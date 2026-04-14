import 'package:mixta_guess_who/plugins/main_plugin/modules/animations_module/animations_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter/animation.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/00_base/screen_base.dart';
import '../../../core/managers/app_manager.dart';
import '../../../core/managers/module_manager.dart';
import '../../../core/managers/state_manager.dart';
import '../modules/main_helper_module/main_helper_module.dart'; // ✅ Import Helper Module

class HomeScreen extends BaseScreen {
  const HomeScreen({Key? key}) : super(key: key);


  @override
  String computeTitle(BuildContext context) {
    return "Home";
  }

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends BaseScreenState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late String _backgroundImage; // ✅ Stores the background image
  final ModuleManager _moduleManager = ModuleManager();

  @override
  void initState() {
    super.initState();

    // ✅ Set a random background on screen load
    _backgroundImage = MainHelperModule.getRandomBackground();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true); // Infinite bouncing effect
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget buildContent(BuildContext context) {
    final animationsModule = _moduleManager.getLatestModule<AnimationsModule>();

    final stateManager = Provider.of<StateManager>(context, listen: false);

    // Update state and navigate when Play button is pressed
    void onPlayPressed() {
      stateManager.updateMainAppState('main_state', 'in_play');
      context.go('/game'); // ✅ Use GoRouter navigation
    }


    if (animationsModule == null) {
      return const Center(child: Text("Required modules are not available."));
    }

    return Stack(
      children: [
        // ✅ Full-Screen Background Image
        Positioned.fill(
          child: _backgroundImage.isNotEmpty
              ? Image.asset(
            _backgroundImage,
            fit: BoxFit.cover,
          )
              : Container(color: Colors.black), // Fallback background
        ),

        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              animationsModule.applyBounceAnimation(
                child: Image.asset(
                  'assets/images/icon_foreground.png', // Replace with your actual asset path
                  width: 300, // Adjust size as needed
                  height: 300,
                ),
                controller: _controller,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: onPlayPressed,
                child: const Text('Play'),
              ),
            ],

          ),
        ),

      ],
    );
  }
}
