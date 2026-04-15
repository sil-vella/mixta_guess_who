import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mixta_guess_who/plugins/game_plugin/modules/function_helper_module/function_helper_module.dart';
import 'package:mixta_guess_who/plugins/game_plugin/modules/rewards_module/rewardsModule_config/config.dart';
import '../../../../core/00_base/module_base.dart';
import '../../../../core/managers/module_manager.dart';
import '../../../../core/managers/services_manager.dart';
import '../../../../core/services/shared_preferences.dart';
import '../../../../tools/logging/logger.dart';
import '../../../main_plugin/modules/connections_module/connections_module.dart';

class RewardsModule extends ModuleBase {
  static final Logger _log = Logger(); // ✅ Use a static logger for static methods

  /// ✅ Constructor - No stored instances, dependencies are fetched dynamically
  RewardsModule() : super("rewards_module") {
    _log.info('✅ RewardsModule initialized.');
  }

  /// ✅ Get points for a specific action, applying the multiplier for the provided level
  Future<int> getPoints(BuildContext context, String key, String category, int level) async {
    final servicesManager = Provider.of<ServicesManager>(context, listen: false);
    final sharedPref = servicesManager.getService<SharedPrefManager>('shared_pref');

    if (sharedPref == null) {
      _log.error('❌ SharedPreferences service not available.');
      return 0;
    }

    // ✅ Fetch the base points using `key`
    int basePoints = RewardsConfig.baseRewards[key] ?? 1;

    // ✅ Fetch the level multiplier based on the provided level
    double multiplier = RewardsConfig.levelMultipliers[level] ?? 1.0;

    _log.info('🏆 Calculating points for $key at Level $level: Base = $basePoints, Multiplier = $multiplier');

    return (basePoints * multiplier).toInt();
  }

  /// ✅ Save Reward and Update Backend
  Future<Map<String, dynamic>> saveReward({
    required BuildContext context,
    required int points,
    required String category,
    required int level,
    required String guessedActor,
  }) async {
    final moduleManager = Provider.of<ModuleManager>(context, listen: false);
    final servicesManager = Provider.of<ServicesManager>(context, listen: false);
    final sharedPref = servicesManager.getService<SharedPrefManager>('shared_pref');
    final connectionModule = moduleManager.getLatestModule<ConnectionsModule>();
    final functionsHelper = moduleManager.getLatestModule<FunctionHelperModule>();

    if (sharedPref == null || connectionModule == null || functionsHelper == null) {
      _log.error('❌ SharedPreferences, ConnectionModule, or FunctionsHelperModule not available.');
      return {"points": 0, "endGame": false, "levelUp": false};
    }

    // ✅ Retrieve current level & points
    int currentLevel = level;
    int previousPoints = sharedPref.getInt('points_${category}_level$currentLevel') ?? 0;
    int updatedPoints = previousPoints + points;

    // ✅ Fetch guessed names for this level
    String guessedKey = "guessed_${category}_level$currentLevel";
    List<String> guessedList = sharedPref.getStringList(guessedKey);

    if (!guessedList.contains(guessedActor)) {
      guessedList.add(guessedActor);
      sharedPref.setStringList(guessedKey, guessedList);
      _log.info("📜 Updated guessed names for $category Level $currentLevel: $guessedList");
    }

    // ✅ Retrieve user details
    final userId = sharedPref.getInt('user_id');
    final username = sharedPref.getString('username');
    final trimmedUsername = (username ?? '').trim();
    final bool isRegistered = trimmedUsername.isNotEmpty;

    sharedPref.setInt('points_${category}_level$currentLevel', updatedPoints);
    int totalPoints = await functionsHelper.getTotalPoints(context); // ✅ Get updated total

    _log.info(
      '[saveReward] progression | registered=$isRegistered user_id=$userId '
      'username=${trimmedUsername.isEmpty ? "(guest)" : trimmedUsername} '
      'category=$category level=$currentLevel points=$updatedPoints '
      'guessedCount=${guessedList.length} totalPoints=$totalPoints',
    );

    // ✅ Backend request to update rewards (guest: server returns flags only, no DB)
    Map<String, dynamic> response = {};
    try {
      _log.info('⚡ Sending updated rewards to backend (/update-rewards)...');

      response = await connectionModule.sendPostRequest(
        "/update-rewards",
        {
          "username": trimmedUsername.isEmpty ? null : trimmedUsername,
          "category": category,
          "level": currentLevel,
          "points": updatedPoints,
          "guessed_names": guessedList,
          "total_points": totalPoints,
        },
      );

      _log.info('📜 [saveReward] backend response: $response');

      final msg = response['message']?.toString();
      final okMessage = msg == 'Rewards updated successfully' || msg == 'Rewards acknowledged (guest)';
      final hasError = response['error'] != null;
      if (response.isEmpty || hasError || (!okMessage && (response['levelUp'] == null && response['endGame'] == null))) {
        _log.error(
          '❌ [saveReward] invalid or error response | error=${response['error']} message=$msg',
        );
      } else if (!okMessage) {
        _log.log('⚠️ [saveReward] unexpected message but level flags present: message=$msg', level: 900);
      }
    } catch (e) {
      _log.error('❌ [saveReward] request failed: $e', error: e);
    }

    // ✅ Update SharedPreferences based on backend response
    bool levelUp = response['levelUp'] == true;
    bool endGame = response['endGame'] == true;
    int newLevel = levelUp ? currentLevel + 1 : currentLevel;

    sharedPref.setInt('level_$category', newLevel);

    _log.info("📜 SharedPreferences total after update: $totalPoints");
    _log.info("🏆 Updated Rewards: Points: $updatedPoints | Level: $newLevel | Level Up: $levelUp | EndGame: $endGame");

    return {
      "points": updatedPoints,
      "endGame": endGame,
      "levelUp": levelUp,
      "totalPoints": totalPoints,
    };
  }

  /// ✅ Dispose method to clean up resources
  @override
  void dispose() {
    _log.info("🗑 RewardsModule disposed.");
    super.dispose();
  }
}
