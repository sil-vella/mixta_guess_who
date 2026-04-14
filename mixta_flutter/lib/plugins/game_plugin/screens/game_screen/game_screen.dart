import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math';
import '../../../../core/00_base/screen_base.dart';
import '../../../../core/managers/module_manager.dart';
import '../../../../core/managers/services_manager.dart';
import '../../../../core/managers/state_manager.dart';
import '../../../../core/services/shared_preferences.dart';
import '../../../../core/services/ticker_timer/ticker_timer.dart';
import '../../../../tools/logging/logger.dart';
import '../../../../utils/consts/theme_consts.dart';
import '../../../adverts_plugin/modules/admobs/rewarded/rewarded_ad.dart';
import '../../../main_plugin/modules/main_helper_module/main_helper_module.dart';
import '../../modules/game_play_module/config/gameplaymodule_config.dart';
import '../../modules/game_play_module/game_play_module.dart';
import 'components/fact_box.dart';
import 'components/feedback_message.dart';
import 'components/game_image_grid.dart';
import 'components/screen_overlay.dart';
import 'components/timer_component.dart';

class GameScreen extends BaseScreen {
  const GameScreen({Key? key}) : super(key: key);

  @override
  String computeTitle(BuildContext context) {
    return "Guess Who";
  }

  @override
  GameScreenState createState() => GameScreenState();
}

class GameScreenState extends BaseScreenState<GameScreen> {
  static final Logger _log = Logger(); // ✅ Use a static logger for logging

  late final ModuleManager _moduleManager;
  late final ServicesManager _servicesManager;
  late final SharedPrefManager? _sharedPref;
  late final StateManager _stateManager;
  late final GamePlayModule? _gamePlayModule;
  late final MainHelperModule? _mainHelperModule;
  late final RewardedAdModule? _rewardedAdModule;
  late final TickerTimer? _roundTimer;

  bool _showFeedback = false;
  bool _helpUsed = false; // ✅ Track if help has been used
  String _feedbackText = "";
  String _correctName = "";
  Timer? _feedbackTimer;
  int _level = 1;
  int _points = 0;
  String _backgroundImage = "";
  final Random _random = Random();
  Set<String> fadedImages = {}; // ✅ Tracks faded images
  CachedNetworkImageProvider? _cachedSelectedImage;

  @override
  void initState() {
    super.initState();
    _log.info("Initializing GameScreen...");

    // ✅ Retrieve managers and modules via Provider
    _moduleManager = Provider.of<ModuleManager>(context, listen: false);
    _servicesManager = Provider.of<ServicesManager>(context, listen: false);
    _stateManager = Provider.of<StateManager>(context, listen: false);

    _sharedPref = _servicesManager.getService<SharedPrefManager>('shared_pref');
    _gamePlayModule = _moduleManager.getLatestModule<GamePlayModule>();
    _mainHelperModule = _moduleManager.getLatestModule<MainHelperModule>();
    _rewardedAdModule = _moduleManager.getLatestModule<RewardedAdModule>();

    // ✅ Ensure `round_timer` is only registered if it doesn't exist
    _roundTimer = _servicesManager.getService<TickerTimer>('round_timer');
    _log.info("🎯 initState services/modules loaded | hasSharedPref=${_sharedPref != null} | hasGamePlayModule=${_gamePlayModule != null} | hasMainHelper=${_mainHelperModule != null} | hasRewardedAd=${_rewardedAdModule != null} | hasRoundTimer=${_roundTimer != null}");

    if (_roundTimer == null) {
      _log.info("🧩 round_timer missing; registering new TickerTimer service...");
      _servicesManager.registerService('round_timer', TickerTimer(id: 'round_timer')).then((_) {
        // ✅ After registration, retrieve the instance
        _roundTimer = _servicesManager.getService<TickerTimer>('round_timer');
        _log.info("✅ round_timer registration future completed | hasRoundTimer=${_roundTimer != null}");
      });
    }

    _initializeGame();
    _loadLevelAndPoints();
  }



  void _onImagesLoaded() {
    _log.info("🖼️ ALL images loaded. Updating game state...");

    _stateManager.updatePluginState("game_round", {
      "imagesLoaded": true,
    }, force: true);
  }

  void _onFactsLoaded() {
    _stateManager.updatePluginState("game_round", {
      "factLoaded": true,
    }, force: true);
  }

  bool get _isOverlayVisible {
    return context.select<StateManager, bool>((stateManager) {
      final gameRoundState = stateManager.getPluginState<Map<String, dynamic>>("game_round") ?? {};
      return !(gameRoundState["imagesLoaded"] == true && gameRoundState["factLoaded"] == true);
    });
  }
  void _useHelp() {
    _log.info("⏳ Entering _useHelp...");

    if (_helpUsed) {
      _log.info("🚫 Help already used! Button disabled.");
      return; // ✅ Prevent multiple uses
    }

    _helpUsed = true; // ✅ Mark help as used

    TickerTimer? roundTimer = _servicesManager.getService<TickerTimer>('round_timer');

    if (_rewardedAdModule != null && _mainHelperModule != null) {
      if (roundTimer != null && roundTimer.isRunning) {
        _log.info("⏸ Pausing timer before showing ad.");
        roundTimer.pauseTimer();
      }

      _stateManager.updatePluginState("game_round", {
        "hint": true,
      });

      _rewardedAdModule!.showAd(
        context,
        onUserEarnedReward: _fadeOutIncorrectImage,
        onAdDismissed: () {
          _log.info("✅ Ad dismissed! Attempting to resume timer...");

          Future.delayed(const Duration(milliseconds: 500), () {
            if (roundTimer == null) {
              _log.error("❌ roundTimer instance is null after ad dismissal!");
            } else {
              _log.info("🔍 roundTimer instance exists. isPaused: ${roundTimer.isPaused}, isRunning: ${roundTimer.isRunning}");

              if (roundTimer.isPaused) {
                _log.info("▶ Resuming timer after ad...");
                roundTimer.startTimer();
              } else {
                _log.error("❌ roundTimer is NOT paused. Cannot resume.");
              }
            }
          });
        },
      );

      _log.info("🎬 Ad is being shown...");
    } else {
      _log.error("❌ RewardedAdModule or MainHelperModule not found!");
    }
  }

  void _fadeOutIncorrectImage() {
    if (_correctAnswer == null) return;

    List<String> incorrectImages = _gamePlayModule?.imageOptions
        .where((img) => img != _correctAnswer && !fadedImages.contains(img))
        .toList() ??
        [];

    if (incorrectImages.isNotEmpty) {
      String fadedImage = incorrectImages[_random.nextInt(incorrectImages.length)];

      setState(() {
        fadedImages = Set.from(fadedImages)..add(fadedImage);
      });

      _log.info("🚫 An incorrect image has been faded out: $fadedImage");
    }
  }

  Future<void> _loadLevelAndPoints() async {
    if (_sharedPref == null) {
      _log.error('❌ SharedPreferences service not available.');
      return;
    }

    final String category = _sharedPref!.getString('category') ?? "actors";
    final int level = _sharedPref!.getInt('level_$category') ?? 1;
    int categoryPoints = 0;

    final int maxLevels = _sharedPref!.getInt('max_levels_$category') ?? 1;

    for (int lvl = 1; lvl <= maxLevels; lvl++) {
      int points = _sharedPref!.getInt('points_${category}_level$lvl') ?? 0;
      categoryPoints += points;
    }

    setState(() {
      _level = level;
      _points = categoryPoints;
    });

    _log.info("📊 Current Category: $category | Level: $_level | Points in Category: $_points");
  }

  /// Modal when the server reports level complete (`levelUp`) or category maxed (`endGame`).
  void _showLevelProgressModal(int traceId, {required bool isEndGame}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          final bool completedCategory = isEndGame;
          final String title = completedCategory ? 'Category complete' : 'Level up';
          final String body = completedCategory
              ? 'You finished every level in this category. Pick another category or play again from preferences.'
              : 'You guessed everyone on this level. Continue to load the next level.';

          return AlertDialog(
            backgroundColor: AppColors.primaryColor,
            title: Text(title, style: AppTextStyles.headingMedium()),
            content: SingleChildScrollView(
              child: Text(body, style: AppTextStyles.bodyLarge),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentColor,
                  foregroundColor: AppColors.white,
                  padding: AppPadding.cardPadding,
                ),
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  _stateManager.updatePluginState("game_round", {
                    "levelUp": false,
                    "endGame": false,
                  }, force: true);
                  if (completedCategory) {
                    Navigator.pushReplacementNamed(context, "/preferences");
                  } else {
                    _loadLevelAndPoints();
                    _startRoundFromScratch(traceId);
                  }
                },
                child: Text(
                  completedCategory ? 'Back to profile' : 'Continue',
                  style: AppTextStyles.buttonText,
                ),
              ),
            ],
          );
        },
      );
    });
  }

  /// Loads background, clears round UI, fetches the next question, starts timer.
  void _startRoundFromScratch(int traceId) {
    final stateManager = _stateManager;

    _setRandomBackground();
    Logger().info("🎨 [round:$traceId] Background prepared");

    setState(() {
      _correctAnswer = null;
      fadedImages.clear();
      _gamePlayModule?.imageOptions = [];
    });
    Logger().info("🧹 [round:$traceId] Cleared local round UI state");

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Logger().info("🧭 [round:$traceId] postFrameCallback -> resetting game_round overlay flags");
      stateManager.updatePluginState("game_round", {
        "hint": false,
        "imagesLoaded": false,
        "factLoaded": false,
      }, force: true);
    });

    setState(() {
      _gamePlayModule?.question = null;
    });
    Logger().info("🧽 [round:$traceId] Cleared module question before fetch");

    Future.delayed(const Duration(milliseconds: 100), () async {
      if (!mounted) return;
      Logger().info("⏱️ [round:$traceId] delayed fetch started");
      await _gamePlayModule?.roundInit(context, () {
        Logger().info("🧠 [round:$traceId] roundInit UI tick (isLoading=${_gamePlayModule?.isLoading})");
        setState(() {
          final q = _gamePlayModule?.question;
          _correctAnswer = q?['image_url'] as String?;
          if (q == null) {
            _gamePlayModule?.imageOptions = [];
            return;
          }
          final distractors =
              (q['distractor_images'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
          final mainUrl = q['image_url']?.toString() ?? '';
          _gamePlayModule?.imageOptions = [mainUrl, ...distractors];
          _gamePlayModule?.imageOptions.shuffle(Random());
        });
        Logger().info("✅ [round:$traceId] roundInit callback applied | correctAnswer=$_correctAnswer | optionsCount=${_gamePlayModule?.imageOptions.length}");
      });

      Logger().info("🔹 [round:$traceId] after round init question=${_gamePlayModule?.question}");

      Logger().info("⏳ [round:$traceId] invoking setTimer");
      _gamePlayModule?.setTimer(context, () {
        _handleAnswer("", timeUp: true);
      });

      Logger().info("✅ [round:$traceId] New game round initialized!");
    });
  }

  void _initializeGame() {
    final int traceId = DateTime.now().microsecondsSinceEpoch;
    _log.info("🚦 [round:$traceId] _initializeGame entered");
    if (_gamePlayModule == null) {
      Logger().error("❌ [round:$traceId] GamePlayModule is not initialized!");
      return; // ✅ Prevent crashing
    }

    Logger().info("🔄 [round:$traceId] Initializing new game round...");

    _helpUsed = false; // ✅ Reset Help button for new round

    final stateManager = Provider.of<StateManager>(context, listen: false);
    final gameRoundState = stateManager.getPluginState<Map<String, dynamic>>("game_round") ?? {};

    bool levelUp = gameRoundState["levelUp"] ?? false;
    bool endGame = gameRoundState["endGame"] ?? false;
    Logger().info("📦 [round:$traceId] game_round snapshot: $gameRoundState");

    if (levelUp || endGame) {
      Logger().info("🎉 [round:$traceId] Showing level progress modal | LevelUp: $levelUp | EndGame: $endGame");
      _showLevelProgressModal(traceId, isEndGame: endGame);
      return;
    }

    _startRoundFromScratch(traceId);
  }

  String? _correctAnswer; // ✅ Stores the correct answer dynamically

  void _handleAnswer(String selectedImage, {bool timeUp = false}) {

    /// ✅ Fetch Cached Image
    CachedNetworkImageProvider cachedImageProvider = CachedNetworkImageProvider(selectedImage);

// ✅ Pass context to checkAnswer
    _gamePlayModule?.checkAnswer(context, selectedImage, () {
      setState(() {
        _correctAnswer = selectedImage;
      });

      Logger().info("🔹 Correct answer $_correctAnswer");

      _updateFeedbackState(
        showFeedback: true,
        feedbackText: _gamePlayModule!.feedbackMessage,
        cachedImage: cachedImageProvider, // ✅ Pass Cached Image
        correctName: _gamePlayModule?.question?['actor'],
      );

      _loadLevelAndPoints();
    }, timeUp: timeUp);

  }

  /// ✅ Select a new random background
  void _setRandomBackground() {
    setState(() {
      _backgroundImage = MainHelperModule.getRandomBackground();
    });
    Logger().info("🎨 New Background: $_backgroundImage");
  }

  void _updateFeedbackState({required bool showFeedback, String feedbackText = "", CachedNetworkImageProvider? cachedImage, String correctName = ""}) {
    setState(() {
      _showFeedback = showFeedback;
      _feedbackText = feedbackText;
      _cachedSelectedImage = cachedImage; // ✅ Store Cached Image
      _correctName = correctName;
    });

    if (showFeedback) {
      _feedbackTimer?.cancel();
      _feedbackTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          _closeFeedback();
        }
      });
    }
  }

  void _closeFeedback() {
    _updateFeedbackState(showFeedback: false);
    _feedbackTimer?.cancel();

    setState(() {
      fadedImages.clear(); // ✅ Clear faded images
    });

    _initializeGame(); // ✅ Reset game and change background
  }

  @override
  Widget buildContent(BuildContext context) {
    return Stack(
      children: [
        // ✅ Background Image
        Positioned.fill(
          child: _backgroundImage.isNotEmpty
              ? Image.asset(_backgroundImage, fit: BoxFit.cover)
              : Container(color: Colors.black),
        ),

        SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ✅ Top bar with Level, TimerBar, and Points
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("⭐ Category Level: $_level",
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text("🏆 Points: $_points",
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Consumer<StateManager>(
                      builder: (context, stateManager, child) {
                        final timerState =
                            stateManager.getPluginState<Map<String, dynamic>>("game_timer") ?? {};
                        final isRunning = timerState["isRunning"] ?? false;
                        final duration = (timerState["duration"] ?? 0).toDouble();
                        final int currentLevel = _level > 0 ? _level : 1;
                        final double levelTimer =
                        (GamePlayConfig.levelTimers[currentLevel] ?? 10).toDouble();
                        return isRunning
                            ? Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: SizedBox(
                            width: double.infinity,
                            child: TimerBar(remainingTime: duration, totalDuration: levelTimer),
                          ),
                        )
                            : const SizedBox.shrink();
                      },
                    ),
                  ],
                ),
              ),

              GameImageGrid(
                imageOptions: _gamePlayModule?.imageOptions?.map((e) => e.toString()).toList() ?? [], // ✅ Prevent null
                onImageTap: _handleAnswer,
                fadedImages: fadedImages,
                onAllImagesLoaded: _onImagesLoaded, // ✅ Call when images are loaded
              ),


              const SizedBox(height: 20),

              // ✅ Help Button (Center-aligned)
              ElevatedButton(
                onPressed: _useHelp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                ),
                child: const Text("💡 Use Help", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),

              const SizedBox(height: 20),

              FactBox(
                facts: (_gamePlayModule?.question?['facts'] as List<dynamic>?)
                    ?.map((e) => e.toString())
                    .toList() ??
                    [], // ✅ Ensure facts is never null
                onFactsLoaded: _onFactsLoaded,
              ),

            ],
          ),
        ),

        // ✅ Full-Screen Feedback Overlay
        if (_showFeedback)
          Positioned.fill(
            child: FeedbackMessage(
              feedback: _feedbackText,
              onClose: _closeFeedback,
              cachedImage: _cachedSelectedImage,
              correctName: _correctName, // ✅ Pass Cached Image
            ),
          ),

        // ✅ Full-Screen Loading Overlay
        const ScreenOverlay(), // ✅ New External Component
      ],
    );
  }


}