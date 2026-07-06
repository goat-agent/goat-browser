// GoatCEF.mm — CEF browser-process bootstrap + multi-tab engine for Goat Browser.
//
// Adapted from CEF's tests/cefsimple (simple_app, simple_handler) and the
// shared external-message-pump message loop. Key differences:
//   * SwiftUI/AppKit owns NSApplication and the main run loop. We therefore do
//     NOT call MainMessageLoop::Run()/CefRunMessageLoop(). Instead we only
//     instantiate the external pump so that OnScheduleMessagePumpWork() can
//     schedule CefDoMessageLoopWork() onto the existing main-thread run loop
//     via NSTimer (see main_message_loop_external_pump_mac.mm).
//   * Windowed rendering into a caller-supplied NSView via CefWindowInfo
//     SetAsChild, rather than the Views framework.
//
// MILESTONE 1: multi-tab. One GoatCEF instance owns a stable container NSView
// and a map of tabId -> CefBrowser (one CEF browser per tab). A single shared
// GoatClient instance services every browser; it carries the engine's id<...>
// delegate (held weakly) and looks up the owning tabId for a given browser. All
// CEF UI-thread callbacks are marshaled to the main queue before touching the
// delegate or the id->browser map (the map is only mutated on the main thread).

#import "GoatCEF.h"

#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/cef_browser.h"
#include "include/cef_client.h"
#include "include/cef_command_line.h"
#include "include/cef_context_menu_handler.h"
#include "include/cef_dialog_handler.h"
#include "include/cef_download_handler.h"
#include "include/cef_find_handler.h"
#include "include/cef_image.h"
#include "include/cef_menu_model.h"
#include "include/cef_parser.h"
#include "include/cef_permission_handler.h"
#include "include/cef_scheme.h"
#include "include/cef_stream.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"
#include "include/wrapper/cef_stream_resource_handler.h"

#import "GoatSchemes.h"
#import "GoatInternalPages.h"

#include "tests/shared/browser/main_message_loop_external_pump.h"

#import <objc/runtime.h>
#import <objc/message.h>

#include <deque>
#include <map>
#include <string>

// Forward declaration of the private engine interface the C++ client calls back
// into. Defined in the @implementation section below.
@interface GoatCEF ()
- (void)onBrowserCreated:(CefRefPtr<CefBrowser>)browser;
- (void)onBrowserClosed:(CefRefPtr<CefBrowser>)browser;
- (NSInteger)tabIdForBrowser:(CefRefPtr<CefBrowser>)browser;
// Permission plumbing: the C++ permission handler stores the CEF callback in the
// engine keyed by a freshly minted reqId, then asks Swift to decide.
- (NSInteger)stashPermissionMediaCallback:(CefRefPtr<CefMediaAccessCallback>)cb
                                  granted:(uint32_t)wantPerms;
- (NSInteger)stashPermissionPromptCallback:(CefRefPtr<CefPermissionPromptCallback>)cb;
- (void)deliverPermissionForTab:(NSInteger)tabId
                           kind:(NSString *)kind
                         origin:(NSString *)origin
                      requestId:(NSInteger)reqId;
- (void)deliverDownloadId:(NSInteger)did
                     name:(NSString *)name
                 received:(long long)r
                    total:(long long)t
                 complete:(BOOL)done
                     path:(NSString *)path;
- (void)deliverFindForBrowser:(CefRefPtr<CefBrowser>)browser
                      current:(NSInteger)current
                        total:(NSInteger)total;
- (void)deliverFaviconForBrowser:(CefRefPtr<CefBrowser>)browser
                            png:(NSData *)png;
@property(nonatomic, weak) id<GoatCEFDelegate> delegate;
@end

namespace {

// Fixed CDP port for the smoke test.
const int kRemoteDebuggingPort = 9222;

// Custom context-menu command ids.
const int kInspectElementCommandId = MENU_ID_USER_FIRST + 1;
const int kOpenLinkNewTabCommandId = MENU_ID_USER_FIRST + 2;
const int kCopyLinkURLCommandId = MENU_ID_USER_FIRST + 3;
const int kSaveImageAsCommandId = MENU_ID_USER_FIRST + 4;
const int kCopyImageURLCommandId = MENU_ID_USER_FIRST + 5;
const int kViewSourceCommandId = MENU_ID_USER_FIRST + 6;
const int kCopyPageURLCommandId = MENU_ID_USER_FIRST + 7;

inline void GoatCopyToPasteboard(const std::string& text) {
  dispatch_async(dispatch_get_main_queue(), ^{
    NSPasteboard* pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard clearContents];
    [pasteboard setString:[NSString stringWithUTF8String:text.c_str()]
                  forType:NSPasteboardTypeString];
  });
}

// Map a bitfield of cef_permission_request_types_t values to a human string.
std::string DescribePermissionTypes(uint32_t perms) {
  struct { uint32_t bit; const char* name; } kMap[] = {
      {CEF_PERMISSION_TYPE_GEOLOCATION, "location"},
      {CEF_PERMISSION_TYPE_NOTIFICATIONS, "notifications"},
      {CEF_PERMISSION_TYPE_CLIPBOARD, "clipboard"},
      {CEF_PERMISSION_TYPE_CAMERA_STREAM, "camera"},
      {CEF_PERMISSION_TYPE_MIC_STREAM, "microphone"},
      {CEF_PERMISSION_TYPE_MIDI_SYSEX, "MIDI"},
      {CEF_PERMISSION_TYPE_IDLE_DETECTION, "idle detection"},
      {CEF_PERMISSION_TYPE_PROTECTED_MEDIA_IDENTIFIER, "protected media"},
      {CEF_PERMISSION_TYPE_STORAGE_ACCESS, "storage access"},
      {CEF_PERMISSION_TYPE_WINDOW_MANAGEMENT, "window management"},
      {CEF_PERMISSION_TYPE_SENSORS, "sensors"},
  };
  std::string out;
  for (const auto& m : kMap) {
    if (perms & m.bit) {
      if (!out.empty()) out += ", ";
      out += m.name;
    }
  }
  return out.empty() ? "permission" : out;
}

// ---------------------------------------------------------------------------
// FaviconDownloadCallback: receives the downloaded CefImage, converts the best
// representation to PNG NSData, and delivers it via the engine on the main
// thread. Used by GoatClient::OnFaviconURLChange.
// ---------------------------------------------------------------------------
class FaviconDownloadCallback : public CefDownloadImageCallback {
 public:
  FaviconDownloadCallback(GoatCEF* engine, CefRefPtr<CefBrowser> browser)
      : engine_(engine), browser_(browser) {}

  void OnDownloadImageFinished(const CefString& image_url,
                               int http_status_code,
                               CefRefPtr<CefImage> image) override {
    CEF_REQUIRE_UI_THREAD();
    NSData* png = nil;
    if (image && !image->IsEmpty()) {
      int pixel_w = 0, pixel_h = 0;
      CefRefPtr<CefBinaryValue> bin =
          image->GetAsPNG(1.0f, /*with_transparency=*/true, pixel_w, pixel_h);
      if (bin && bin->GetSize() > 0) {
        size_t size = bin->GetSize();
        NSMutableData* data = [NSMutableData dataWithLength:size];
        bin->GetData([data mutableBytes], size, 0);
        png = data;
      }
    }
    GoatCEF* engine = engine_;
    CefRefPtr<CefBrowser> browser = browser_;
    dispatch_async(dispatch_get_main_queue(), ^{
      [engine deliverFaviconForBrowser:browser png:png];
    });
  }

 private:
  __weak GoatCEF* engine_;
  CefRefPtr<CefBrowser> browser_;
  IMPLEMENT_REFCOUNTING(FaviconDownloadCallback);
};

// ---------------------------------------------------------------------------
// GoatClient: CefClient + LifeSpan + Load + Display handlers.
//
// A single shared client services every browser/tab. It holds a __weak pointer
// to the owning GoatCEF engine. CEF callbacks run on the UI thread, so we hop
// to the main queue before talking to the engine or its delegate. We pass the
// raw CefRefPtr<CefBrowser> through the hop (it is refcounted and thread-safe to
// retain) and let the engine resolve it back to a tabId on the main thread.
// ---------------------------------------------------------------------------
class GoatClient : public CefClient,
                   public CefLifeSpanHandler,
                   public CefLoadHandler,
                   public CefDisplayHandler,
                   public CefPermissionHandler,
                   public CefDialogHandler,
                   public CefDownloadHandler,
                   public CefFindHandler,
                   public CefContextMenuHandler {
 public:
  explicit GoatClient(GoatCEF* engine) : engine_(engine) {}

  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefPermissionHandler> GetPermissionHandler() override { return this; }
  CefRefPtr<CefDialogHandler> GetDialogHandler() override { return this; }
  CefRefPtr<CefDownloadHandler> GetDownloadHandler() override { return this; }
  CefRefPtr<CefFindHandler> GetFindHandler() override { return this; }
  CefRefPtr<CefContextMenuHandler> GetContextMenuHandler() override {
    return this;
  }

  // CefLifeSpanHandler ------------------------------------------------------
  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    CEF_REQUIRE_UI_THREAD();
    GoatCEF* engine = engine_;
    dispatch_async(dispatch_get_main_queue(), ^{
      [engine onBrowserCreated:browser];
    });
  }

  bool DoClose(CefRefPtr<CefBrowser> browser) override {
    CEF_REQUIRE_UI_THREAD();
    return false;  // Allow OS close.
  }

  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
    CEF_REQUIRE_UI_THREAD();
    GoatCEF* engine = engine_;
    dispatch_async(dispatch_get_main_queue(), ^{
      [engine onBrowserClosed:browser];
    });
  }

  bool OnBeforePopup(CefRefPtr<CefBrowser> browser,
                     CefRefPtr<CefFrame> frame,
                     int popup_id,
                     const CefString& target_url,
                     const CefString& target_frame_name,
                     WindowOpenDisposition target_disposition,
                     bool user_gesture,
                     const CefPopupFeatures& popupFeatures,
                     CefWindowInfo& windowInfo,
                     CefRefPtr<CefClient>& client,
                     CefBrowserSettings& settings,
                     CefRefPtr<CefDictionaryValue>& extra_info,
                     bool* no_javascript_access) override {
    CEF_REQUIRE_UI_THREAD();
    // Cancel the native popup and route the URL to a new Swift-managed tab.
    std::string url(target_url);
    GoatCEF* engine = engine_;
    dispatch_async(dispatch_get_main_queue(), ^{
      id<GoatCEFDelegate> delegate = engine.delegate;
      if (delegate && !url.empty()) {
        [delegate tabDidRequestNewTabWithURL:
            [NSString stringWithUTF8String:url.c_str()]];
      }
    });
    return true;  // true = cancel the popup.
  }

  // CefLoadHandler ----------------------------------------------------------
  void OnLoadingStateChange(CefRefPtr<CefBrowser> browser,
                            bool isLoading,
                            bool canGoBack,
                            bool canGoForward) override {
    CEF_REQUIRE_UI_THREAD();
    GoatCEF* engine = engine_;
    dispatch_async(dispatch_get_main_queue(), ^{
      NSInteger tabId = [engine tabIdForBrowser:browser];
      if (tabId < 0) return;
      id<GoatCEFDelegate> delegate = engine.delegate;
      [delegate tab:tabId
          didChangeLoading:isLoading
                 canGoBack:canGoBack
              canGoForward:canGoForward];
    });
  }

  void OnLoadError(CefRefPtr<CefBrowser> browser,
                   CefRefPtr<CefFrame> frame,
                   ErrorCode errorCode,
                   const CefString& errorText,
                   const CefString& failedUrl) override {
    CEF_REQUIRE_UI_THREAD();
    if (errorCode == ERR_ABORTED) {
      return;
    }
    if (!frame || !frame->IsMain()) {
      return;
    }
    std::string failed = failedUrl.ToString();
    if (failed.rfind("goat://error", 0) == 0) {
      return;
    }
    std::string target = "goat://error?url=" +
        CefURIEncode(failedUrl, false).ToString() + "&text=" +
        CefURIEncode(errorText, false).ToString();
    frame->LoadURL(target);
  }

  void OnLoadingProgressChange(CefRefPtr<CefBrowser> browser,
                               double progress) override {
    CEF_REQUIRE_UI_THREAD();
    GoatCEF* engine = engine_;
    dispatch_async(dispatch_get_main_queue(), ^{
      NSInteger tabId = [engine tabIdForBrowser:browser];
      if (tabId < 0) return;
      [engine.delegate tab:tabId didChangeLoadProgress:progress];
    });
  }

  // CefDisplayHandler -------------------------------------------------------
  void OnAddressChange(CefRefPtr<CefBrowser> browser,
                       CefRefPtr<CefFrame> frame,
                       const CefString& url) override {
    CEF_REQUIRE_UI_THREAD();
    if (!frame->IsMain()) {
      return;
    }
    std::string u(url);
    GoatCEF* engine = engine_;
    dispatch_async(dispatch_get_main_queue(), ^{
      NSInteger tabId = [engine tabIdForBrowser:browser];
      if (tabId < 0) return;
      id<GoatCEFDelegate> delegate = engine.delegate;
      [delegate tab:tabId
          didChangeURL:[NSString stringWithUTF8String:u.c_str()]];
    });
  }

  void OnTitleChange(CefRefPtr<CefBrowser> browser,
                     const CefString& title) override {
    CEF_REQUIRE_UI_THREAD();
    std::string t(title);
    GoatCEF* engine = engine_;
    dispatch_async(dispatch_get_main_queue(), ^{
      NSInteger tabId = [engine tabIdForBrowser:browser];
      if (tabId < 0) return;
      id<GoatCEFDelegate> delegate = engine.delegate;
      [delegate tab:tabId
          didChangeTitle:[NSString stringWithUTF8String:t.c_str()]];
    });
  }

  void OnFaviconURLChange(CefRefPtr<CefBrowser> browser,
                          const std::vector<CefString>& icon_urls) override {
    CEF_REQUIRE_UI_THREAD();
    GoatCEF* engine = engine_;
    if (icon_urls.empty()) {
      // No favicon advertised; deliver nil so the UI falls back to a globe.
      dispatch_async(dispatch_get_main_queue(), ^{
        [engine deliverFaviconForBrowser:browser png:nil];
      });
      return;
    }
    // Download the first advertised favicon and convert CefImage -> PNG.
    // The callback runs on the UI thread; we hop to main before the delegate.
    CefRefPtr<CefDownloadImageCallback> cb =
        new FaviconDownloadCallback(engine, browser);
    browser->GetHost()->DownloadImage(icon_urls.front(), /*is_favicon=*/true,
                                      /*max_image_size=*/64,
                                      /*bypass_cache=*/false, cb);
  }

  // CefPermissionHandler ----------------------------------------------------
  bool OnRequestMediaAccessPermission(
      CefRefPtr<CefBrowser> browser,
      CefRefPtr<CefFrame> frame,
      const CefString& requesting_origin,
      uint32_t requested_permissions,
      CefRefPtr<CefMediaAccessCallback> callback) override {
    CEF_REQUIRE_UI_THREAD();
    std::string origin(requesting_origin);
    // Compose a human "kind" describing the audio/video request and the set of
    // permission bits we should grant if Swift says yes.
    bool wantAudio =
        (requested_permissions & CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE) != 0;
    bool wantVideo =
        (requested_permissions & CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE) != 0;
    std::string kind;
    if (wantAudio && wantVideo) {
      kind = "camera & microphone";
    } else if (wantVideo) {
      kind = "camera";
    } else if (wantAudio) {
      kind = "microphone";
    } else {
      kind = "media";
    }
    NSLog(@"[GoatCEF] OnRequestMediaAccessPermission origin=%s perms=0x%x (%s)",
          origin.c_str(), requested_permissions, kind.c_str());
    GoatCEF* engine = engine_;
    uint32_t grantBits = requested_permissions;
    std::string kindCopy = kind;
    dispatch_async(dispatch_get_main_queue(), ^{
      NSInteger tabId = [engine tabIdForBrowser:browser];
      NSInteger reqId =
          [engine stashPermissionMediaCallback:callback granted:grantBits];
      [engine deliverPermissionForTab:tabId
                                 kind:[NSString stringWithUTF8String:kindCopy.c_str()]
                               origin:[NSString stringWithUTF8String:origin.c_str()]
                            requestId:reqId];
    });
    return true;  // We will resolve the callback asynchronously.
  }

  bool OnShowPermissionPrompt(
      CefRefPtr<CefBrowser> browser,
      uint64_t prompt_id,
      const CefString& requesting_origin,
      uint32_t requested_permissions,
      CefRefPtr<CefPermissionPromptCallback> callback) override {
    CEF_REQUIRE_UI_THREAD();
    std::string origin(requesting_origin);
    std::string kind = DescribePermissionTypes(requested_permissions);
    NSLog(@"[GoatCEF] OnShowPermissionPrompt origin=%s perms=0x%x (%s)",
          origin.c_str(), requested_permissions, kind.c_str());
    GoatCEF* engine = engine_;
    std::string kindCopy = kind;
    dispatch_async(dispatch_get_main_queue(), ^{
      NSInteger tabId = [engine tabIdForBrowser:browser];
      NSInteger reqId = [engine stashPermissionPromptCallback:callback];
      [engine deliverPermissionForTab:tabId
                                 kind:[NSString stringWithUTF8String:kindCopy.c_str()]
                               origin:[NSString stringWithUTF8String:origin.c_str()]
                            requestId:reqId];
    });
    return true;  // Resolve asynchronously via CefPermissionPromptCallback.
  }

  // CefDialogHandler --------------------------------------------------------
  // Show a native NSOpenPanel/NSSavePanel entirely in the bridge on the main
  // thread; no Swift round-trip needed. Returns true (custom handling).
  bool OnFileDialog(CefRefPtr<CefBrowser> browser,
                    FileDialogMode mode,
                    const CefString& title,
                    const CefString& default_file_path,
                    const std::vector<CefString>& accept_filters,
                    const std::vector<CefString>& accept_extensions,
                    const std::vector<CefString>& accept_descriptions,
                    CefRefPtr<CefFileDialogCallback> callback) override {
    CEF_REQUIRE_UI_THREAD();
    NSLog(@"[GoatCEF] OnFileDialog mode=%d title=%s", (int)mode,
          std::string(title).c_str());
    // Collect extension filters from accept_extensions (semicolon-delimited).
    NSMutableArray<NSString*>* exts = [NSMutableArray array];
    for (const auto& e : accept_extensions) {
      std::string s(e);
      // Split on ';'
      size_t start = 0;
      while (start <= s.size()) {
        size_t pos = s.find(';', start);
        std::string token = s.substr(
            start, pos == std::string::npos ? std::string::npos : pos - start);
        if (!token.empty()) {
          if (token[0] == '.') token = token.substr(1);
          if (!token.empty())
            [exts addObject:[NSString stringWithUTF8String:token.c_str()]];
        }
        if (pos == std::string::npos) break;
        start = pos + 1;
      }
    }
    std::string defPath(default_file_path);
    NSString* defNS =
        defPath.empty() ? nil : [NSString stringWithUTF8String:defPath.c_str()];
    int modeInt = (int)mode;

    dispatch_async(dispatch_get_main_queue(), ^{
      std::vector<CefString> result;
      if (modeInt == FILE_DIALOG_SAVE) {
        NSSavePanel* panel = [NSSavePanel savePanel];
        if (defNS) panel.nameFieldStringValue = [defNS lastPathComponent];
        if ([panel runModal] == NSModalResponseOK && panel.URL) {
          result.push_back(CefString([panel.URL.path UTF8String]));
        }
      } else {
        NSOpenPanel* panel = [NSOpenPanel openPanel];
        panel.canChooseFiles = (modeInt != FILE_DIALOG_OPEN_FOLDER);
        panel.canChooseDirectories = (modeInt == FILE_DIALOG_OPEN_FOLDER);
        panel.allowsMultipleSelection = (modeInt == FILE_DIALOG_OPEN_MULTIPLE);
        if (exts.count > 0 && modeInt != FILE_DIALOG_OPEN_FOLDER) {
          panel.allowedFileTypes = exts;  // best-effort; deprecated but works.
        }
        if ([panel runModal] == NSModalResponseOK) {
          for (NSURL* url in panel.URLs) {
            result.push_back(CefString([url.path UTF8String]));
          }
        }
      }
      if (result.empty()) {
        callback->Cancel();
      } else {
        callback->Continue(result);
      }
    });
    return true;  // custom handling
  }

  // CefDownloadHandler ------------------------------------------------------
  bool CanDownload(CefRefPtr<CefBrowser> browser,
                   const CefString& url,
                   const CefString& request_method) override {
    return true;  // Allow all downloads.
  }

  bool OnBeforeDownload(CefRefPtr<CefBrowser> browser,
                        CefRefPtr<CefDownloadItem> download_item,
                        const CefString& suggested_name,
                        CefRefPtr<CefBeforeDownloadCallback> callback) override {
    CEF_REQUIRE_UI_THREAD();
    // Always save to ~/Downloads/<suggestedName>, no prompt.
    std::string name(suggested_name);
    NSString* nameNS = [NSString stringWithUTF8String:name.c_str()];
    NSString* downloads = [NSSearchPathForDirectoriesInDomains(
        NSDownloadsDirectory, NSUserDomainMask, YES) firstObject];
    NSString* dest = [downloads stringByAppendingPathComponent:nameNS];
    NSLog(@"[GoatCEF] OnBeforeDownload -> %@", dest);
    callback->Continue(CefString([dest UTF8String]), /*show_dialog=*/false);
    return true;
  }

  void OnDownloadUpdated(CefRefPtr<CefBrowser> browser,
                         CefRefPtr<CefDownloadItem> download_item,
                         CefRefPtr<CefDownloadItemCallback> callback) override {
    CEF_REQUIRE_UI_THREAD();
    NSInteger did = (NSInteger)download_item->GetId();
    std::string name(download_item->GetSuggestedFileName());
    std::string full(download_item->GetFullPath());
    long long received = download_item->GetReceivedBytes();
    long long total = download_item->GetTotalBytes();
    bool complete = download_item->IsComplete();
    GoatCEF* engine = engine_;
    dispatch_async(dispatch_get_main_queue(), ^{
      [engine deliverDownloadId:did
                           name:[NSString stringWithUTF8String:name.c_str()]
                       received:received
                          total:total
                       complete:complete
                           path:[NSString stringWithUTF8String:full.c_str()]];
    });
  }

  // CefFindHandler ----------------------------------------------------------
  void OnFindResult(CefRefPtr<CefBrowser> browser,
                    int identifier,
                    int count,
                    const CefRect& selectionRect,
                    int activeMatchOrdinal,
                    bool finalUpdate) override {
    CEF_REQUIRE_UI_THREAD();
    GoatCEF* engine = engine_;
    dispatch_async(dispatch_get_main_queue(), ^{
      [engine deliverFindForBrowser:browser
                            current:activeMatchOrdinal
                              total:count];
    });
  }

  // CefContextMenuHandler ---------------------------------------------------
  void OnBeforeContextMenu(CefRefPtr<CefBrowser> browser,
                           CefRefPtr<CefFrame> frame,
                           CefRefPtr<CefContextMenuParams> params,
                           CefRefPtr<CefMenuModel> model) override {
    CEF_REQUIRE_UI_THREAD();
    const bool hasLink = !params->GetLinkUrl().empty();
    const bool isImage = params->GetMediaType() == CM_MEDIATYPE_IMAGE &&
                         !params->GetSourceUrl().empty();
    if (model->GetCount() > 0) {
      model->AddSeparator();
    }
    if (hasLink) {
      model->AddItem(kOpenLinkNewTabCommandId, "Open Link in New Tab");
      model->AddItem(kCopyLinkURLCommandId, "Copy Link Address");
    }
    if (isImage) {
      model->AddItem(kSaveImageAsCommandId, "Save Image As…");
      model->AddItem(kCopyImageURLCommandId, "Copy Image Address");
    }
    model->AddItem(kCopyPageURLCommandId, "Copy Page URL");
    model->AddItem(kViewSourceCommandId, "View Page Source");
    model->AddSeparator();
    model->AddItem(kInspectElementCommandId, "Inspect Element");
  }

  bool OnContextMenuCommand(CefRefPtr<CefBrowser> browser,
                            CefRefPtr<CefFrame> frame,
                            CefRefPtr<CefContextMenuParams> params,
                            int command_id,
                            EventFlags event_flags) override {
    CEF_REQUIRE_UI_THREAD();
    GoatCEF* engine = engine_;
    switch (command_id) {
      case kInspectElementCommandId: {
        CefWindowInfo window_info;
        CefBrowserSettings settings;
        browser->GetHost()->ShowDevTools(window_info, this, settings,
                                         CefPoint(params->GetXCoord(),
                                                  params->GetYCoord()));
        return true;
      }
      case kOpenLinkNewTabCommandId: {
        std::string link = params->GetLinkUrl().ToString();
        dispatch_async(dispatch_get_main_queue(), ^{
          [engine.delegate tabDidRequestNewTabWithURL:
              [NSString stringWithUTF8String:link.c_str()]];
        });
        return true;
      }
      case kCopyLinkURLCommandId:
        GoatCopyToPasteboard(params->GetLinkUrl().ToString());
        return true;
      case kCopyImageURLCommandId:
        GoatCopyToPasteboard(params->GetSourceUrl().ToString());
        return true;
      case kSaveImageAsCommandId:
        browser->GetHost()->StartDownload(params->GetSourceUrl());
        return true;
      case kCopyPageURLCommandId:
        GoatCopyToPasteboard(frame->GetURL().ToString());
        return true;
      case kViewSourceCommandId: {
        std::string vs = "view-source:" + frame->GetURL().ToString();
        dispatch_async(dispatch_get_main_queue(), ^{
          [engine.delegate tabDidRequestNewTabWithURL:
              [NSString stringWithUTF8String:vs.c_str()]];
        });
        return true;
      }
    }
    return false;
  }

 private:
  __weak GoatCEF* engine_;
  IMPLEMENT_REFCOUNTING(GoatClient);
};

// ---------------------------------------------------------------------------
class GoatSchemeHandlerFactory : public CefSchemeHandlerFactory {
 public:
  CefRefPtr<CefResourceHandler> Create(CefRefPtr<CefBrowser> browser,
                                       CefRefPtr<CefFrame> frame,
                                       const CefString& scheme_name,
                                       CefRefPtr<CefRequest> request) override {
    CefURLParts parts;
    std::string host;
    if (CefParseURL(request->GetURL(), parts)) {
      host = CefString(&parts.host).ToString();
    }
    std::string html = GoatInternalPageHTML(host);
    CefRefPtr<CefStreamReader> stream =
        CefStreamReader::CreateForData(const_cast<char*>(html.data()), html.size());
    return new CefStreamResourceHandler("text/html", stream);
  }

 private:
  IMPLEMENT_REFCOUNTING(GoatSchemeHandlerFactory);
};

// GoatApp: CefApp + CefBrowserProcessHandler. Enables the external pump.
// ---------------------------------------------------------------------------
class GoatApp : public CefApp, public CefBrowserProcessHandler {
 public:
  GoatApp() = default;

  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override {
    return this;
  }

  void OnBeforeCommandLineProcessing(const CefString& process_type,
                                     CefRefPtr<CefCommandLine> command_line) override {
    command_line->AppendSwitchWithValue("password-store", "basic");
    command_line->AppendSwitch("use-mock-keychain");
  }

  void OnRegisterCustomSchemes(CefRawPtr<CefSchemeRegistrar> registrar) override {
    GoatRegisterCustomSchemes(registrar);
  }

  // CefBrowserProcessHandler
  void OnContextInitialized() override {
    CEF_REQUIRE_UI_THREAD();
    CefRegisterSchemeHandlerFactory("goat", "", new GoatSchemeHandlerFactory());
  }

  // The heart of external_message_pump: forward to the shared pump, which
  // schedules CefDoMessageLoopWork() on the main thread's run loop.
  void OnScheduleMessagePumpWork(int64_t delay_ms) override {
    auto* pump = client::MainMessageLoopExternalPump::Get();
    if (pump) {
      pump->OnScheduleMessagePumpWork(delay_ms);
    }
  }

 private:
  IMPLEMENT_REFCOUNTING(GoatApp);
};

// Global state for the browser-process bootstrap (process-wide singletons).
CefRefPtr<GoatApp> g_app;
std::unique_ptr<client::MainMessageLoopExternalPump> g_message_loop;
bool g_initialized = false;

}  // namespace

// ---------------------------------------------------------------------------
// CefAppProtocol bring-up under SwiftUI.
//
// CEF on macOS requires NSApp to be an NSApplication subclass conforming to
// CefAppProtocol (implementing -isHandlingSendEvent / -setHandlingSendEvent:)
// and to wrap -sendEvent: in a CefScopedSendingEvent. SwiftUI, however, owns
// NSApplication and installs its own private subclass (SwiftUI.AppKitApplication),
// ignoring Info.plist's NSPrincipalClass. We therefore patch the *actual* NSApp
// class at runtime: add the two protocol methods (state stored in an associated
// object), swizzle -sendEvent:, and declare CefAppProtocol conformance.
// ---------------------------------------------------------------------------

static const void* kGoatHandlingSendEventKey = &kGoatHandlingSendEventKey;
static IMP g_originalSendEvent = nullptr;

static BOOL Goat_isHandlingSendEvent(id self, SEL _cmd) {
  NSNumber* v = objc_getAssociatedObject(self, kGoatHandlingSendEventKey);
  return [v boolValue];
}

static void Goat_setHandlingSendEvent(id self, SEL _cmd, BOOL handling) {
  objc_setAssociatedObject(self, kGoatHandlingSendEventKey,
                           @(handling), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void Goat_sendEvent(id self, SEL _cmd, NSEvent* event) {
  CefScopedSendingEvent sendingEventScoper;
  if (g_originalSendEvent) {
    ((void (*)(id, SEL, NSEvent*))g_originalSendEvent)(self, _cmd, event);
  }
}

// Patch NSApp's class so it satisfies CefAppProtocol. Safe to call once on the
// main thread after NSApplication exists. Returns NO if NSApp is missing.
static BOOL GoatPatchNSAppForCEF() {
  if (!NSApp) {
    return NO;
  }
  Class cls = [NSApp class];

  // Avoid double-patching.
  if (class_getInstanceMethod(cls, @selector(isHandlingSendEvent)) &&
      objc_getAssociatedObject(NSApp, &g_originalSendEvent) != nil) {
    return YES;
  }

  // 1. Add the CrAppControlProtocol methods if not already present.
  if (!class_getInstanceMethod(cls, @selector(isHandlingSendEvent))) {
    class_addMethod(cls, @selector(isHandlingSendEvent),
                    (IMP)Goat_isHandlingSendEvent, "c@:");
  }
  if (!class_getInstanceMethod(cls, @selector(setHandlingSendEvent:))) {
    class_addMethod(cls, @selector(setHandlingSendEvent:),
                    (IMP)Goat_setHandlingSendEvent, "v@:c");
  }

  // 2. Declare CefAppProtocol conformance so CEF's protocol check passes.
  Protocol* proto = @protocol(CefAppProtocol);
  if (proto) {
    class_addProtocol(cls, proto);
  }

  // 3. Swizzle -sendEvent: to wrap in CefScopedSendingEvent.
  Method m = class_getInstanceMethod(cls, @selector(sendEvent:));
  if (m && g_originalSendEvent == nullptr) {
    g_originalSendEvent = method_getImplementation(m);
    method_setImplementation(m, (IMP)Goat_sendEvent);
    // Marker so we don't re-swizzle.
    objc_setAssociatedObject(NSApp, &g_originalSendEvent, @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
  }

  return YES;
}

// ---------------------------------------------------------------------------
// GoatCEF — the engine instance.
// ---------------------------------------------------------------------------
@implementation GoatCEF {
  NSView* _container;                       // Stable container, strongly held.
  CefRefPtr<GoatClient> _client;            // Shared client for all browsers.
  std::map<NSInteger, CefRefPtr<CefBrowser>>* _browsers;  // tabId -> browser.
  std::deque<NSInteger>* _pendingTabIds;     // FIFO of tabIds awaiting OnAfterCreated.
  NSInteger _activeTabId;                    // Currently visible tab, or -1.

  // Pending permission callbacks keyed by a monotonically increasing reqId. Two
  // maps because the two CEF callback flavors are distinct types. We also stash
  // the media grant bitmask so we can grant exactly what was requested.
  std::map<NSInteger, CefRefPtr<CefMediaAccessCallback>>* _mediaCallbacks;
  std::map<NSInteger, uint32_t>* _mediaGrantBits;
  std::map<NSInteger, CefRefPtr<CefPermissionPromptCallback>>* _promptCallbacks;
  NSInteger _nextReqId;
}

@synthesize delegate = _delegate;

+ (BOOL)initializeCEF {
  if (g_initialized) {
    return YES;
  }

  // Ensure NSApp satisfies CefAppProtocol. SwiftUI installs its own private
  // NSApplication subclass that ignores NSPrincipalClass, so we patch it at
  // runtime rather than requiring a specific subclass.
  if (!GoatPatchNSAppForCEF()) {
    NSLog(@"[GoatCEF] FATAL: NSApp missing; cannot patch for CefAppProtocol.");
    return NO;
  }

  // Load the CEF framework library at runtime (main process).
  static CefScopedLibraryLoader* loader = new CefScopedLibraryLoader();
  if (!loader->LoadInMain()) {
    NSLog(@"[GoatCEF] FATAL: LoadInMain() failed.");
    return NO;
  }

  // Create the external message-pump message loop on the main thread. This
  // must exist before CefInitialize so OnScheduleMessagePumpWork can use it.
  g_message_loop = client::MainMessageLoopExternalPump::Create();

  CefMainArgs main_args(0, nullptr);

  CefSettings settings;
  settings.no_sandbox = true;               // SANDBOX OFF for first bring-up.
  settings.external_message_pump = true;    // Drive via OnScheduleMessagePumpWork.
  settings.remote_debugging_port = kRemoteDebuggingPort;  // CDP on 127.0.0.1.

  // Use a per-app cache path under Application Support to avoid the default
  // shared CEF location and its process-singleton warning.
  NSString* appSupport = [NSSearchPathForDirectoriesInDomains(
      NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
  if (appSupport) {
    NSString* cachePath =
        [appSupport stringByAppendingPathComponent:@"Goat Browser"];
    [[NSFileManager defaultManager] createDirectoryAtPath:cachePath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    CefString(&settings.root_cache_path).FromString([cachePath UTF8String]);
  }

  g_app = new GoatApp();

  if (!CefInitialize(main_args, settings, g_app.get(), nullptr)) {
    NSLog(@"[GoatCEF] FATAL: CefInitialize failed, exit code %d",
          CefGetExitCode());
    return NO;
  }

  g_initialized = true;
  NSLog(@"[GoatCEF] CEF initialized (external pump, no sandbox, CDP %d).",
        kRemoteDebuggingPort);
  return YES;
}

+ (BOOL)isInitialized {
  return g_initialized;
}

+ (void)shutdown {
  if (!g_initialized) {
    return;
  }
  CefShutdown();
  g_message_loop.reset();
  g_initialized = false;
}

- (instancetype)initWithContainer:(NSView *)container
                         delegate:(id<GoatCEFDelegate>)delegate {
  self = [super init];
  if (self) {
    _container = container;
    _delegate = delegate;
    _browsers = new std::map<NSInteger, CefRefPtr<CefBrowser>>();
    _pendingTabIds = new std::deque<NSInteger>();
    _activeTabId = -1;
    _mediaCallbacks = new std::map<NSInteger, CefRefPtr<CefMediaAccessCallback>>();
    _mediaGrantBits = new std::map<NSInteger, uint32_t>();
    _promptCallbacks = new std::map<NSInteger, CefRefPtr<CefPermissionPromptCallback>>();
    _nextReqId = 1;
    _client = new GoatClient(self);
  }
  return self;
}

- (void)dealloc {
  // Close any remaining browsers and free the map.
  if (_browsers) {
    for (auto& kv : *_browsers) {
      if (kv.second) {
        kv.second->GetHost()->CloseBrowser(true);
      }
    }
    delete _browsers;
    _browsers = nullptr;
  }
  if (_pendingTabIds) {
    delete _pendingTabIds;
    _pendingTabIds = nullptr;
  }
  if (_mediaCallbacks) {
    delete _mediaCallbacks;
    _mediaCallbacks = nullptr;
  }
  if (_mediaGrantBits) {
    delete _mediaGrantBits;
    _mediaGrantBits = nullptr;
  }
  if (_promptCallbacks) {
    delete _promptCallbacks;
    _promptCallbacks = nullptr;
  }
}

- (void)createTabWithId:(NSInteger)tabId url:(NSString *)url {
  if (!g_initialized) {
    NSLog(@"[GoatCEF] createTabWithId called before initializeCEF; ignoring.");
    return;
  }
  if (!_container) {
    return;
  }
  if (_browsers->find(tabId) != _browsers->end()) {
    return;  // Already exists.
  }
  // Guard against a duplicate creation while a previous create for this tab is
  // still in flight (queued but OnAfterCreated not yet delivered).
  for (NSInteger pending : *_pendingTabIds) {
    if (pending == tabId) {
      return;
    }
  }

  CefWindowInfo window_info;
  NSRect bounds = [_container bounds];
  CefRect cef_bounds(0, 0, static_cast<int>(bounds.size.width),
                     static_cast<int>(bounds.size.height));
  // Windowed rendering: parent the CEF browser into our stable container view.
  window_info.SetAsChild(CAST_NSVIEW_TO_CEF_WINDOW_HANDLE(_container),
                         cef_bounds);
  window_info.runtime_style = CEF_RUNTIME_STYLE_ALLOY;
  // New browsers start hidden until activated, so switching is visibility-only.
  window_info.hidden = true;

  CefBrowserSettings browser_settings;
  std::string url_str([url UTF8String]);

  // Record the intended tabId so OnAfterCreated can resolve which tab a freshly
  // created browser belongs to. CreateBrowser->OnAfterCreated preserves order,
  // and all creation happens on the main thread, so a FIFO queue is safe. (CEF
  // does not expose extra_info back to the browser process, so we cannot stash
  // the id in the browser itself.)
  _pendingTabIds->push_back(tabId);

  CefBrowserHost::CreateBrowser(window_info, _client, url_str, browser_settings,
                                nullptr, nullptr);
  NSLog(@"[GoatCEF] CreateBrowser requested for tab %ld -> %@",
        (long)tabId, url);
}

- (void)closeTab:(NSInteger)tabId {
  auto it = _browsers->find(tabId);
  if (it == _browsers->end()) {
    return;
  }
  CefRefPtr<CefBrowser> browser = it->second;
  if (browser) {
    browser->GetHost()->CloseBrowser(true);
  }
  // The map entry is erased in onBrowserClosed: once CEF tears down.
  if (_activeTabId == tabId) {
    _activeTabId = -1;
  }
}

static void ApplyCardCorners(NSView* view) {
  if (!view) return;
  view.wantsLayer = YES;
  view.layer.cornerRadius = 10.0;
  view.layer.cornerCurve = kCACornerCurveContinuous;
  view.layer.masksToBounds = YES;
  for (NSView* sub in view.subviews) {
    sub.wantsLayer = YES;
    sub.layer.cornerRadius = 10.0;
    sub.layer.cornerCurve = kCACornerCurveContinuous;
    sub.layer.masksToBounds = YES;
  }
}

- (void)activateTab:(NSInteger)tabId {
  _activeTabId = tabId;
  for (auto& kv : *_browsers) {
    CefRefPtr<CefBrowser> browser = kv.second;
    if (!browser) continue;
    NSView* view = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(
        browser->GetHost()->GetWindowHandle());
    if (!view) continue;
    BOOL isActive = (kv.first == tabId);
    [view setHidden:!isActive];
    if (isActive) {
      [view setFrame:[_container bounds]];
      ApplyCardCorners(view);
    }
  }
}

- (void)resizeActiveToContainer {
  if (_activeTabId < 0) {
    return;
  }
  auto it = _browsers->find(_activeTabId);
  if (it == _browsers->end() || !it->second) {
    return;
  }
  NSView* view = CAST_CEF_WINDOW_HANDLE_TO_NSVIEW(
      it->second->GetHost()->GetWindowHandle());
  if (view) {
    [view setFrame:[_container bounds]];
    ApplyCardCorners(view);
  }
}

- (void)loadURL:(NSString *)url inTab:(NSInteger)tabId {
  auto it = _browsers->find(tabId);
  if (it == _browsers->end() || !it->second) {
    return;
  }
  std::string u([url UTF8String]);
  it->second->GetMainFrame()->LoadURL(u);
}

- (void)goBack:(NSInteger)tabId {
  auto it = _browsers->find(tabId);
  if (it != _browsers->end() && it->second) {
    it->second->GoBack();
  }
}

- (void)goForward:(NSInteger)tabId {
  auto it = _browsers->find(tabId);
  if (it != _browsers->end() && it->second) {
    it->second->GoForward();
  }
}

- (void)reload:(NSInteger)tabId {
  auto it = _browsers->find(tabId);
  if (it != _browsers->end() && it->second) {
    it->second->Reload();
  }
}

- (void)stopLoad:(NSInteger)tabId {
  auto it = _browsers->find(tabId);
  if (it != _browsers->end() && it->second) {
    it->second->StopLoad();
  }
}

- (void)showDevTools:(NSInteger)tabId {
  auto it = _browsers->find(tabId);
  if (it == _browsers->end() || !it->second) {
    return;
  }
  CefWindowInfo window_info;
  CefBrowserSettings settings;
  it->second->GetHost()->ShowDevTools(window_info, _client, settings,
                                      CefPoint());
}

// --- Permissions -----------------------------------------------------------

- (NSInteger)stashPermissionMediaCallback:(CefRefPtr<CefMediaAccessCallback>)cb
                                  granted:(uint32_t)wantPerms {
  NSInteger reqId = _nextReqId++;
  (*_mediaCallbacks)[reqId] = cb;
  (*_mediaGrantBits)[reqId] = wantPerms;
  return reqId;
}

- (NSInteger)stashPermissionPromptCallback:(CefRefPtr<CefPermissionPromptCallback>)cb {
  NSInteger reqId = _nextReqId++;
  (*_promptCallbacks)[reqId] = cb;
  return reqId;
}

- (void)deliverPermissionForTab:(NSInteger)tabId
                           kind:(NSString *)kind
                         origin:(NSString *)origin
                      requestId:(NSInteger)reqId {
  id<GoatCEFDelegate> delegate = _delegate;
  if (!delegate) {
    // No delegate to decide — deny safely.
    [self respondToPermission:reqId granted:NO];
    return;
  }
  [delegate tab:tabId requestPermission:kind origin:origin requestId:reqId];
}

- (void)respondToPermission:(NSInteger)reqId granted:(BOOL)granted {
  // Media callback?
  auto mit = _mediaCallbacks->find(reqId);
  if (mit != _mediaCallbacks->end()) {
    CefRefPtr<CefMediaAccessCallback> cb = mit->second;
    uint32_t bits = 0;
    auto bit = _mediaGrantBits->find(reqId);
    if (bit != _mediaGrantBits->end()) bits = bit->second;
    _mediaCallbacks->erase(mit);
    _mediaGrantBits->erase(reqId);
    if (cb) {
      if (granted) {
        cb->Continue(bits);
      } else {
        cb->Continue(CEF_MEDIA_PERMISSION_NONE);
      }
    }
    return;
  }
  // Prompt callback?
  auto pit = _promptCallbacks->find(reqId);
  if (pit != _promptCallbacks->end()) {
    CefRefPtr<CefPermissionPromptCallback> cb = pit->second;
    _promptCallbacks->erase(pit);
    if (cb) {
      cb->Continue(granted ? CEF_PERMISSION_RESULT_ACCEPT
                           : CEF_PERMISSION_RESULT_DENY);
    }
    return;
  }
}

// --- Find-in-page ----------------------------------------------------------

- (void)find:(NSString *)text tab:(NSInteger)tabId forward:(BOOL)forward {
  auto it = _browsers->find(tabId);
  if (it == _browsers->end() || !it->second) {
    return;
  }
  std::string s([text UTF8String]);
  // findNext is true once a search is active; CEF restarts when text changes,
  // so passing true for follow-ups (forward/back) is correct, and a fresh first
  // call with new text also works because CEF detects the text change.
  it->second->GetHost()->Find(s, forward, /*matchCase=*/false,
                              /*findNext=*/true);
}

- (void)stopFind:(NSInteger)tabId clearSelection:(BOOL)clear {
  auto it = _browsers->find(tabId);
  if (it == _browsers->end() || !it->second) {
    return;
  }
  it->second->GetHost()->StopFinding(clear);
}

- (void)deliverFindForBrowser:(CefRefPtr<CefBrowser>)browser
                      current:(NSInteger)current
                        total:(NSInteger)total {
  NSInteger tabId = [self tabIdForBrowser:browser];
  if (tabId < 0) return;
  id<GoatCEFDelegate> delegate = _delegate;
  [delegate tab:tabId didUpdateFindMatches:current of:total];
}

// --- Zoom ------------------------------------------------------------------

- (void)setZoom:(double)level tab:(NSInteger)tabId {
  auto it = _browsers->find(tabId);
  if (it == _browsers->end() || !it->second) {
    return;
  }
  it->second->GetHost()->SetZoomLevel(level);
}

- (double)zoom:(NSInteger)tabId {
  auto it = _browsers->find(tabId);
  if (it == _browsers->end() || !it->second) {
    return 0.0;
  }
  return it->second->GetHost()->GetZoomLevel();
}

// --- Downloads + Favicon delivery ------------------------------------------

- (void)deliverDownloadId:(NSInteger)did
                     name:(NSString *)name
                 received:(long long)r
                    total:(long long)t
                 complete:(BOOL)done
                     path:(NSString *)path {
  id<GoatCEFDelegate> delegate = _delegate;
  [delegate downloadDidUpdateId:did
                       fileName:name
                  receivedBytes:r
                     totalBytes:t
                       complete:done
                           path:path];
}

- (void)deliverFaviconForBrowser:(CefRefPtr<CefBrowser>)browser
                            png:(NSData *)png {
  NSInteger tabId = [self tabIdForBrowser:browser];
  if (tabId < 0) return;
  id<GoatCEFDelegate> delegate = _delegate;
  [delegate tab:tabId didChangeFavicon:png];
}

// --- Called from GoatClient on the MAIN thread (already marshaled). ---------

- (void)onBrowserCreated:(CefRefPtr<CefBrowser>)browser {
  // Resolve the tabId from the FIFO of pending creations (creation order is
  // preserved by CEF, and both ends run on the main thread).
  NSInteger tabId = -1;
  if (!_pendingTabIds->empty()) {
    tabId = _pendingTabIds->front();
    _pendingTabIds->pop_front();
  }
  if (tabId < 0) {
    return;
  }
  (*_browsers)[tabId] = browser;

  // If this tab is the one the model already wants active, show it now;
  // otherwise keep it hidden (it was created hidden).
  if (_activeTabId == tabId) {
    [self activateTab:tabId];
  }
}

- (void)onBrowserClosed:(CefRefPtr<CefBrowser>)browser {
  for (auto it = _browsers->begin(); it != _browsers->end(); ++it) {
    if (it->second && it->second->IsSame(browser)) {
      _browsers->erase(it);
      break;
    }
  }
}

- (NSInteger)tabIdForBrowser:(CefRefPtr<CefBrowser>)browser {
  for (auto& kv : *_browsers) {
    if (kv.second && kv.second->IsSame(browser)) {
      return kv.first;
    }
  }
  return -1;
}

@end
