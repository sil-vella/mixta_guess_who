import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../plugins/adverts_plugin/adverts_plugin_main.dart';
import '../../plugins/game_plugin/game_plugin_main.dart';
import '../../plugins/main_plugin/main_plugin_main.dart';
import '../../tools/logging/logger.dart';
import '../00_base/plugin_base.dart';
import 'hooks_manager.dart';
import 'module_manager.dart';
import 'state_manager.dart';

class PluginManager extends ChangeNotifier {
  static final Logger _log = Logger();
  final Map<String, PluginBase> _plugins = {};

  PluginManager();

  void registerPlugin(BuildContext context, String pluginKey, PluginBase plugin) {
    if (_plugins.containsKey(pluginKey)) {
      _log.info('Plugin already registered: $pluginKey');
      return;
    }

    _plugins[pluginKey] = plugin;
    _log.info('Initializing plugin: $pluginKey');

    plugin.initialize(context);

    // ✅ Plugins should register their hooks here
    HooksManager().registerHook('app_startup', () {
      _log.info('App Startup Hook Triggered by $pluginKey');
    });

    HooksManager().registerHook('reg_nav', () {
      _log.info('Navigation Hook Triggered by $pluginKey');
    });

    notifyListeners();
  }


  /// ✅ Initializes all required plugins
  Future<void> initializePlugins(BuildContext context) async {
    registerPlugin(context, "main_plugin", MainPlugin());
    registerPlugin(context, "game_plugin", GamePlugin());
    registerPlugin(context, "adverts_plugin", AdvertsPlugin());

    _log.info("✅ All plugins registered.");
  }

  /// ✅ Removes a specific plugin
  void deregisterPlugin(String pluginKey) {
    final plugin = _plugins.remove(pluginKey);
    if (plugin != null) {
      _log.info('Plugin deregistered: $pluginKey');
      notifyListeners();
    }
  }

  /// ✅ Retrieves a plugin instance
  T? getPlugin<T extends PluginBase>(String pluginKey) {
    return _plugins[pluginKey] as T?;
  }

  /// ✅ Clears all plugins
  void clearPlugins() {
    _plugins.clear();
    _log.info('All plugins cleared.');
    notifyListeners();
  }

  @override
  void dispose() {
    clearPlugins();
    super.dispose();
  }
}
