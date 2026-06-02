import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';

/// Tappable 5-star rating input widget.
///
/// Accepts [rating] (0 = none selected, 1..5 = filled up to that index) and
/// fires [onRatingChanged] with the tapped star index (1-based).
///
/// Uses [TreinoIcon.starFill] / [TreinoIcon.starOutline] exclusively.
/// Colors via [AppPalette.of(context)] — no hex literals.
/// Spacing from scale: 8/12.
///
/// REQ-RV-WRITE-003. Fase 6 Etapa 7.
class StarRatingInput extends StatelessWidget {
  const StarRatingInput({
    super.key,
    required this.rating,
    required this.onRatingChanged,
  });

  /// Current rating value (0 = none, 1..5).
  final int rating;

  /// Called when the user taps a star. Argument is 1-based index.
  final ValueChanged<int> onRatingChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starIndex = index + 1; // 1-based
        final isFilled = starIndex <= rating;
        return GestureDetector(
          onTap: () => onRatingChanged(starIndex),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              isFilled ? TreinoIcon.starFill : TreinoIcon.starOutline,
              size: 28,
              color: isFilled ? palette.warning : palette.textMuted,
            ),
          ),
        );
      }),
    );
  }
}
