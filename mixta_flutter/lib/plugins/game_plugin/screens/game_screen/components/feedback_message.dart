import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import '../../../../../core/managers/module_manager.dart';
import '../../../../../utils/consts/theme_consts.dart';

class FeedbackMessage extends StatefulWidget {
  final String feedback;
  final String correctName;
  final VoidCallback onClose;
  final String? selectedImageUrl;
  final CachedNetworkImageProvider? cachedImage; // ✅ Add Cached Image Provider


  const FeedbackMessage({
    Key? key,
    required this.feedback,
    required this.correctName,
    required this.onClose,
    this.selectedImageUrl,
    this.cachedImage,

  }) : super(key: key);

  @override
  _FeedbackMessageState createState() => _FeedbackMessageState();
}

class _FeedbackMessageState extends State<FeedbackMessage> {
  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 2));

    if (widget.feedback.contains("Correct")) {
      _confettiController.play();
    }
  }

  String _formatCorrectName(String name) {
    return name
        .replaceAll("_", " ") // ✅ Replace underscores with spaces
        .split(" ") // ✅ Split into words
        .map((word) => word.isNotEmpty ? word[0].toUpperCase() + word.substring(1).toLowerCase() : "") // ✅ Capitalize first letter of each word
        .join(" "); // ✅ Join words back into a single string
  }


  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  @override
  @override
  Widget build(BuildContext context) {
    bool isCorrect = widget.feedback.contains("Correct");

    return Stack(
      alignment: Alignment.center,
      children: [
        // ✅ Background Overlay
        Container(
          color: Colors.black.withOpacity(0.8),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ✅ Display Selected Image ONLY IF Answer is Correct
              if (isCorrect && widget.cachedImage != null) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Image(
                    image: widget.cachedImage!,
                    height: 120,
                    width: 120,
                    fit: BoxFit.cover,
                  ),
                ),
                // ✅ Display Correct Name Under the Image
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    _formatCorrectName(widget.correctName),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],

              // ✅ Feedback text
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Text(
                  widget.feedback,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isCorrect ? AppColors.accentColor : Colors.redAccent,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ✅ Close Button
              ElevatedButton(
                onPressed: widget.onClose,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accentColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                ),
                child: const Text("Close", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),

        // ✅ Confetti Animation (Only if Correct)
        if (isCorrect)
          Positioned(
            top: MediaQuery.of(context).size.height * 0.20, // ✅ 1/4 from the top
            left: 0,
            right: 0,  // ✅ Ensures full width for centering
            child: Align(
              alignment: Alignment.topCenter,  // ✅ Center it horizontally
              child: ConfettiWidget(
                confettiController: _confettiController,
                blastDirectionality: BlastDirectionality.explosive,
                emissionFrequency: 0.15,
                numberOfParticles: 15,
                maxBlastForce: 20,
                minBlastForce: 10,
                gravity: 0.1,
              ),
            ),
          ),
      ],
    );
  }

}
