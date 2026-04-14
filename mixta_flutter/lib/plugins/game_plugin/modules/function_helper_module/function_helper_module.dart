import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/00_base/module_base.dart';
import '../../../../core/managers/module_manager.dart';
import '../../../../core/managers/services_manager.dart';
import '../../../../core/services/shared_preferences.dart';
import '../../../../tools/logging/logger.dart';
import '../../../main_plugin/modules/main_helper_module/main_helper_module.dart';

class FunctionHelperModule extends ModuleBase {
  static final Logger _log = Logger();

  /// ✅ Constructor with module key
  FunctionHelperModule() : super("game_functions_helper_module") {
    _log.info('🚀 FunctionHelperModule initialized and auto-registered.');
  }

  /// ✅ Fetches total points from all categories
  Future<int> getTotalPoints(BuildContext context) async {
    final sharedPref = Provider.of<ServicesManager>(context, listen: false).getService<SharedPrefManager>('shared_pref');

    if (sharedPref == null) {
      _log.error('❌ SharedPreferences service not available.');
      return 0;
    }

    List<String> categories = sharedPref.getStringList('available_categories') ?? [];

    int totalPoints = 0;

    for (String category in categories) {
      int maxLevels = sharedPref.getInt('max_levels_$category') ?? 1;

      for (int level = 1; level <= maxLevels; level++) {
        int points = sharedPref.getInt('points_${category}_level$level') ?? 0;
        totalPoints += points;
      }
    }

    _log.info("🏆 Total Points across all categories: $totalPoints");
    return totalPoints;
  }

  /// ✅ Store image cache timestamp
  Future<void> storeImageCacheTimestamp(BuildContext context, String imageUrl) async {
    final sharedPref = Provider.of<ServicesManager>(context, listen: false).getService<SharedPrefManager>('shared_pref');

    if (sharedPref == null) {
      _log.error('❌ SharedPreferences service not available.');
      return;
    }

    String? cachedImages = sharedPref.getString('cached_images');
    Map<String, int> imageCacheMap = cachedImages != null ? Map<String, int>.from(jsonDecode(cachedImages)) : {};

    if (imageCacheMap.containsKey(imageUrl)) {
      return;
    }

    imageCacheMap[imageUrl] = DateTime.now().millisecondsSinceEpoch;
    await cleanupExpiredImages(context);
    sharedPref.setString('cached_images', jsonEncode(imageCacheMap));
  }

  /// ✅ Clean up expired images from SharedPreferences
  Future<void> cleanupExpiredImages(BuildContext context) async {
    final sharedPref = Provider.of<ServicesManager>(context, listen: false).getService<SharedPrefManager>('shared_pref');

    if (sharedPref == null) {
      _log.error('❌ SharedPreferences service not available.');
      return;
    }

    String? cachedImages = sharedPref.getString('cached_images');
    if (cachedImages == null) return;

    Map<String, int> imageCacheMap = Map<String, int>.from(jsonDecode(cachedImages));

    final int now = DateTime.now().millisecondsSinceEpoch;
    final int twoMonthsAgo = now - (60 * 24 * 60 * 60 * 1000); // ✅ 60 days in milliseconds

    imageCacheMap.removeWhere((_, timestamp) => timestamp < twoMonthsAgo);
    sharedPref.setString('cached_images', jsonEncode(imageCacheMap));
  }

  /// ✅ Clear all user progress
  Future<void> clearUserProgress(BuildContext context) async {
    final sharedPref = Provider.of<ServicesManager>(context, listen: false).getService<SharedPrefManager>('shared_pref');

    if (sharedPref == null) {
      _log.error('❌ SharedPrefManager not found.');
      return;
    }

    try {
      _log.info("🧹 Resetting SharedPreferences values for levels, points, and guessed names...");

      // ✅ Fetch all keys from SharedPreferences
      final Set<String> allKeys = sharedPref.getKeys();

      if (allKeys.isEmpty) {
        _log.info("⚠️ No keys found in SharedPreferences.");
        return;
      }

      _log.info("✅ Retrieved all keys from SharedPreferences: $allKeys");

      for (String key in allKeys) {
        // Check if the key contains 'level', 'points', or 'guessed'
        if (key.contains('level') || key.contains('points') || key.contains('guessed')) {
          // Determine the type of the value and reset it
          dynamic value = sharedPref.get(key);

          if (value is int) {
            int resetValue = key.contains('level_') ? 1 : 0; // ✅ Levels reset to 1, Points reset to 0
            sharedPref.setInt(key, resetValue);
            _log.info("✅ Reset key: $key to $resetValue");

          } else if (value is List<String>) {
            // ✅ Reset lists to empty
            sharedPref.setStringList(key, []);
            _log.info("✅ Reset key: $key to []");

          } else if (value is String) {
            // ✅ Reset strings to empty (if applicable)
            sharedPref.setString(key, '');
            _log.info("✅ Reset key: $key to ''");

          } else {
            _log.info("⚠️ Key $key has an unsupported type: ${value.runtimeType}");
          }
        }
      }

      _log.info("✅ SharedPreferences values reset successfully.");
    } catch (e) {
      _log.error("❌ Error resetting category system: $e", error: e);
    }
  }
}
