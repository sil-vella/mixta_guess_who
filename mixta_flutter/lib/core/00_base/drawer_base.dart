import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/consts/theme_consts.dart';
import '../../utils/navigation_utils.dart';
import '../managers/navigation_manager.dart';

class CustomDrawer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final navigationManager = Provider.of<NavigationManager>(context);
    final drawerRoutes = navigationManager.drawerRoutes;

    return Drawer(
      child: ListView(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: AppColors.primaryColor),
            child: Text(
              'Menu',
              style: AppTextStyles.headingMedium(color: AppColors.accentColor),
            ),
          ),
          ListTile(
            leading: Icon(Icons.home, color: AppColors.accentColor),
            title: Text('Home', style: AppTextStyles.bodyLarge),
            onTap: () => NavigationUtils.navigateFromDrawer(context, '/'),
          ),
          ...drawerRoutes.map((route) {
            return ListTile(
              leading: Icon(route.drawerIcon, color: AppColors.accentColor),
              title: Text(route.drawerTitle ?? '', style: AppTextStyles.bodyLarge),
              onTap: () => NavigationUtils.navigateFromDrawer(context, route.path),
            );
          }),
        ],
      ),
    );
  }
}
