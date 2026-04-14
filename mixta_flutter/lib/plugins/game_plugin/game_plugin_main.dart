import 'package:flutter/foundation.dart';
import 'package:mixta_guess_who/plugins/game_plugin/modules/game_play_module/game_play_module.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mixta_guess_who/plugins/game_plugin/modules/function_helper_module/function_helper_module.dart';
import 'package:mixta_guess_who/plugins/game_plugin/modules/leaderboard_module/leaderboard_module.dart';
import 'package:mixta_guess_who/plugins/game_plugin/modules/rewards_module/rewards_module.dart';
import 'package:mixta_guess_who/plugins/game_plugin/modules/question_module/question_module.dart';
import 'package:mixta_guess_who/plugins/game_plugin/screens/game_screen/game_screen.dart';
import 'package:mixta_guess_who/plugins/game_plugin/screens/leaderboard_screen/leaderboard_screen.dart';
import 'package:mixta_guess_who/plugins/game_plugin/screens/level_up_screen/level_up_screen.dart';
import 'package:mixta_guess_who/plugins/game_plugin/screens/progress_screen/progress_screen.dart';

import '../../core/00_base/module_base.dart';
import '../../core/00_base/plugin_base.dart';
import '../../core/managers/hooks_manager.dart';
import '../../core/managers/module_manager.dart';
import '../../core/managers/navigation_manager.dart';
import '../../core/managers/services_manager.dart';
import '../../core/managers/state_manager.dart';
import '../../core/services/shared_preferences.dart';
import '../../tools/logging/logger.dart';
import '../main_plugin/modules/connections_module/connections_module.dart';
import '../main_plugin/screens/preferences_screen/preferences_screen.dart';

class GamePlugin extends PluginBase {
  late final NavigationManager navigationManager;

  GamePlugin();

  @override
  void initialize(BuildContext context) {
    log.info("🔄 Initializing ${runtimeType.toString()}...");

    super.initialize(context);
    final moduleManager = Provider.of<ModuleManager>(context, listen: false);
    final servicesManager = Provider.of<ServicesManager>(context, listen: false);
    final stateManager = Provider.of<StateManager>(context, listen: false);
    navigationManager = Provider.of<NavigationManager>(context, listen: false);

    getCategories(context); // ✅ Fetch categories dynamically
    _initializeUserData(context); // ✅ Initialize user data
    _registerGameTimerState(stateManager);
    _registerNavigation();

    // ✅ Register all game-related modules in ModuleManager
    final modules = createModules();
    for (var entry in modules.entries) {
      final instanceKey = entry.key;
      final module = entry.value;
      moduleManager.registerModule(module, instanceKey: instanceKey);
    }
  }

  /// ✅ Register game-related modules
  @override
  Map<String?, ModuleBase> createModules() {
    return {
      null: GamePlayModule(),
      null: QuestionModule(),
      null: RewardsModule(),
      null: LeaderboardModule(),
      null: FunctionHelperModule(),
    };
  }


  /// ✅ Define initial states for this plugin
  @override
  Map<String, Map<String, dynamic>> getInitialStates() {
    return {
      "game_timer": {
        "isRunning": false,
        "duration": 30, // Default duration
      },
      "game_round": {
        "roundNumber": 0,
        "hint": false,
        "imagesLoaded": false,
        "factLoaded": false,
      }
    };
  }

  void _registerNavigation() {
    navigationManager.registerRoute(
      path: '/game',
      screen: (context) => const GameScreen(),
      drawerTitle: 'Play Guess Who', // ✅ Add to drawer
      drawerIcon: Icons.leaderboard,
      drawerPosition: 2,
    );
    navigationManager.registerRoute(
      path: '/leaderboard',
      screen: (context) => const TimerModule(),
      drawerTitle: 'Leaderboard', // ✅ Add to drawer
      drawerIcon: Icons.leaderboard,
      drawerPosition: 4,
    );

    navigationManager.registerRoute(
      path: '/progress',
      screen: (context) => const ProgressScreen(),
      drawerTitle: 'My Progress', // ✅ Add to drawer
      drawerIcon: Icons.emoji_events,
      drawerPosition: 3,
    );

    navigationManager.registerRoute(
      path: '/level-up',
      screen: (context) => const LevelUpScreen(),
    ); // ❌ No drawerTitle, so it WON'T appear in the drawer
  }


  /// ✅ Register game timer state in StateManager
  void _registerGameTimerState(StateManager stateManager) {
    if (!stateManager.isPluginStateRegistered("game_timer")) {
      stateManager.registerPluginState("game_timer", {
        "isRunning": false,
        "duration": 30, // Default duration
      });

      Logger().info("✅ Game timer state registered.");
    }
  }

  /// ✅ Fetch game categories and update only if changed
  Future<void> getCategories(BuildContext context) async {
    final moduleManager = Provider.of<ModuleManager>(context, listen: false);
    final servicesManager = Provider.of<ServicesManager>(context, listen: false);
    final connectionModule = moduleManager.getLatestModule<ConnectionsModule>();
    final sharedPref = servicesManager.getService<SharedPrefManager>('shared_pref');

    if (connectionModule == null) {
      Logger().error('❌ ConnectionModule not found in ModuleManager.');
      return;
    }

    if (sharedPref == null) {
      Logger().error('❌ SharedPreferences service not available.');
      return;
    }

    try {
      Logger().info('⚡ Fetching categories from `/get-categories`...');
      final response = await connectionModule.sendGetRequest('/get-categories');

      if (response != null && response is Map<String, dynamic> && response.containsKey("categories")) {
        final Map<String, dynamic> categoriesMap = response["categories"];
        List<String> fetchedCategories = categoriesMap.keys.toList();

        Logger().info("✅ Fetched categories from backend: $fetchedCategories");

        // ✅ Get currently stored categories
        List<String>? storedCategories = sharedPref.getStringList('available_categories') ?? [];

        // ✅ Only update if the categories have changed
        if (storedCategories.isEmpty || !listEquals(storedCategories, fetchedCategories)) {
          Logger().info("🔄 Categories changed, updating SharedPreferences...");

          await sharedPref.setStringList('available_categories', fetchedCategories);

          // ✅ Store max levels per category
          for (String category in categoriesMap.keys) {
            int levels = categoriesMap[category]["levels"] ?? 2;
            await sharedPref.setInt('max_levels_$category', levels);
            Logger().info("✅ Saved max levels for $category: $levels");
          }

          Logger().info('✅ Categories and levels updated in SharedPreferences.');
        } else {
          Logger().info("✅ Categories are unchanged. No update needed.");
        }

        // ✅ Ensure initialization even if categories didn’t change
        await _initializeCategorySystem(fetchedCategories, sharedPref);
      } else {
        Logger().error('❌ Failed to fetch categories. Unexpected response format: $response');
      }
    } catch (e) {
      Logger().error('❌ Error fetching categories: $e', error: e);
    }
  }

  Future<void> _initializeUserData(BuildContext context) async {
    final servicesManager = Provider.of<ServicesManager>(context, listen: false);
    final sharedPref = servicesManager.getService<SharedPrefManager>('shared_pref');

    if (sharedPref == null) {
      Logger().error('❌ SharedPrefManager not found.');
      return;
    }

    // ✅ Store user profile details if not already set
    String? username = sharedPref.getString('username');
    if (username == null) {
      sharedPref.setString('username', '');
      sharedPref.setString('email', '');
      sharedPref.setString('password', '');
    }

    // ✅ Check if categories are already saved
    List<String>? categories = sharedPref.getStringList('available_categories');
    if (categories == null || categories.isEmpty) {
      Logger().info("📜 Categories not found. Fetching from backend...");
      await getCategories(context);
    } else {
      Logger().info("✅ Categories already initialized in SharedPreferences.");
      await _initializeCategorySystem(categories, sharedPref);
    }
  }


  /// ✅ Initialize SharedPreferences keys for levels, points, and guessed names
  Future<void> _initializeCategorySystem(List<String> categories, SharedPrefManager sharedPref) async {
    try {
      Logger().info("⚙️ Initializing SharedPreferences for levels, points, and guessed names...");

      for (String category in categories) {
        // ✅ Fetch max levels directly
        int maxLevels = sharedPref.getInt('max_levels_$category') ?? 0;

        // ✅ Default to level 1
        String levelKey = "level_$category";
        int currentLevel = sharedPref.getInt(levelKey) ?? 1;
        sharedPref.setInt(levelKey, currentLevel);

        for (int level = 1; level <= maxLevels; level++) {
          String pointsKey = "points_${category}_level$level";
          String guessedKey = "guessed_${category}_level$level";

          // ✅ Set default points directly
          sharedPref.setInt(pointsKey, sharedPref.getInt(pointsKey) ?? 0);

          // ✅ Set empty guessed names list directly
          sharedPref.setStringList(guessedKey, sharedPref.getStringList(guessedKey) ?? []);

          Logger().info("✅ Initialized keys for $category: level $level");
        }
      }
    } catch (e) {
      Logger().error("❌ Error initializing category system: $e", error: e);
    }
  }

}
