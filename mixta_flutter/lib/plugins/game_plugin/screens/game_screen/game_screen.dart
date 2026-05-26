import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:confetti/confetti.dart';
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
import '../../../../utils/navigation_utils.dart';
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

    // ✅ Ensure `round_timer` is only registered if it doesn't exist
    _roundTimer = _servicesManager.getService<TickerTimer>('round_timer');
    _log.info("🎯 initState services/modules loaded | hasSharedPref=${_sharedPref != null} | hasGamePlayModule=${_gamePlayModule != null} | hasRoundTimer=${_roundTimer != null}");

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

  /// Resume round timer after help (same timing as the old post-ad-dismiss path).
  void _resumeRoundTimerAfterHelp(TickerTimer? roundTimer) {
    _log.info("✅ Help flow finished. Attempting to resume timer...");
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      if (roundTimer == null) {
        _log.error("❌ roundTimer instance is null after help!");
        return;
      }
      _log.info(
          "🔍 roundTimer instance exists. isPaused: ${roundTimer.isPaused}, isRunning: ${roundTimer.isRunning}");

      if (roundTimer.isPaused) {
        _log.info("▶ Resuming timer after help...");
        roundTimer.startTimer();
      } else {
        _log.error("❌ roundTimer is NOT paused. Cannot resume.");
      }
    });
  }

  void _useHelp() {
    _log.info("⏳ Entering _useHelp...");

    if (_helpUsed) {
      _log.info("🚫 Help already used! Button disabled.");
      return; // ✅ Prevent multiple uses
    }

    _helpUsed = true; // ✅ Mark help as used

    final TickerTimer? roundTimer = _servicesManager.getService<TickerTimer>('round_timer');

    if (roundTimer != null && roundTimer.isRunning) {
      _log.info("⏸ Pausing timer before help.");
      roundTimer.pauseTimer();
    }
    _stateManager.updatePluginState("game_round", {
      "hint": true,
    });

    _log.info("💡 Applying help (hint + fade) — rewarded ad path skipped.");
    _fadeOutIncorrectImage();
    _resumeRoundTimerAfterHelp(roundTimer);
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
          return _LevelProgressDialog(
            completedCategory: completedCategory,
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _stateManager.updatePluginState("game_round", {
                "levelUp": false,
                "endGame": false,
              }, force: true);
              if (completedCategory) {
                NavigationUtils.navigateReset(context, '/preferences');
              } else {
                _loadLevelAndPoints();
                _startRoundFromScratch(traceId);
              }
            },
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
      _lastSelectionCorrect = null;
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
  bool? _lastSelectionCorrect;

  void _handleAnswer(String selectedImage, {bool timeUp = false}) {

    /// ✅ Fetch Cached Image
    CachedNetworkImageProvider cachedImageProvider = CachedNetworkImageProvider(selectedImage);

// ✅ Pass context to checkAnswer
    _gamePlayModule?.checkAnswer(context, selectedImage, () {
      final isCorrect = _gamePlayModule!.feedbackMessage.contains('Correct');
      setState(() {
        _correctAnswer = selectedImage;
        _lastSelectionCorrect = isCorrect;
      });

      Logger().info("🔹 Answer result: correct=$isCorrect | selected=$_correctAnswer");

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

  Widget? _buildRoundLoadError() {
    final module = _gamePlayModule;
    if (module == null || module.isLoading || module.question != null) return null;
    final msg = module.feedbackMessage;
    if (msg.isEmpty) return null;

    return Padding(
      padding: AppPadding.defaultPadding,
      child: Material(
        color: AppColors.primaryColor,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: AppPadding.cardPadding,
          child: Text(
            msg.replaceFirst(RegExp(r'^❌\s*'), ''),
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.redAccent),
          ),
        ),
      ),
    );
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

        SafeArea(
          child: Column(
            children: [
              if (_buildRoundLoadError() != null) _buildRoundLoadError()!,
              Padding(
                padding: AppPadding.defaultPadding,
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "⭐ Category Level: $_level",
                          style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          "🏆 Points: $_points",
                          style: AppTextStyles.bodyLarge.copyWith(fontWeight: FontWeight.bold),
                        ),
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
                imageOptions: _gamePlayModule?.imageOptions?.map((e) => e.toString()).toList() ?? [],
                onImageTap: _handleAnswer,
                fadedImages: fadedImages,
                selectionCorrect: _lastSelectionCorrect,
                onAllImagesLoaded: _onImagesLoaded,
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              Expanded(
                child: FactBox(
                  facts: (_gamePlayModule?.question?['facts'] as List<dynamic>?)
                          ?.map((e) => e.toString())
                          .toList() ??
                      [],
                  onFactsLoaded: _onFactsLoaded,
                ),
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

class _LevelProgressDialog extends StatefulWidget {
  final bool completedCategory;
  final VoidCallback onPressed;

  const _LevelProgressDialog({
    required this.completedCategory,
    required this.onPressed,
  });

  @override
  State<_LevelProgressDialog> createState() => _LevelProgressDialogState();
}

class _LevelProgressDialogState extends State<_LevelProgressDialog>
    with SingleTickerProviderStateMixin {
  late final ConfettiController _confettiController;
  late final AnimationController _scaleController;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 2));
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scaleAnim = CurvedAnimation(parent: _scaleController, curve: Curves.easeOutBack);
    _scaleController.forward();
    _confettiController.play();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.completedCategory ? "🏆 Category Complete!" : "🎉 Level Up!";
    final body = widget.completedCategory
        ? "You finished every level in this category. Pick another category to keep playing."
        : "You guessed everyone on this level. Ready for the next challenge?";
    final button = widget.completedCategory ? "Back to profile" : "Continue";

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Stack(
        alignment: Alignment.center,
        children: [
          ScaleTransition(
            scale: _scaleAnim,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
              decoration: BoxDecoration(
                color: AppColors.primaryColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.accentColor.withOpacity(0.4), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.completedCategory ? Icons.emoji_events : Icons.auto_awesome,
                    size: 62,
                    color: AppColors.accentColor,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    title,
                    style: AppTextStyles.headingMedium(),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    body,
                    style: AppTextStyles.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton(
                    onPressed: widget.onPressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentColor,
                      foregroundColor: AppColors.white,
                      padding: AppPadding.cardPadding,
                    ),
                    child: Text(button, style: AppTextStyles.buttonText),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirectionality: BlastDirectionality.explosive,
                emissionFrequency: 0.08,
                numberOfParticles: 20,
                maxBlastForce: 16,
                minBlastForce: 8,
                gravity: 0.18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}