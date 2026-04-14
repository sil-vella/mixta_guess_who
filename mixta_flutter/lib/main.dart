import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'core/managers/app_manager.dart';
import 'core/managers/module_manager.dart';
import 'core/managers/plugin_manager.dart';
import 'core/managers/hooks_manager.dart';
import 'core/managers/services_manager.dart';
import 'core/managers/state_manager.dart';
import 'core/managers/navigation_manager.dart';
import 'plugins/main_plugin/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final servicesManager = ServicesManager();
  await servicesManager.autoRegisterAllServices(); // ✅ Initialize all services, including SharedPreferences

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppManager()),
        ChangeNotifierProvider(create: (_) => ModuleManager()),
        ChangeNotifierProvider(create: (_) => PluginManager()),
        ChangeNotifierProvider(create: (_) => servicesManager), // ✅ Use pre-initialized ServicesManager
        ChangeNotifierProvider(create: (_) => StateManager()),
        ChangeNotifierProvider(create: (_) => NavigationManager()),
      ],
      child: const MyApp(),
    ),
  );
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final appManager = Provider.of<AppManager>(context);
    final navigationManager = Provider.of<NavigationManager>(context, listen: false);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!appManager.isInitialized) {
        appManager.initializeApp(context);
      }
    });

    if (!appManager.isInitialized) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MaterialApp.router(
      title: "My App",
      theme: ThemeData.dark(),
      routerConfig: navigationManager.router, // ✅ Use the dynamic GoRouter instance
    );
  }
}
