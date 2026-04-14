import 'package:mixta_guess_who/core/managers/navigation_manager.dart';
import 'package:mixta_guess_who/plugins/main_plugin/modules/animations_module/animations_module.dart';
import 'package:mixta_guess_who/plugins/main_plugin/modules/login_module/login_module.dart';
import 'package:mixta_guess_who/plugins/main_plugin/modules/main_helper_module/main_helper_module.dart';
import 'package:mixta_guess_who/plugins/main_plugin/screens/home_screen.dart';
import 'package:mixta_guess_who/plugins/main_plugin/screens/preferences_screen/preferences_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/00_base/module_base.dart';
import '../../core/00_base/plugin_base.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/hooks_manager.dart';
import '../../core/managers/services_manager.dart';
import '../../core/managers/state_manager.dart';
import '../../tools/logging/logger.dart';
import '../../utils/consts/config.dart';
import 'modules/connections_module/connections_module.dart';

class MainPlugin extends PluginBase {
  late final ServicesManager servicesManager;
  late final StateManager stateManager;
  late final NavigationManager navigationManager;

  MainPlugin();

  @override
  void initialize(BuildContext context) {
    super.initialize(context);

    servicesManager = Provider.of<ServicesManager>(context, listen: false);
    stateManager = Provider.of<StateManager>(context, listen: false);
    navigationManager = Provider.of<NavigationManager>(context, listen: false);
    final moduleManager = Provider.of<ModuleManager>(context, listen: false);

    _registerNavigation();

    // ✅ Register all modules in ModuleManager
    final modules = createModules();
    for (var entry in modules.entries) {
      final instanceKey = entry.key;
      final module = entry.value;
      moduleManager.registerModule(module, instanceKey: instanceKey);
    }
  }

  /// ✅ Register Ad-related modules with specific instance keys
  @override
  Map<String?, ModuleBase> createModules() {
    return {
      null: ConnectionsModule(Config.apiUrl),
      null: AnimationsModule(),
      null: MainHelperModule(),
      null: LoginModule(),
    };
  }

  /// ✅ Register game navigation dynamically
  void _registerNavigation() {
    navigationManager.registerRoute(
      path: '/preferences',
      screen: (context) => const PreferencesScreen(),
      drawerTitle: 'Preferences', // ✅ Add to drawer
      drawerIcon: Icons.settings, // ✅ Assign an icon
      drawerPosition: 5,
    );

  }

  /// ✅ Define initial states for this plugin
  @override
  Map<String, Map<String, dynamic>> getInitialStates() {
    return {}; // Define initial states if needed
  }
}
