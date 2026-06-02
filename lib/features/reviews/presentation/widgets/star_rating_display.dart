import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';

/// Read-only 5-star rating display widget.
///
/// Shows 1..5 filled stars based on [rating], rounded to nearest whole star.
/// Null [rating] renders all outline stars (no data state).
/// Non-interactive — no GestureDetectors (contrast with StarRatingInput).
///
/// Uses [TreinoIcon.starFill] / [TreinoIcon.starOutline] exclusively.
/// Colors via [AppPalette.of(context)] — no hex literals.
/// Spacing from scale: 8.
///
/// REQ-RV-DISPLAY-001, REQ-RV-DISPLAY-003. Fase 6 Etapa 7.
class StarRatingDisplay extends StatelessWidget {
  const StarRatingDisplay({
    super.key,
    required this.rating,
    this.starSize = 14,
  });

  /// Average rating value (null = no reviews yet → all outline stars).
  final double? rating;

  /// Icon size in logical pixels. Defaults to 14 for compact display contexts.
  final double starSize;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // Round to nearest integer star count (e.g. 4.7 → 5 would be misleading,
    // so we floor: 4.7 → 4 filled stars, consistent with half-star-less UX).
    final filled = rating != null ? rating!.floor() : 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starIndex = index + 1; // 1-based
        final isFilled = starIndex <= filled;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Icon(
            isFilled ? TreinoIcon.starFill : TreinoIcon.starOutline,
            size: starSize,
            color: isFilled ? palette.warning : palette.textMuted,
          ),
        );
      }),
    );
  }
}
