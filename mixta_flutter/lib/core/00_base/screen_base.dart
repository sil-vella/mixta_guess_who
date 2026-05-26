import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../tools/logging/logger.dart';
import '../managers/app_manager.dart';
import '../managers/navigation_manager.dart';
import '../../utils/consts/theme_consts.dart';
import '../../utils/navigation_utils.dart';
import 'drawer_base.dart';

abstract class BaseScreen extends StatefulWidget {
  const BaseScreen({Key? key}) : super(key: key);

  /// Define a method to compute the title dynamically
  String computeTitle(BuildContext context);

  @override
  BaseScreenState createState();
}

abstract class BaseScreenState<T extends BaseScreen> extends State<T> {
  late final AppManager appManager;

  final Logger log = Logger();

  @override
  void initState() {
    super.initState();

    appManager = Provider.of<AppManager>(context, listen: false);
  }

  @override
  @override
  Widget build(BuildContext context) {
    Provider.of<NavigationManager>(context);

    final router = GoRouter.of(context);
    final onHome = GoRouterState.of(context).uri.path == '/';
    final showBack = !onHome && router.canPop();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          NavigationUtils.handleSystemBack(context);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.scaffoldBackgroundColor,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: _buildDrawerButton(context),
          title: Text(
            widget.computeTitle(context),
            style: AppTextStyles.headingMedium(color: AppColors.darkGray),
          ),
          backgroundColor: AppColors.accentColor,
          iconTheme: IconThemeData(color: AppColors.darkGray),
        ),

        drawer: CustomDrawer(),

        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showBack) _buildBackRow(context),
            Expanded(child: buildContent(context)),
          ],
        ),
      ),
    );
  }


  Widget _buildDrawerButton(BuildContext context) {
    return Builder(
      builder: (scaffoldContext) => IconButton(
        icon: Icon(Icons.menu, color: AppColors.darkGray),
        tooltip: 'Menu',
        onPressed: () => Scaffold.of(scaffoldContext).openDrawer(),
      ),
    );
  }

  /// Shown under the app bar when there is a route to pop back to.
  Widget _buildBackRow(BuildContext context) {
    return Material(
      color: AppColors.scaffoldBackgroundColor,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppPadding.defaultPadding.left,
          right: AppPadding.defaultPadding.right,
          top: AppPadding.defaultPadding.top / 2,
          bottom: AppPadding.defaultPadding.top / 2,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => NavigationUtils.handleSystemBack(context),
            icon: Icon(Icons.arrow_back, color: AppColors.accentColor),
            label: Text('Back', style: AppTextStyles.bodyMedium),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.accentColor,
              padding: EdgeInsets.zero,
            ),
          ),
        ),
      ),
    );
  }

  /// Abstract method to be implemented in subclasses
  Widget buildContent(BuildContext context);
}
