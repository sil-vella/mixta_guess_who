import '../managers/module_manager.dart';

abstract class ModuleBase {
  final String moduleKey;

  /// ✅ Access `ModuleManager` singleton
  static final ModuleManager _moduleManager = ModuleManager();

  /// ✅ Auto-register module on creation
  ModuleBase([String? key])
      : moduleKey = key ?? 'module_${DateTime.now().millisecondsSinceEpoch}' {
    _registerModule(); // ✅ Auto-register on instantiation
  }

  /// ✅ Auto-register the module in `ModuleManager`
  void _registerModule() {
    _moduleManager.registerModule(this);
  }

  /// ✅ Dispose method to clean up resources
  void dispose() {
    _moduleManager.deregisterModule(moduleKey); // ✅ Auto-deregister on dispose
  }
}
