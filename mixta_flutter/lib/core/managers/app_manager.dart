import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../tools/logging/logger.dart';
import 'hooks_manager.dart';
import 'plugin_manager.dart';

class AppManager extends ChangeNotifier {
  static final Logger _log = Logger();
  static final AppManager _instance = AppManager._internal();
  static late BuildContext globalContext;

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  factory AppManager() => _instance;
  AppManager._internal();

  final HooksManager _hooksManager = HooksManager(); // ✅ Ensure Singleton HooksManager

  Future<void> _initializePlugins(BuildContext context) async {
    _log.info('Initializing plugins...');

    final pluginManager = Provider.of<PluginManager>(context, listen: false);

    // ✅ Ensure all plugins are registered first
    pluginManager.initializePlugins(context);

    _isInitialized = true;
    notifyListeners();
    _log.info('Plugins initialized successfully.');
  }

  Future<void> initializeApp(BuildContext context) async {
    if (!_isInitialized) {
      Future.delayed(Duration.zero, () {
        // ✅ Use GoRouter instead of NavigationContainer
        if (Navigator.canPop(context)) {
          context.go('/'); // ✅ Navigate to Home using GoRouter
        }
      });
      await _initializePlugins(context); // Now awaited
      _isInitialized = true;
    }
  }
}
