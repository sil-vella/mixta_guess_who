import 'package:flutter/material.dart';
import '../../tools/logging/logger.dart';
import '../00_base/module_base.dart';

class ModuleManager extends ChangeNotifier {
  static final Logger _log = Logger();
  static final ModuleManager _instance = ModuleManager._internal();
  factory ModuleManager() => _instance;
  ModuleManager._internal();

  final Map<String, Map<String, ModuleBase>> _modules = {};

  void registerModule(ModuleBase module, {String? instanceKey}) {
    final key = instanceKey ?? module.runtimeType.toString();
    _modules.putIfAbsent(module.moduleKey, () => {})[key] = module;
    _log.info('Module instance registered: ${module.moduleKey} (Key: $key)');

    notifyListeners(); // ✅ Notify listeners that a module was registered
  }

  List<T>? getModules<T extends ModuleBase>(String moduleKey) {
    return _modules[moduleKey]?.values.cast<T>().toList();
  }

  /// ✅ Get a specific module instance by key, or the latest if no key is provided
  T? getModuleInstance<T extends ModuleBase>(String moduleKey, [String? instanceKey]) {
    if (_modules[moduleKey] == null || _modules[moduleKey]!.isEmpty) {
      _log.error('❌ No instances found for module: $moduleKey');
      return null;
    }

    if (instanceKey != null) {
      return _modules[moduleKey]?[instanceKey] as T?;
    } else {
      return _modules[moduleKey]!.values.last as T?;
    }
  }

  /// ✅ Get the latest instance of a module of type `T`, ignoring the module key
  T? getLatestModule<T extends ModuleBase>() {
    for (var moduleGroup in _modules.values) {
      for (var module in moduleGroup.values) {
        if (module is T) {
          return module;
        }
      }
    }
    _log.error('❌ No instance found for module type: ${T.toString()}');
    return null;
  }

  void deregisterModule(String moduleKey, {String? instanceKey}) {
    if (!_modules.containsKey(moduleKey)) return;

    if (instanceKey != null) {
      _modules[moduleKey]?.remove(instanceKey);
    } else {
      _modules[moduleKey]?.remove(_modules[moduleKey]?.keys.last);
    }

    if (_modules[moduleKey]?.isEmpty ?? true) {
      _modules.remove(moduleKey);
    }

    _log.info('Module instance deregistered: $moduleKey (Key: $instanceKey)');
    notifyListeners(); // ✅ Notify listeners when a module is deregistered
  }

  void disposeModules() {
    for (var moduleGroup in _modules.values) {
      for (var module in moduleGroup.values) {
        module.dispose();
      }
    }
    _modules.clear();
    _log.info('All modules disposed.');
    notifyListeners(); // ✅ Notify listeners after clearing all modules
  }
}
