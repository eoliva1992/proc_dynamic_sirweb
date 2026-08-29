#include "sub_window_registrant.h"

#include <flutter_js/flutter_js_plugin.h>
#include <webview_flutter_windows/webview_windows_plugin.h>

void RegisterSubWindowPlugins(flutter::PluginRegistry* registry) {
  // Provides JavaScript evaluation for PL/SQL syntax checking in the editor.
  FlutterJsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("FlutterJsPlugin"));

  // Provides WebView2 / Chromium for the Monaco code editor.
  WebviewWindowsPluginRegisterWithRegistrar(
      registry->GetRegistrarForPlugin("WebviewWindowsPlugin"));

  // window_manager is intentionally omitted: it calls ShowWindow(hwnd, SW_HIDE)
  // during plugin registration, which permanently hides the sub-window because
  // no Dart code ever calls windowManager.waitUntilReadyToShow().
  //
  // screen_retriever_windows is intentionally omitted: it is only used by
  // window_manager to centre the window, which is also not needed here.
}

