import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';

/// Compact, read-only summary of an exercise prescription.
///
/// Formatting stays with the caller because the values come from the editor's
/// private set model. This widget only owns the visual treatment.
class PrescriptionChips extends StatelessWidget {
  const PrescriptionChips({
    required this.prescription,
    this.rest,
    this.hasError = false,
    super.key,
  });

  final String prescription;
  final String? rest;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = hasError ? palette.danger : palette.textMuted;
    final style = GoogleFonts.barlow(
      color: color,
      fontSize: 11.5,
      height: 1.2,
      fontWeight: FontWeight.w400,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            prescription,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (rest != null) ...[
          Text(' · ', style: style),
          Icon(TreinoIcon.timer, size: 12, color: color),
          const SizedBox(width: AppSpacing.hairline),
          Text(rest!, style: style),
        ],
      ],
    );
  }
}
