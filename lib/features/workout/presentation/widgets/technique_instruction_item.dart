import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';

/// Numbered technique cue — circle badge with gradient + instruction text.
/// Used in [ExerciseDetailScreen] to list technique instructions.
class TechniqueInstructionItem extends StatelessWidget {
  const TechniqueInstructionItem({
    super.key,
    required this.index,
    required this.text,
  });

  /// 1-based display index.
  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: palette.accent.withValues(alpha: 0.18),
            shape: BoxShape.circle,
            border: Border.all(
              color: palette.accent.withValues(alpha: 0.6),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            '$index',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: palette.accent,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w400,
              fontSize: 14,
              color: palette.textPrimary,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
