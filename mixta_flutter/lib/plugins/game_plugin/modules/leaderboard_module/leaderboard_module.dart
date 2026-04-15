import 'package:mixta_guess_who/plugins/main_plugin/modules/connections_module/connections_module.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../core/00_base/module_base.dart';
import '../../../../core/managers/module_manager.dart';
import '../../../../core/managers/services_manager.dart';
import '../../../../core/services/shared_preferences.dart';
import '../../../../tools/logging/logger.dart';
import '../../../../utils/consts/theme_consts.dart'; // ✅ Import Theme

class LeaderboardModule extends ModuleBase {
  static final Logger _log = Logger(); // ✅ Use a static logger for static methods

  /// ✅ Constructor - No stored instances, dependencies fetched dynamically
  LeaderboardModule() : super("leaderboard_module") {
    _log.info('📢 LeaderboardModule initialized and auto-registered.');
  }

  /// ✅ Fetch leaderboard data from backend
  Future<Map<String, dynamic>> getLeaderboard(BuildContext context) async {
    final moduleManager = Provider.of<ModuleManager>(context, listen: false);
    final servicesManager = Provider.of<ServicesManager>(context, listen: false);

    final connectionModule = moduleManager.getLatestModule<ConnectionsModule>();
    final sharedPref = servicesManager.getService<SharedPrefManager>('shared_pref');

    if (connectionModule == null) {
      _log.error("❌ ConnectionModule not found!");
      return {};
    }

    if (sharedPref == null) {
      _log.error("❌ SharedPrefManager not found!");
      return {};
    }

    try {
      // ✅ Retrieve user's username from SharedPreferences
      final username = sharedPref.getString('username');
      String queryParams = "";

      if (username != null && username.isNotEmpty) {
        queryParams = "?username=$username";
        _log.info("⚡ Fetching leaderboard data with username from `/get-leaderboard$queryParams`...");
      } else {
        _log.info("⚡ Fetching global leaderboard from `/get-leaderboard`...");
      }

      // ✅ Send GET request (with or without username)
      final response = await connectionModule.sendGetRequest("/get-leaderboard$queryParams");

      _log.info("✅ Leaderboard response: $response");

      if (response != null && response.containsKey("leaderboard")) {
        return {
          "leaderboard": List<Map<String, dynamic>>.from(response["leaderboard"]),
          "user_rank": response["user_rank"] ?? null, // ✅ User rank if available
        };
      } else {
        _log.error("❌ Failed to retrieve leaderboard data.");
        return {};
      }
    } catch (e) {
      _log.error("❌ Error fetching leaderboard: $e");
      return {};
    }
  }



  /// ✅ **User Rank Card (Styled)**
  Widget buildUserRankCard(Map<String, dynamic>? userRank) {
    if (userRank == null) return const SizedBox.shrink();
    final rank = userRank["user_rank"] ?? userRank["rank"] ?? "-";

    return Card(
      color: AppColors.primaryColor, // ✅ Consistent dark theme
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: AppPadding.defaultPadding,
      child: Padding(
        padding: AppPadding.cardPadding,
        child: Column(
          children: [
            Text(
              "🏆 Your Rank",
              style: AppTextStyles.headingSmall(color: AppColors.accentColor),
            ),
            const SizedBox(height: 8),
            Text(
              "#$rank - ${userRank["username"]}",
              style: AppTextStyles.bodyLarge,
            ),
            Text(
              "⭐ Points: ${userRank["points"]}",
              style: AppTextStyles.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  /// ✅ **Leaderboard List (Styled)**
  Widget buildLeaderboardList(List<Map<String, dynamic>> leaderboard, String? currentUsername) {
    return Expanded(
      child: ListView.builder(
        itemCount: leaderboard.length,
        padding: AppPadding.defaultPadding,
        itemBuilder: (context, index) {
          final user = leaderboard[index];
          final rank = user["user_rank"] ?? user["rank"] ?? "-";

          return Card(
            color: (currentUsername != null && user["username"] == currentUsername)
                ? AppColors.accentColor.withOpacity(0.3) // ✅ Highlight current user
                : AppColors.primaryColor, // ✅ Default color
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.accentColor,
                child: Text(
                  "$rank", // ✅ Prefer backend `user_rank`, fallback to `rank`
                  style: AppTextStyles.bodyMedium,
                ),

              ),
              title: Text(
                user["username"] ?? "Unknown",
                style: AppTextStyles.bodyLarge,
              ),
              subtitle: Text(
                "⭐ Points: ${user["points"] ?? 0}",
                style: AppTextStyles.bodyMedium,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget buildNoAccountNotice(BuildContext context) {
    return Card(
      color: AppColors.primaryColor,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: AppPadding.defaultPadding,
      child: Padding(
        padding: AppPadding.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Create a username to save rank",
              style: AppTextStyles.headingSmall(color: AppColors.accentColor),
            ),
            const SizedBox(height: 8),
            const Text(
              "You are viewing the global leaderboard as a guest. Create a username in Preferences so your rank is tracked.",
              style: AppTextStyles.bodyMedium,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => context.go("/preferences"),
                icon: const Icon(Icons.person_add_alt_1, color: AppColors.accentColor),
                label: Text(
                  "Go to Preferences",
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.accentColor),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.accentColor),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ✅ **Leaderboard Screen Widget**
  Widget buildLeaderboardWidget(BuildContext context) {
    final servicesManager = Provider.of<ServicesManager>(context, listen: false);
    final sharedPref = servicesManager.getService<SharedPrefManager>('shared_pref');
    final username = sharedPref?.getString('username');
    final hasAccount = username != null && username.isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackgroundColor, // ✅ Ensure solid background
      body: FutureBuilder<Map<String, dynamic>>(
        future: getLeaderboard(context),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || snapshot.data == null || snapshot.data!["leaderboard"] == null) {
            return const Center(
              child: Text("No leaderboard data available.", style: AppTextStyles.bodyLarge),
            );
          }

          final leaderboard = List<Map<String, dynamic>>.from(snapshot.data!["leaderboard"]);
          final userRank = snapshot.data!["user_rank"];
          final currentUsername = userRank != null ? userRank["username"] : null;

          return Column(
            children: [
              if (!hasAccount) buildNoAccountNotice(context),
              buildUserRankCard(userRank),
              buildLeaderboardList(leaderboard, currentUsername),
            ],
          );
        },
      ),
    );
  }
}
