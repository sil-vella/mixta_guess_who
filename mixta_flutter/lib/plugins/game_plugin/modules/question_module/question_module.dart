import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/00_base/module_base.dart';
import '../../../../core/managers/module_manager.dart';
import '../../../../core/managers/services_manager.dart';
import '../../../../core/services/shared_preferences.dart';
import '../../../../tools/logging/logger.dart';
import '../../../main_plugin/modules/connections_module/connections_module.dart';

class QuestionModule extends ModuleBase {
  static final Logger _log = Logger(); // ✅ Use a static logger for static methods

  /// ✅ Constructor - No stored instances, dependencies are fetched dynamically
  QuestionModule() : super("question_module") {
    _log.info('✅ QuestionModule initialized.');
  }

  /// ✅ Retrieve guessed names from SharedPreferences
  Future<List<String>> getGuessedNames(BuildContext context, String category, int level) async {
    final servicesManager = Provider.of<ServicesManager>(context, listen: false);
    final sharedPref = servicesManager.getService<SharedPrefManager>('shared_pref');

    if (sharedPref == null) {
      _log.error("❌ SharedPreferences service not available.");
      return [];
    }

    String guessedKey = "guessed_${category}_level$level";
    List<String> guessedNames = sharedPref.getStringList(guessedKey);

    _log.info("📜 Retrieved guessed names for $category Level $level: $guessedNames");
    return guessedNames;
  }

  /// ✅ Fetch a question from the backend
  Future<Map<String, dynamic>> getQuestion(BuildContext context, int difficulty, String category, List<String> guessedNames) async {
    final traceId = DateTime.now().microsecondsSinceEpoch;
    final stopwatch = Stopwatch()..start();
    _log.info("🚦 [q:$traceId] getQuestion start | difficulty=$difficulty | category=$category | guessedCount=${guessedNames.length}");
    final moduleManager = Provider.of<ModuleManager>(context, listen: false);
    final connectionModule = moduleManager.getLatestModule<ConnectionsModule>();

    if (connectionModule == null) {
      _log.error("❌ [q:$traceId] ConnectionModule not found in QuestionModule.");
      return {"error": "Connection module not available"};
    }

    try {
      // ✅ Build request payload including guessed names
      final payload = {
        "level": difficulty,
        "category": category,
        "guessed_names": guessedNames,
      };

      _log.info("⚡ [q:$traceId] Sending POST request to `/get-question` with payload: $payload");

      final response = await connectionModule.sendPostRequest("/get-question", payload);
      stopwatch.stop();

      _log.info("✅ [q:$traceId] Response received in ${stopwatch.elapsedMilliseconds}ms | keys=${response.keys.toList()}");
      _log.debug("📦 [q:$traceId] Response Body: $response");

      return response;
    } catch (e) {
      stopwatch.stop();
      _log.error("❌ [q:$traceId] Error fetching question from backend after ${stopwatch.elapsedMilliseconds}ms: $e", error: e);
      return {"error": "Failed to fetch question from server"};
    }
  }

  /// ✅ Checks if the given answer matches the correct answer
  bool checkAnswer(String input, String correctAnswer) {
    return input.trim().toLowerCase() == correctAnswer.trim().toLowerCase();
  }

  /// ✅ Dispose method to clean up resources
  @override
  void dispose() {
    _log.info("🗑 QuestionModule disposed.");
    super.dispose();
  }
}
