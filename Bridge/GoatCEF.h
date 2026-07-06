// GoatCEF — Objective-C(++) facade exposing CEF to Swift.
//
// Pure Objective-C interface (no CEF/C++ types leak into the header) so it can
// be imported from Swift via the bridging header.
//
// MILESTONE 1: multi-tab engine bridge. One GoatCEF *engine instance* owns a
// single stable AppKit container NSView and a map of tabId -> CefBrowser (one
// CEF browser per tab). Swift assigns the integer tabId; the bridge maps it to
// the underlying browser. Switching tabs toggles VISIBILITY (isHidden) and
// frame, never reparenting on SwiftUI diffs. Background browsers stay alive.

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// ---------------------------------------------------------------------------
// GoatCEFDelegate — main-thread callbacks the engine invokes for tab state.
//
// CEF callbacks arrive on the CEF UI thread. The bridge marshals every one of
// these to the main queue (dispatch_async) before calling the delegate, so
// Swift @Observable main-actor models can update safely.
// ---------------------------------------------------------------------------
@protocol GoatCEFDelegate <NSObject>

// The address bar URL for a tab changed (navigation committed / redirected).
- (void)tab:(NSInteger)tabId didChangeURL:(NSString *)url;

// The document title for a tab changed.
- (void)tab:(NSInteger)tabId didChangeTitle:(NSString *)title;

// Loading state changed; also reports back/forward availability.
- (void)tab:(NSInteger)tabId
    didChangeLoading:(BOOL)isLoading
           canGoBack:(BOOL)canGoBack
        canGoForward:(BOOL)canGoForward;

// Favicon changed (PNG bytes), or nil when unavailable.
- (void)tab:(NSInteger)tabId didChangeFavicon:(NSData *_Nullable)pngData;

// A page requested a popup / new window (window.open, target=_blank). The
// engine cancels the native popup and asks Swift to open a new tab instead.
- (void)tabDidRequestNewTabWithURL:(NSString *)url;

// A site requested a permission (camera/mic/geolocation/notifications/clipboard…)
// for `origin`. Swift must eventually call -respondToPermission:granted: with the
// matching `reqId`. The bridge holds the underlying CEF callback until then.
// `kind` is a lower-case identifier like "microphone", "camera", "geolocation".
- (void)tab:(NSInteger)tabId
    requestPermission:(NSString *)kind
               origin:(NSString *)origin
            requestId:(NSInteger)reqId;

// A download progressed or completed. `downloadId` is stable for the download's
// lifetime. `total` may be -1 when unknown. When `complete` is YES the file has
// finished writing to ~/Downloads/<name>.
- (void)downloadDidUpdateId:(NSInteger)downloadId
                   fileName:(NSString *)name
              receivedBytes:(long long)r
                 totalBytes:(long long)t
                   complete:(BOOL)done
                       path:(NSString *)fullPath;

// Find-in-page result for a tab: 1-based active match `current` of `total`.
- (void)tab:(NSInteger)tabId
    didUpdateFindMatches:(NSInteger)current
                      of:(NSInteger)total;

// Main-frame load progress for a tab, 0.0...1.0.
- (void)tab:(NSInteger)tabId didChangeLoadProgress:(double)progress;

@end

// ---------------------------------------------------------------------------
// GoatCEF — the engine facade.
// ---------------------------------------------------------------------------
@interface GoatCEF : NSObject

// Initialize CEF in the browser (main) process. Must be called on the main
// thread after NSApplication exists and before any browser is created.
// Configures external_message_pump + no_sandbox + remote_debugging_port=9222.
// Returns NO on failure.
+ (BOOL)initializeCEF;

// YES once CefInitialize has succeeded. Callers (e.g. the container's layout
// pass) can poll this to know when it is safe to create browsers.
+ (BOOL)isInitialized;

// Shut down CEF. Call on app termination.
+ (void)shutdown;

// Create an engine instance that owns `container` (a stable AppKit NSView for
// the window's lifetime) and reports tab state changes to `delegate` (held
// weakly). ContentView creates exactly one engine per window.
- (instancetype)initWithContainer:(NSView *)container
                         delegate:(id<GoatCEFDelegate>)delegate;

// Create a new browser for `tabId` loading `url`, parented into the container.
// The new browser is created hidden; call activateTab: to show it. No-op if a
// browser already exists for tabId, or if CEF is not yet initialized.
- (void)createTabWithId:(NSInteger)tabId url:(NSString *)url;

// Close the browser for `tabId` and remove it from the map.
- (void)closeTab:(NSInteger)tabId;

// Show the browser for `tabId` (resized to the container), hide all others.
- (void)activateTab:(NSInteger)tabId;

// Resize the currently active browser's view to the container bounds.
- (void)resizeActiveToContainer;

// Navigation, keyed by tabId.
- (void)loadURL:(NSString *)url inTab:(NSInteger)tabId;
- (void)goBack:(NSInteger)tabId;
- (void)goForward:(NSInteger)tabId;
- (void)reload:(NSInteger)tabId;
- (void)stopLoad:(NSInteger)tabId;

// Open DevTools for `tabId`.
- (void)showDevTools:(NSInteger)tabId;

// --- Permissions -----------------------------------------------------------
// Resolve a pending permission request (see -tab:requestPermission:...). Calls
// the held CEF callback (Continue/Cancel) and drops it. No-op if reqId unknown.
- (void)respondToPermission:(NSInteger)reqId granted:(BOOL)granted;

// --- Find-in-page ----------------------------------------------------------
- (void)find:(NSString *)text tab:(NSInteger)tabId forward:(BOOL)forward;
- (void)stopFind:(NSInteger)tabId clearSelection:(BOOL)clear;

// --- Zoom ------------------------------------------------------------------
// CEF zoom level is logarithmic: 0 = 100%, each ~+1.2 step doubles. We use
// ~0.5 increments from Swift. SetZoomLevel/GetZoomLevel on the host.
- (void)setZoom:(double)level tab:(NSInteger)tabId;
- (double)zoom:(NSInteger)tabId;

@end

NS_ASSUME_NONNULL_END
