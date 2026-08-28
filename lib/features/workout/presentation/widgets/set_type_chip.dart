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
          // 44 de ancho, no los 34 del handoff: 34 bajaba el área táctil de
          // 1936 a 1632 px² sobre un control que se toca en cada set. Los 10 px
          // extra salen del ancho de los campos —a 320 px de pantalla quedan
          // en 101 en vez de 106, imperceptible— y el mínimo táctil se conserva.
          //
          // minHeight en vez de height fijo: con Dynamic Type grande el número
          // del set crece, y un alto rígido lo recorta.
          constraints: const BoxConstraints(minWidth: 44, minHeight: 48),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: border),
          ),
          // Center con factores en 1 en vez de `alignment: center` en el
          // Container: `alignment` mete un Align, y un Align con constraints
          // acotadas se estira a llenarlas — el chip se comía el alto entero
          // de la fila. Con los factores, envuelve al texto y el mínimo de
          // 44×48 lo pone `constraints`.
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
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
      ),
    );
  }
}
