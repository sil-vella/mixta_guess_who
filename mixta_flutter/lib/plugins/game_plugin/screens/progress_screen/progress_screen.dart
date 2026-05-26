import 'package:flutter/material.dart';
import '../../../../utils/navigation_utils.dart';
import 'package:provider/provider.dart';
import '../../../../core/00_base/screen_base.dart';
import '../../../../core/managers/services_manager.dart';
import '../../../../core/services/shared_preferences.dart';
import '../../../../tools/logging/logger.dart';
import '../../../../utils/consts/theme_consts.dart';

class ProgressScreen extends BaseScreen {
  const ProgressScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) {
    return 'Category Progress';
  }

  @override
  ProgressScreenState createState() => ProgressScreenState();
}

class ProgressScreenState extends BaseScreenState<ProgressScreen> {
  final Logger logger = Logger();

  late ServicesManager _servicesManager;
  SharedPrefManager? _sharedPref;

  Map<String, dynamic> _categories = {};
  int _totalPoints = 0;
  bool _isLoading = true;
  bool _isGuest = true;

  @override
  void initState() {
    super.initState();
    logger.info("📊 Initializing ProgressScreen...");

    // ✅ Retrieve managers using Provider
    _servicesManager = Provider.of<ServicesManager>(context, listen: false);

    // ✅ Retrieve services
    _sharedPref = _servicesManager.getService<SharedPrefManager>('shared_pref');

    if (_sharedPref == null) {
      logger.error('❌ SharedPreferences service not available.');
      setState(() {
        _isLoading = false;
        _isGuest = true;
      });
      return;
    }

    _fetchCategories();
  }

  bool _computeIsGuest() {
    final u = _sharedPref?.getString('username');
    return u == null || u.trim().isEmpty;
  }

  Future<void> _fetchCategories() async {
    if (_sharedPref == null) return;

    List<String> cachedCategories = _sharedPref!.getStringList('available_categories');
    if (cachedCategories.isEmpty) {
      final keys = _sharedPref!.getKeys();
      final inferred = <String>{};
      for (final key in keys) {
        if (key.startsWith('max_levels_')) {
          inferred.add(key.substring('max_levels_'.length));
        } else if (key.startsWith('level_')) {
          inferred.add(key.substring('level_'.length));
        } else if (key.startsWith('points_') && key.contains('_level')) {
          final category = key.substring('points_'.length, key.indexOf('_level'));
          if (category.isNotEmpty) inferred.add(category);
        } else if (key.startsWith('guessed_') && key.contains('_level')) {
          final rest = key.substring('guessed_'.length);
          final idx = rest.lastIndexOf('_level');
          if (idx > 0) inferred.add(rest.substring(0, idx));
        }
      }
      if (inferred.isNotEmpty) {
        cachedCategories = inferred.toList();
        logger.info('📜 Inferred categories from SharedPreferences keys: $cachedCategories');
      }
    }

    if (cachedCategories.isNotEmpty) {
      logger.info('📜 Loaded categories from SharedPreferences: $cachedCategories');

      Map<String, dynamic> categoryData = {};

      for (String category in cachedCategories) {
        int maxLevels = _sharedPref!.getInt('max_levels_$category') ?? 1;
        int currentLevel = _sharedPref!.getInt('level_$category') ?? 1;

        int categoryPoints = 0;
        int guessedNamesCount = 0;

        for (int level = 1; level <= maxLevels; level++) {
          int points = _sharedPref!.getInt('points_${category}_level$level') ?? 0;
          List<String> guessedNames = _sharedPref!.getStringList('guessed_${category}_level$level');

          categoryPoints += points;
          guessedNamesCount += guessedNames.length;
        }

        categoryData[category] = {
          "level": currentLevel,
          "points": categoryPoints,
          "guessedNamesCount": guessedNamesCount,
        };

        logger.info("📊 Category: $category -> Level: $currentLevel, Points: $categoryPoints, Guessed: $guessedNamesCount");
      }

      final int totalPoints = categoryData.values.fold<int>(
        0,
            (sum, item) => sum + ((item["points"] as int?) ?? 0),
      );

      setState(() {
        _categories = categoryData;
        _totalPoints = totalPoints;
        _isLoading = false;
        _isGuest = _computeIsGuest();
      });

      return;
    }

    logger.error('⚠️ No categories found in SharedPreferences.');
    if (mounted) {
      // Categories may be set a moment later by game plugin initialization; retry once.
      Future.delayed(const Duration(milliseconds: 500), () async {
        if (!mounted || _sharedPref == null) return;
        final retryCategories = _sharedPref!.getStringList('available_categories');
        if (retryCategories.isNotEmpty) {
          await _fetchCategories();
        } else {
          setState(() {
            _isLoading = false;
            _isGuest = _computeIsGuest();
          });
        }
      });
    }
  }

  /// ✅ Format category name (Replace `_` with space & capitalize first letter)
  String _formatCategoryName(String category) {
    return category.replaceAll("_", " ").splitMapJoin(
      RegExp(r'(\w+)'),
      onMatch: (m) => m[0]![0].toUpperCase() + m[0]!.substring(1).toLowerCase(),
    );
  }

  /// Call-to-action for guests: leaderboard requires a registered username.
  Widget _buildGuestLeaderboardHint() {
    if (_isLoading || !_isGuest) return const SizedBox.shrink();

    return Padding(
      padding: AppPadding.defaultPadding,
      child: Card(
        color: AppColors.primaryColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: AppPadding.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Leaderboard',
                style: AppTextStyles.headingSmall(color: AppColors.white),
              ),
              const SizedBox(height: 8),
              Text(
                'Create a username in Preferences to save your progress to the server and appear on the leaderboard.',
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.white),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => NavigationUtils.navigateForward(context, '/preferences'),
                  child: Text(
                    'Go to Preferences',
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.accentColor),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ✅ UI for displaying total points
  Widget _buildTotalPointsCard() {
    return Padding(
      padding: AppPadding.defaultPadding,
      child: Card(
        color: AppColors.accentColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          width: double.infinity, // ✅ Full width
          padding: AppPadding.cardPadding,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center, // ✅ Centered content
            crossAxisAlignment: CrossAxisAlignment.center, // ✅ Center text horizontally
            children: [
              Text(
                "🏆 Total Points",
                style: AppTextStyles.headingSmall(color: AppColors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "$_totalPoints",
                style: AppTextStyles.headingLarge(color: AppColors.white),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ✅ UI for displaying category progress
  Widget _buildCategoryProgress() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_categories.isEmpty) {
      return Center(
        child: Text(
          "No category progress found.",
          style: AppTextStyles.bodyLarge,
        ),
      );
    }

    return Expanded(
      child: ListView.builder(
        itemCount: _categories.length,
        padding: AppPadding.defaultPadding,
        itemBuilder: (context, index) {
          final category = _categories.keys.elementAt(index);
          final data = _categories[category];

          return Card(
            color: AppColors.primaryColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: ListTile(
              contentPadding: AppPadding.cardPadding,
              title: Text(
                _formatCategoryName(category),
                style: AppTextStyles.headingSmall(),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  "🔹 Level: ${data["level"]}\n⭐ Points: ${data["points"]}\n🎯 Guessed Names: ${data["guessedNamesCount"]}",
                  style: AppTextStyles.bodyMedium,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget buildContent(BuildContext context) {
    return Column(
      children: [
        _buildTotalPointsCard(),
        _buildGuestLeaderboardHint(),
        _buildCategoryProgress(),
      ],
    );
  }
}
