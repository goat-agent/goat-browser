#include "include/cef_app.h"
#include "include/wrapper/cef_library_loader.h"
#include "../Bridge/GoatSchemes.h"

namespace {

class GoatHelperApp : public CefApp {
 public:
  GoatHelperApp() = default;
  void OnRegisterCustomSchemes(CefRawPtr<CefSchemeRegistrar> registrar) override {
    GoatRegisterCustomSchemes(registrar);
  }

 private:
  IMPLEMENT_REFCOUNTING(GoatHelperApp);
};

}  // namespace

int main(int argc, char* argv[]) {
  CefScopedLibraryLoader library_loader;
  if (!library_loader.LoadInHelper()) {
    return 1;
  }

  CefMainArgs main_args(argc, argv);
  CefRefPtr<GoatHelperApp> app = new GoatHelperApp();
  return CefExecuteProcess(main_args, app, nullptr);
}
