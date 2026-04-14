import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/00_base/screen_base.dart';
import '../../../../core/managers/services_manager.dart';
import '../../../../core/managers/module_manager.dart';
import '../../../../core/services/shared_preferences.dart';
import '../../../../tools/logging/logger.dart';
import '../../../../utils/consts/theme_consts.dart';
import '../../modules/function_helper_module/function_helper_module.dart';

class ProgressScreen extends BaseScreen {
  const ProgressScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) {
    return "Well Done!";
  }

  @override
  ProgressScreenState createState() => ProgressScreenState();
}

class ProgressScreenState extends BaseScreenState<ProgressScreen> {
  final Logger logger = Logger();

  late ServicesManager _servicesManager;
  late ModuleManager _moduleManager;
  FunctionHelperModule? _functionHelperModule;
  SharedPrefManager? _sharedPref;

  Map<String, dynamic> _categories = {};
  int _totalPoints = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    logger.info("📊 Initializing ProgressScreen...");

    // ✅ Retrieve managers using Provider
    _servicesManager = Provider.of<ServicesManager>(context, listen: false);
    _moduleManager = Provider.of<ModuleManager>(context, listen: false);

    // ✅ Retrieve modules and services
    _functionHelperModule = _moduleManager.getLatestModule<FunctionHelperModule>();
    _sharedPref = _servicesManager.getService<SharedPrefManager>('shared_pref');

    if (_sharedPref == null) {
      logger.error('❌ SharedPreferences service not available.');
      setState(() => _isLoading = false);
      return;
    }

    _fetchCategories();
  }

  Future<void> _fetchCategories() async {
    if (_sharedPref == null) return;

    List<String> cachedCategories = _sharedPref!.getStringList('available_categories');

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

      int totalPoints = await _functionHelperModule?.getTotalPoints(context) ?? 0;

      setState(() {
        _categories = categoryData;
        _totalPoints = totalPoints;
        _isLoading = false;
      });

      return;
    }

    logger.error('⚠️ No categories found in SharedPreferences.');
    setState(() => _isLoading = false);
  }

  /// ✅ Format category name (Replace `_` with space & capitalize first letter)
  String _formatCategoryName(String category) {
    return category.replaceAll("_", " ").splitMapJoin(
      RegExp(r'(\w+)'),
      onMatch: (m) => m[0]![0].toUpperCase() + m[0]!.substring(1).toLowerCase(),
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
    return Scaffold(
      appBar: AppBar(title: const Text("Category Progress")),
      backgroundColor: AppColors.scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildTotalPointsCard(),
          _buildCategoryProgress(),
        ],
      ),
    );
  }
}
