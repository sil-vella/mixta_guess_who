import 'package:flutter/material.dart';
import 'package:mixta_guess_who/core/managers/module_manager.dart';
import '../../../../core/00_base/screen_base.dart';
import '../../../../core/managers/services_manager.dart';
import '../../../../tools/logging/logger.dart';

class TemplateScreen extends BaseScreen {
  const TemplateScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) {
    return "TemplateScreen";
  }

  @override
  TemplateScreenState createState() => TemplateScreenState();
}

class TemplateScreenState extends BaseScreenState<TemplateScreen> {
  final ServicesManager _servicesManager = ServicesManager();
  final ModuleManager _moduleManager = ModuleManager();

  @override
  void initState() {
    super.initState();
    Logger().info("Initializing TemplateScreen...");

  }

  @override
  Widget buildContent(BuildContext context) {
    return Stack(
      children: [

      ],
    );
  }
}
