import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../tools/logging/logger.dart';
import '../managers/app_manager.dart';
import '../managers/navigation_manager.dart';
import '../../utils/consts/theme_consts.dart';
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

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          widget.computeTitle(context),
          style: AppTextStyles.headingMedium(color: AppColors.darkGray),
        ),
        backgroundColor: AppColors.accentColor,
        iconTheme: IconThemeData(color: AppColors.darkGray),
      ),

      drawer: CustomDrawer(), // ✅ Use the correct drawer

      body: Column(
        children: [
          Expanded(child: buildContent(context)),
        ],
      ),
    );
  }


  /// Abstract method to be implemented in subclasses
  Widget buildContent(BuildContext context);
}
