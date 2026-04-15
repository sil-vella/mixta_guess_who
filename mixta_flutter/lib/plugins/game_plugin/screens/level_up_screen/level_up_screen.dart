import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:provider/provider.dart';
import 'dart:math';
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

class LevelUpScreenState extends BaseScreenState<LevelUpScreen> with TickerProviderStateMixin {
  bool _isLevelUp = false;
  bool _isEndGame = false;
  late final AnimationController _pulseController;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;
  late final ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    Logger().info("Initializing LevelUpScreen...");
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _scaleAnim = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _fadeAnim = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));

    // ✅ Retrieve arguments to determine if it's a level-up or end-game
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final Map<String, dynamic>? args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

      setState(() {
        _isLevelUp = args?["levelUp"] ?? false;
        _isEndGame = args?["endGame"] ?? false;
      });

      Logger().info("🎯 LevelUp: $_isLevelUp | 🏆 EndGame: $_isEndGame");
      _confettiController.play();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _confettiController.dispose();
    super.dispose();
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
    final heading = _isEndGame ? "🏆 Category Complete!" : "🎉 Level Up!";
    final subHeading = _isEndGame
        ? "Amazing run. You cleared every level in this category."
        : "Great job! You unlocked the next challenge.";
    final buttonText = _isEndGame ? "Pick Another Category" : "Continue";
    final icon = _isEndGame ? Icons.emoji_events_rounded : Icons.auto_awesome_rounded;

    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.2),
                radius: 1.1,
                colors: [
                  Color(0xFF2C2542),
                  AppColors.scaffoldBackgroundColor,
                ],
              ),
            ),
          ),
        ),
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, _) {
            return Stack(
              alignment: Alignment.center,
              children: List.generate(8, (index) {
                final angle = (index / 8) * 6.283185307179586 + (_pulseController.value * 2.2);
                final radius = 110.0 + (index.isEven ? 12.0 : 0.0);
                final x = radius * cos(angle);
                final y = radius * sin(angle);
                return Transform.translate(
                  offset: Offset(x, y),
                  child: Opacity(
                    opacity: _fadeAnim.value * (index.isEven ? 1.0 : 0.7),
                    child: const Icon(
                      Icons.star_rounded,
                      size: 16,
                      color: AppColors.accentColor,
                    ),
                  ),
                );
              }),
            );
          },
        ),
        Padding(
          padding: AppPadding.defaultPadding,
          child: Center(
            child: ScaleTransition(
              scale: _scaleAnim,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 540),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                decoration: BoxDecoration(
                  color: AppColors.primaryColor.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.accentColor.withOpacity(0.35), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 84, color: AppColors.accentColor),
                    const SizedBox(height: 14),
                    Text(
                      heading,
                      style: AppTextStyles.headingLarge(color: AppColors.accentColor),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      subHeading,
                      style: AppTextStyles.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _isEndGame ? _handleEndGame : _handleLevelUp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accentColor,
                        foregroundColor: AppColors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(buttonText, style: AppTextStyles.buttonText),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.of(context).size.height * 0.18,
          left: 0,
          right: 0,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              emissionFrequency: 0.08,
              numberOfParticles: 22,
              maxBlastForce: 18,
              minBlastForce: 9,
              gravity: 0.14,
            ),
          ),
        ),
      ],
    );
  }
}
