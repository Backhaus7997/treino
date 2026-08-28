import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/tokens/tokens.dart';
import '../../domain/set_enums.dart';

/// Compact set-type affordance used at the start of each routine set row.
class SetTypeChip extends StatelessWidget {
  const SetTypeChip({
    super.key,
    required this.label,
    required this.type,
    required this.palette,
    required this.semanticsLabel,
    required this.onTap,
  });

  final String label;
  final SetType type;
  final AppPalette palette;
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = switch (type) {
      SetType.warmup => palette.accent.withAlpha(40),
      SetType.drop => palette.highlight.withAlpha(40),
      SetType.failure => palette.danger.withAlpha(40),
      SetType.normal => palette.surfaceSubtle,
    };
    final foreground = switch (type) {
      SetType.warmup => palette.accentText,
      SetType.drop => palette.highlight,
      SetType.failure => palette.danger,
      SetType.normal => palette.textPrimary,
    };
    final border = switch (type) {
      SetType.warmup => palette.accent.withAlpha(100),
      SetType.drop => palette.highlight.withAlpha(100),
      SetType.failure => palette.danger.withAlpha(100),
      SetType.normal => palette.border,
    };

    return Semantics(
      button: true,
      label: semanticsLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 34,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: border),
          ),
          child: Text(
            label,
            style: GoogleFonts.barlowCondensed(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}
