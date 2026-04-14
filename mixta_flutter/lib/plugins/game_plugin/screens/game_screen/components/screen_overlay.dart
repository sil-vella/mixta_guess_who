import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../../core/managers/state_manager.dart';

class ScreenOverlay extends StatelessWidget {
  const ScreenOverlay({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<StateManager>(
      builder: (context, stateManager, child) {
        final gameRoundState = stateManager.getPluginState<Map<String, dynamic>>("game_round") ?? {};
        final bool isOverlayVisible = !(gameRoundState["imagesLoaded"] == true && gameRoundState["factLoaded"] == true);

        if (!isOverlayVisible) return const SizedBox.shrink(); // ✅ No overlay needed

        return Container(
          color: Colors.black.withOpacity(0.6), // ✅ Semi-transparent black overlay
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 20),
              Text(
                "Loading...",
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        );
      },
    );
  }
}
