import 'package:flutter/material.dart';
import '../../../../../utils/consts/theme_consts.dart';

class FactBox extends StatefulWidget {
  final List<String>? facts;
  final VoidCallback onFactsLoaded;

  const FactBox({
    Key? key,
    required this.facts,
    required this.onFactsLoaded,
  }) : super(key: key);

  @override
  _FactBoxState createState() => _FactBoxState();
}

class _FactBoxState extends State<FactBox> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _notifyFactsLoadedIfReady();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _notifyFactsLoadedIfReady() {
    if (widget.facts != null && widget.facts!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onFactsLoaded();
      });
    }
  }

  @override
  void didUpdateWidget(covariant FactBox oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.facts != null &&
        widget.facts!.isNotEmpty &&
        oldWidget.facts != widget.facts) {
      _scrollController.jumpTo(0);
      _notifyFactsLoadedIfReady();
    }
  }

  Future<void> _showAllFactsSheet() async {
    final facts = widget.facts;
    if (facts == null || facts.isEmpty || !mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.primaryColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        minChildSize: 0.35,
        maxChildSize: 0.9,
        builder: (context, sheetController) => Padding(
          padding: AppPadding.defaultPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Clues', style: AppTextStyles.headingMedium()),
              const SizedBox(height: 12),
              Expanded(
                child: Scrollbar(
                  controller: sheetController,
                  thumbVisibility: true,
                  child: ListView.builder(
                    controller: sheetController,
                    itemCount: facts.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        '- ${facts[index]}',
                        style: AppTextStyles.bodyLarge,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasFacts = widget.facts != null && widget.facts!.isNotEmpty;

    return Semantics(
      label: 'Game clues',
      identifier: 'game_description',
      child: Container(
        width: double.infinity,
        padding: AppPadding.cardPadding,
        margin: AppPadding.defaultPadding,
        decoration: BoxDecoration(
          color: AppColors.accentColor,
          borderRadius: BorderRadius.circular(10.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasFacts)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _showAllFactsSheet,
                  icon: const Icon(Icons.unfold_more, size: 18, color: AppColors.darkGray),
                  label: Text(
                    'Expand',
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.darkGray),
                  ),
                ),
              ),
            Expanded(
              child: hasFacts
                  ? Scrollbar(
                      controller: _scrollController,
                      thumbVisibility: true,
                      child: ListView.builder(
                        controller: _scrollController,
                        physics: const ClampingScrollPhysics(),
                        itemCount: widget.facts!.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Text(
                              '- ${widget.facts![index]}',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.bodyLarge.copyWith(
                                color: AppColors.darkGray,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  : Center(
                      child: Text(
                        'No facts available',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: AppColors.darkGray,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
