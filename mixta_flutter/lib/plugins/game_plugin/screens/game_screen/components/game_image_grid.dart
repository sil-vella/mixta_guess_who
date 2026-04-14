import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:mixta_guess_who/plugins/game_plugin/modules/function_helper_module/function_helper_module.dart';
import 'package:mixta_guess_who/utils/consts/theme_consts.dart';
import '../../../../../tools/logging/logger.dart';
import '../../../modules/game_play_module/game_play_module.dart';
import '../../../../../core/managers/module_manager.dart';

class GameImageGrid extends StatefulWidget {
  final List<String> imageOptions;
  final Function(String) onImageTap;
  final Function() onAllImagesLoaded;
  final Set<String> fadedImages;

  const GameImageGrid({
    Key? key,
    required this.imageOptions,
    required this.onImageTap,
    required this.onAllImagesLoaded,
    required this.fadedImages,
  }) : super(key: key);

  @override
  _GameImageGridState createState() => _GameImageGridState();
}

class _GameImageGridState extends State<GameImageGrid> {
  late List<bool> _isLoaded;
  int _loadedCount = 0;
  bool _callbackFired = false;
  FunctionHelperModule? _gameFunctionsHelper; // ✅ Retrieved from ModuleManager
  String? selectedImage;

  @override
  void initState() {
    super.initState();

    // ✅ Retrieve ModuleManager via Provider
    final moduleManager = Provider.of<ModuleManager>(context, listen: false);
    _gameFunctionsHelper = moduleManager.getLatestModule<FunctionHelperModule>();

    _resetLoadingState();
  }

  @override
  void didUpdateWidget(covariant GameImageGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.imageOptions != oldWidget.imageOptions) {
      _resetLoadingState();
    }
  }

  void _resetLoadingState() {
    setState(() {
      _isLoaded = List.generate(widget.imageOptions.length, (_) => false);
      _loadedCount = 0;
      _callbackFired = false;
      selectedImage = null; // ✅ Reset selection on new game round
    });
  }

  void _onImageLoaded(int index, String imageUrl) {
    if (mounted && !_isLoaded[index]) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        setState(() {
          _isLoaded[index] = true;
          _loadedCount++;

          Logger().info("📸 Image Loaded: $imageUrl [$_loadedCount/${widget.imageOptions.length}]");

          // ✅ Store timestamp using FunctionHelperModule
          _gameFunctionsHelper?.storeImageCacheTimestamp(context, imageUrl);

          if (_loadedCount >= widget.imageOptions.length && !_callbackFired) {
            _callbackFired = true;
            Logger().info("✅ ALL images processed. Triggering callback...");
            widget.onAllImagesLoaded();
          }
        });
      });
    }
  }

  void _handleImageTap(String imageUrl) {
    if (widget.fadedImages.contains(imageUrl)) return; // ✅ Ignore faded images

    setState(() {
      selectedImage = imageUrl; // ✅ Mark image as selected
      Logger().info("📸 Image tapped: $imageUrl | selectedImage now: $selectedImage");
    });

    // ✅ Wait 100ms before calling onImageTap to ensure UI updates first
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        setState(() {}); // ✅ Ensure UI refresh before calling logic
        widget.onImageTap(imageUrl);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    List<String> images = widget.imageOptions.take(4).toList();

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: images.take(2).map((image) => _buildImageBox(image)).toList(),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: images.skip(2).map((image) => _buildImageBox(image)).toList(),
        ),
      ],
    );
  }

  Widget _buildImageBox(String imageUrl) {
    bool isFaded = widget.fadedImages.contains(imageUrl);
    bool isSelected = selectedImage == imageUrl;

    Logger().info("📸 Checking if selected: $imageUrl -> ${isSelected ? "Selected" : "Not Selected"}");

    return GestureDetector(
      onTap: () => _handleImageTap(imageUrl),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: selectedImage == null ? 1.0 : (isSelected ? 1.0 : 0.05), // ✅ Start at 100%, fade to 5% after selection
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 150,
          height: 150,
          margin: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected
                  ? Colors.greenAccent // ✅ Selected image gets a green border
                  : (isFaded ? Colors.grey : AppColors.accentColor),
              width: isSelected ? 6.0 : (isFaded ? 2.5 : 3.0), // ✅ Thicker border for selected image
            ),
            borderRadius: BorderRadius.circular(8.0),
            boxShadow: isSelected
                ? [
              BoxShadow(
                color: Colors.greenAccent.withOpacity(0.8),
                blurRadius: 20,
                spreadRadius: 4,
              ),
            ]
                : [],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6.0),
            child: ColorFiltered(
              colorFilter: isFaded
                  ? ColorFilter.mode(Colors.grey.withOpacity(0.5), BlendMode.saturation)
                  : const ColorFilter.mode(Colors.transparent, BlendMode.multiply),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                errorWidget: (context, url, error) {
                  Logger().error("❌ Image failed to load: $imageUrl | Using fallback...");
                  _onImageLoaded(widget.imageOptions.indexOf(imageUrl), imageUrl);
                  return Image.asset(
                    'assets/images/icon.png',
                    fit: BoxFit.cover,
                  );
                },
                imageBuilder: (context, imageProvider) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _onImageLoaded(widget.imageOptions.indexOf(imageUrl), imageUrl);
                  });
                  return Image(image: imageProvider, fit: BoxFit.cover);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
