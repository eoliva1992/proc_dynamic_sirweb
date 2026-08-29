#ifndef RUNNER_SUB_WINDOW_REGISTRANT_H_
#define RUNNER_SUB_WINDOW_REGISTRANT_H_

#include <flutter/plugin_registry.h>

// Registers the plugins needed by sub-windows (created via desktop_multi_window).
// window_manager is intentionally excluded: it calls SW_HIDE on initialization,
// which permanently hides sub-windows because waitUntilReadyToShow is never
// called in sub-window Dart code.
void RegisterSubWindowPlugins(flutter::PluginRegistry* registry);

#endif  // RUNNER_SUB_WINDOW_REGISTRANT_H_

