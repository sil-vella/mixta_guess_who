import 'package:flutter/material.dart';
import '../../../../../utils/consts/theme_consts.dart';

class FactBox extends StatefulWidget {
  final List<String>? facts;
  final VoidCallback onFactsLoaded; // ✅ Callback when facts are loaded

  const FactBox({
    Key? key,
    required this.facts,
    required this.onFactsLoaded, // ✅ Passed from parent
  }) : super(key: key);

  @override
  _FactBoxState createState() => _FactBoxState();
}

class _FactBoxState extends State<FactBox> {
  final ScrollController _scrollController = ScrollController(); // ✅ Scroll controller

  @override
  void dispose() {
    _scrollController.dispose(); // ✅ Dispose ScrollController
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FactBox oldWidget) {
    super.didUpdateWidget(oldWidget);

    // ✅ Trigger callback only when new facts are received
    if (widget.facts != null && widget.facts!.isNotEmpty && oldWidget.facts != widget.facts) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onFactsLoaded();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12.0),
      margin: const EdgeInsets.symmetric(horizontal: 16.0),
      decoration: BoxDecoration(
        color: AppColors.accentColor, // ✅ Gold Background
        borderRadius: BorderRadius.circular(10.0),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.4, // ✅ Limit height to 40% of screen
        ),
        child: widget.facts != null && widget.facts!.isNotEmpty
            ? Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: ListView.builder(
            controller: _scrollController,
            shrinkWrap: true,
            physics: const BouncingScrollPhysics(),
            itemCount: widget.facts!.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Text(
                  "- ${widget.facts![index]}",
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              );
            },
          ),
        )
            : const Center(
          child: Text(
            "No facts available",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}
