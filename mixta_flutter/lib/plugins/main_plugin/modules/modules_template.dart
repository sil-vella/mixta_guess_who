import 'dart:math';
import '../../../../core/00_base/module_base.dart';
import '../../../../core/managers/module_manager.dart';
import '../../../../core/managers/services_manager.dart';
import '../../../../tools/logging/logger.dart';

class TemplateModule extends ModuleBase {
  final Logger logger = Logger();
  final ServicesManager servicesManager = ServicesManager();
  final ModuleManager moduleManager = ModuleManager();

  static TemplateModule? _instance;

  TemplateModule._internal() {
    _registerLeaderboardMethods();
  }

  /// Factory method to provide the singleton instance
  factory TemplateModule() {
    if (_instance == null) {
      Logger().info('Initializing TemplateModule:');
      _instance = TemplateModule._internal();
    } else {
      Logger().info('TemplateModule instance already exists.');
    }
    return _instance!;
  }

  /// Registers methods with the module
  void _registerLeaderboardMethods() {
    Logger().info('Registering connection methods in TemplateModule.');
    ///  registerMethod('sendGetRequest', sendGetRequest);

  }

}