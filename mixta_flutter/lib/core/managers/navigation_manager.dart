import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../plugins/main_plugin/screens/home_screen.dart';

/// ✅ Holds route data, including optional drawer details
class RegisteredRoute {
  final String path;
  final Widget Function(BuildContext) screen;
  final String? drawerTitle;
  final IconData? drawerIcon;
  final int drawerPosition;

  RegisteredRoute({
    required this.path,
    required this.screen,
    this.drawerTitle,
    this.drawerIcon,
    this.drawerPosition = 999,
  });

  GoRoute toGoRoute() {
    return GoRoute(
      path: path,
      builder: (context, state) => screen(context),
    );
  }

  /// ✅ Helper method to check if route should appear in the drawer
  bool get shouldAppearInDrawer {
    return drawerTitle != null && drawerIcon != null;
  }
}

class NavigationManager extends ChangeNotifier {
  static final NavigationManager _instance = NavigationManager._internal();
  factory NavigationManager() => _instance;
  NavigationManager._internal();

  final List<RegisteredRoute> _routes = [];

  /// ✅ Getter for dynamically registered routes
  List<GoRoute> get routes => _routes.map((r) => r.toGoRoute()).toList();

  List<RegisteredRoute> get drawerRoutes {
    final filteredRoutes = _routes.where((r) => r.shouldAppearInDrawer).toList();

    // ✅ Sort drawer items based on `drawerPosition`
    filteredRoutes.sort((a, b) => a.drawerPosition.compareTo(b.drawerPosition));

    return filteredRoutes;
  }

  void registerRoute({
    required String path,
    required Widget Function(BuildContext) screen,
    String? drawerTitle,
    IconData? drawerIcon,
    int drawerPosition = 999, // ✅ Default low priority
  }) {
    if (_routes.any((r) => r.path == path)) return; // Prevent duplicates

    final newRoute = RegisteredRoute(
      path: path,
      screen: screen,
      drawerTitle: drawerTitle,
      drawerIcon: drawerIcon,
      drawerPosition: drawerPosition,
    );

    _routes.add(newRoute);

    notifyListeners();
  }


  /// ✅ Create a dynamic GoRouter instance
  GoRouter get router {
    return GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        ...routes, // ✅ Include dynamically registered plugin routes
      ],
    );
  }
}
