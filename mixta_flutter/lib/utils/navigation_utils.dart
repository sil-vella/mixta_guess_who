import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'consts/theme_consts.dart';

/// Central navigation policy for GoRouter (push stack vs reset).
class NavigationUtils {
  NavigationUtils._();

  static DateTime? _lastExitBackPress;

  /// Drawer: close first, then home via [go] or forward via [push].
  static void navigateFromDrawer(BuildContext context, String path) {
    Navigator.of(context).pop();
    if (path == '/') {
      context.go('/');
    } else {
      context.push(path);
    }
  }

  /// Forward navigation — preserves back stack.
  static void navigateForward(BuildContext context, String path) {
    context.push(path);
  }

  /// Replace entire stack with one route (e.g. category complete → profile).
  static void navigateReset(BuildContext context, String path) {
    context.go(path);
  }

  /// Android / web system back: pop, fallback to home, or double-back to exit.
  static void handleSystemBack(BuildContext context) {
    final router = GoRouter.of(context);

    if (router.canPop()) {
      router.pop();
      return;
    }

    final location = GoRouterState.of(context).uri.path;
    if (location != '/') {
      context.go('/');
      return;
    }

    final now = DateTime.now();
    if (_lastExitBackPress != null &&
        now.difference(_lastExitBackPress!) < const Duration(seconds: 2)) {
      _lastExitBackPress = null;
      SystemNavigator.pop();
      return;
    }

    _lastExitBackPress = now;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Press back again to exit',
          style: AppTextStyles.bodyMedium,
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
