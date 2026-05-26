import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'core/managers/app_manager.dart';
import 'core/managers/module_manager.dart';
import 'core/managers/plugin_manager.dart';
import 'core/managers/services_manager.dart';
import 'core/managers/state_manager.dart';
import 'core/managers/navigation_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final servicesManager = ServicesManager();
  await servicesManager.autoRegisterAllServices();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppManager()),
        ChangeNotifierProvider(create: (_) => ModuleManager()),
        ChangeNotifierProvider(create: (_) => PluginManager()),
        ChangeNotifierProvider(create: (_) => servicesManager),
        ChangeNotifierProvider(create: (_) => StateManager()),
        ChangeNotifierProvider(create: (_) => NavigationManager()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  GoRouter? _router;

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

    _router ??= navigationManager.router;

    return MaterialApp.router(
      title: "My App",
      theme: ThemeData.dark(),
      routerConfig: _router!,
    );
  }
}
