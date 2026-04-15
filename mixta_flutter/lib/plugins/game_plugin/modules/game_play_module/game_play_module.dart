import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/00_base/module_base.dart';
import '../../../../core/managers/module_manager.dart';
import '../../../../core/managers/services_manager.dart';
import '../../../../core/managers/state_manager.dart';
import '../../../../core/services/shared_preferences.dart';
import '../../../../core/services/ticker_timer/ticker_timer.dart';
import '../../../../tools/logging/logger.dart';
import '../question_module/question_module.dart';
import '../rewards_module/rewards_module.dart';
import 'config/gameplaymodule_config.dart';

class GamePlayModule extends ModuleBase {
  static final Logger _log = Logger(); // ✅ Use a static logger for static methods

  /// ✅ Constructor with module key
  GamePlayModule() : super("game_play_module") {
    _log.info('📢 GamePlayModule initialized and auto-registered.');
  }

  Map<String, dynamic>? question;
  bool isLoading = true;
  String feedbackMessage = "";
  List<String> imageOptions = []; // ✅ Store shuffled images

  /// Level this round was loaded for (prefs at `roundInit`). Drives points/`update-rewards`, not `question['level']` alone.
  int? roundLevel;

  void _finishRoundLoadWithError(Function updateState, String message) {
    isLoading = false;
    feedbackMessage = message;
    _log.error(message);
    updateState();
  }

  Future<void> resetState(BuildContext context) async {
    final stateManager = Provider.of<StateManager>(context, listen: false);

    stateManager.updatePluginState("game_timer", {
      "isRunning": false,
      "duration": 30,
    }, force: true);

    stateManager.updatePluginState("game_round", {
      "hint": false,
      "imagesLoaded": false,
      "factLoaded": false,
      "levelUp": false,
      "endGame": false,
    }, force: true);

    roundLevel = null;

    _log.info("✅ Game state reset completed.");

    // ✅ Wait a frame to ensure updates are reflected before proceeding
    await Future.delayed(Duration(milliseconds: 50));
  }
  /// Fetch user level and request a question from backend
  Future<void> roundInit(BuildContext context, Function updateState) async {
    final stateManager = Provider.of<StateManager>(context, listen: false);
    final sharedPref = Provider.of<ServicesManager>(context, listen: false)
        .getService<SharedPrefManager>('shared_pref');

    isLoading = true;
    feedbackMessage = "";
    updateState();

    if (sharedPref == null) {
      _finishRoundLoadWithError(updateState, "❌ SharedPrefManager not found!");
      return;
    }

    final questionModule = Provider.of<ModuleManager>(context, listen: false).getLatestModule<QuestionModule>();

    if (questionModule == null) {
      _finishRoundLoadWithError(updateState, "❌ QuestionModule not found!");
      return;
    }

    // ✅ Retrieve game round state
    final gameRoundState = stateManager.getPluginState<Map<String, dynamic>>('game_round');
    final int roundNumber = gameRoundState?['roundNumber'] ?? 1;
    int updatedNumber = roundNumber + 1; // ✅ Increment round

    stateManager.updatePluginState("game_round", {
      "roundNumber": updatedNumber, // ✅ Update state
    });

    await resetState(context);  // ✅ Ensure state resets before fetching new data

    try {
      // ✅ Get user's level and category from SharedPreferences
      final category = sharedPref.getString('category') ?? "actors";  // ✅ Default value
      final int level = sharedPref.getInt('level_$category') ?? 1;
      roundLevel = level;

      _log.info("🏆 User category: $category | Level: $level");

      final guessedKey = "guessed_${category}_level$level";
      List<String> guessedNames = sharedPref.getStringList(guessedKey);  // ✅ Ensure it's always a list

      _log.info("📜 Final guessed names sent to backend: $guessedNames");

      // ✅ Fetch question with updated guessed list
      final response = await questionModule.getQuestion(context, level, category, guessedNames);

      if (response.containsKey("error")) {
        roundLevel = null;
        final errText = "${response["error"]}";
        final noMoreNames = errText.toLowerCase().contains("no more names left to guess");

        if (noMoreNames) {
          final int maxLevels = sharedPref.getInt('max_levels_$category') ?? level;
          if (level < maxLevels) {
            final nextLevel = level + 1;
            await sharedPref.setInt('level_$category', nextLevel);
            _log.info(
              "🏁 Level $level completed for '$category' via no-more-names response. Promoting to level $nextLevel/$maxLevels.",
            );
            stateManager.updatePluginState("game_round", {"levelUp": true}, force: true);
            isLoading = false;
            feedbackMessage = "";
            updateState();
          } else {
            _log.info(
              "🏆 Category '$category' fully completed (level $level/$maxLevels). Triggering endGame.",
            );
            stateManager.updatePluginState("game_round", {"endGame": true}, force: true);
            isLoading = false;
            feedbackMessage = "";
            updateState();
          }
        } else {
          _finishRoundLoadWithError(updateState, "❌ Error fetching question: ${response['error']}");
        }
        return;
      }

      // ✅ Ensure question values are valid
      String imageUrl = response['image_url'] ?? ""; // ✅ Prevents null
      List<String> distractors = response['distractor_images']?.cast<String>() ?? []; // ✅ Ensures it's a list

      question = response;
      isLoading = false;

      // ✅ Prepare shuffled images (correct + 3 distractors)
      imageOptions = [imageUrl, ...distractors];
      imageOptions.shuffle(Random());

      // ✅ Update UI State in GameScreen
      updateState();
      _log.info("✅ Question retrieved successfully: $response");

    } catch (e) {
      roundLevel = null;
      _finishRoundLoadWithError(updateState, "❌ Failed to fetch question: $e");
      _log.error("❌ Failed to fetch question: $e", error: e);
    }
  }


  Future<void> setTimer(BuildContext context, Function onTimeout) async {
    final servicesManager = Provider.of<ServicesManager>(context, listen: false);
    final stateManager = Provider.of<StateManager>(context, listen: false);
    final sharedPref = servicesManager.getService<SharedPrefManager>('shared_pref');

    if (sharedPref == null) {
      _log.error("❌ SharedPrefManager not found!");
      return;
    }

    try {
      final category = sharedPref.getString('category') ?? 'actors';
      final int level = sharedPref.getInt('level_$category') ?? 1;

      if (level <= 2) {
        _log.info("⏳ Skipping timer. Level is $level ($category).");
        return;
      }

      final int duration = (GamePlayConfig.levelTimers[level] ?? 10).toInt();

      _log.info("⏳ Starting timer for Level $level: $duration seconds");

      // ✅ Retrieve or register the round timer
      TickerTimer? roundTimer = servicesManager.getService<TickerTimer>('round_timer');

      if (roundTimer == null) {
        roundTimer = TickerTimer(id: 'round_timer');
        await servicesManager.registerService('round_timer', roundTimer);
      }

      // ✅ Reset and start the timer
      roundTimer.resetTimer();
      roundTimer.startTimer();

      // ✅ Listen to timer updates and update state
      roundTimer.addListener(() {
        final int remainingTime = duration - roundTimer!.elapsedSeconds;

        if (remainingTime >= 0) {
          _log.info("⏳ Timer ticking: $remainingTime seconds left");

          stateManager.updatePluginState("game_timer", {
            "isRunning": true,
            "duration": remainingTime,
          }, force: true);
        }

        if (remainingTime <= 0) {
          roundTimer.stopTimer(); // ✅ Ensure timer stops at 0
          _log.info("✅ Timer reached 0. Triggering timeout.");

          stateManager.updatePluginState("game_timer", {
            "isRunning": false,
            "duration": 0,
          });

          onTimeout();
        }
      });
    } catch (e) {
      _log.error("❌ Failed to start timer: $e", error: e);
    }
  }


  void checkAnswer(BuildContext context, String selectedImage, Function updateState, {bool timeUp = false}) async {

    _log.info("🏆 Checking answer...");

    final correctImage = question?['image_url'] ?? "";
    final rewardsModule = ModuleManager().getLatestModule<RewardsModule>();
    final stateManager = Provider.of<StateManager>(context, listen: false);
    final sharedPref = Provider.of<ServicesManager>(context, listen: false).getService<SharedPrefManager>('shared_pref');

    if (rewardsModule == null) {
      _log.error("❌ RewardsModule not found.");
      return;
    }

    if (question == null) {
      _log.info("⚠️ checkAnswer called with no question.");
      updateState();
      return;
    }

    // ✅ Extract category, level, and correct actor
    String category = question!["category"] ?? "actors";
    final int questionFallbackLevel = int.tryParse(question!["level"]?.toString() ?? "1") ?? 1;
    final int level = roundLevel ?? questionFallbackLevel;
    String correctActor = question!["actor"] ?? "";

    if (sharedPref != null) {
      final int prefLevel = sharedPref.getInt('level_$category') ?? 1;
      if (prefLevel > level) {
        _log.info(
          "⏭️ Ignoring answer: prefs already advanced (level_$category=$prefLevel > roundLevel=$level). Await new round.",
        );
        updateState();
        return;
      }
    }

    _log.info("📌 Checking answer for: $correctActor (Category: $category, Level: $level)");
    _log.forceLog("📌 Checking answer for: $correctActor (Category: $category, Level: $level)");

    if (selectedImage == correctImage) {
      feedbackMessage = "🎉 Correct!";

      // ✅ Retrieve 'hint' state from StateManager
      final gameRoundState = stateManager.getPluginState<Map<String, dynamic>>('game_round');
      final bool hintUsed = gameRoundState?['hint'] ?? false;

      _log.forceLog("📌 hint: $hintUsed ");

      // ✅ Determine points based on hint usage
      String pointsKey = hintUsed ? 'hint' : 'no_hint';
      int points = await rewardsModule.getPoints(context, pointsKey, category, level);

      _log.forceLog("📌 hint: $points ");

      // ✅ Call saveReward with all necessary data
      final rewardData = await rewardsModule.saveReward(
        context: context, // ✅ Pass context here
        points: points,
        category: category,
        level: level,
        guessedActor: correctActor,
      );

      Logger().forceLog("📜 reward data if correct ${rewardData}");
      _log.info("🏆 Updated Rewards: ${rewardData}");

      // ✅ Update game state with level-up or end-game status
      final Map<String, dynamic> roundPatch = {};
      if (rewardData["levelUp"] == true) roundPatch["levelUp"] = true;
      if (rewardData["endGame"] == true) roundPatch["endGame"] = true;
      if (roundPatch.isNotEmpty) {
        stateManager.updatePluginState("game_round", roundPatch, force: true);
      }

    } else {
      feedbackMessage = "❌ Incorrect.";
    }

    updateState();
    _log.info("✅ User selected: $selectedImage | Correct: ${question?['image_url']}");
  }

void showGameOverScreen() {
  _log.info("🎯 Game over! Player reached max level.");
}

}
