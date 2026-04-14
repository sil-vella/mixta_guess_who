import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/00_base/screen_base.dart';
import '../../../../core/managers/state_manager.dart';
import '../../../../tools/logging/logger.dart';
import '../../../../utils/consts/theme_consts.dart'; // ✅ Import Theme Constants

class LevelUpScreen extends BaseScreen {
  const LevelUpScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) {
    return "Well Done!";
  }

  @override
  LevelUpScreenState createState() => LevelUpScreenState();
}

class LevelUpScreenState extends BaseScreenState<LevelUpScreen> {
  bool _isLevelUp = false;
  bool _isEndGame = false;

  @override
  void initState() {
    super.initState();
    Logger().info("Initializing LevelUpScreen...");

    // ✅ Retrieve arguments to determine if it's a level-up or end-game
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final Map<String, dynamic>? args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

      setState(() {
        _isLevelUp = args?["levelUp"] ?? false;
        _isEndGame = args?["endGame"] ?? false;
      });

      Logger().info("🎯 LevelUp: $_isLevelUp | 🏆 EndGame: $_isEndGame");
    });
  }

  void _handleLevelUp() {
    final stateManager = Provider.of<StateManager>(context, listen: false);
    stateManager.updatePluginState("game_round", {
      "levelUp": false,
      "endGame": false,
    }, force: true);
    Logger().info("🎯 Leveling up → game (flags cleared)");
    Navigator.pushReplacementNamed(context, "/game");
  }

  void _handleEndGame() {
    final stateManager = Provider.of<StateManager>(context, listen: false);
    stateManager.updatePluginState("game_round", {
      "levelUp": false,
      "endGame": false,
    }, force: true);
    Logger().info("🏆 Game completed → preferences (flags cleared)");
    Navigator.pushReplacementNamed(context, "/preferences");
  }

  @override
  Widget buildContent(BuildContext context) {
    return Container(
      color: AppColors.scaffoldBackgroundColor, // ✅ Use Themed Background
      padding: AppPadding.defaultPadding, // ✅ Apply consistent padding
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isEndGame ? Icons.emoji_events : Icons.rocket_launch,
            size: 100,
            color: AppColors.accentColor, // ✅ Use themed accent color
          ),
          const SizedBox(height: 20),

          // ✅ Main Heading
          Text(
            _isEndGame ? "🏆 Congratulations!" : "🎉 Level Up!",
            style: AppTextStyles.headingLarge(color: AppColors.accentColor),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // ✅ Subheading Text
          Text(
            _isEndGame
                ? "You've completed this category and proved your skills!"
                : "Keep going! The next challenge awaits!",
            style: AppTextStyles.bodyLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),

          // ✅ Button (Uses Themed Button Styling)
          ElevatedButton(
            onPressed: _isEndGame ? _handleEndGame : _handleLevelUp, // ✅ Calls the correct function
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accentColor, // ✅ Gold Theme Color
              foregroundColor: AppColors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              _isEndGame ? "Select a new category" : "Continue to Next Level",
              style: AppTextStyles.buttonText,
            ),
          ),
        ],
      ),
    );
  }
}
