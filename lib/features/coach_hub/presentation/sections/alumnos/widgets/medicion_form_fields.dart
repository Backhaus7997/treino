import 'package:flutter/material.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_tappable.dart';
import 'package:treino/core/widgets/treino_icon.dart';

/// Sección colapsable de un form de mediciones/rendimiento — Fase 3 WU-06a.
///
/// Extraído de `_NuevaMedicionSection` (`alumno_detail_screen.dart`,
/// ADR-A3-04). Reusado por `MedicionDialog` y `RendimientoDialog` — ambos
/// formularios comparten la misma anatomía de secciones colapsables con
/// campos numéricos opcionales.
class MedicionFormSection extends StatelessWidget {
  const MedicionFormSection({
    super.key,
    required this.title,
    required this.palette,
    required this.expanded,
    required this.onToggle,
    required this.children,
  });

  /// Título CAPS de la sección (ej. "COMPOSICIÓN CORPORAL").
  final String title;
  final AppPalette palette;

  /// `true` = sección visible. Si [onToggle] es null, siempre expandida.
  final bool expanded;

  /// Null = sección estática (no colapsable, ej. composición corporal).
  final VoidCallback? onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final header = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
      child: Row(
        children: [
          if (onToggle != null)
            Icon(
              expanded ? TreinoIcon.chevronDown : TreinoIcon.chevronRight,
              size: 18,
              color: palette.textMuted,
            ),
          if (onToggle != null) const SizedBox(width: AppSpacing.hairline),
          Text(
            title,
            style: TextStyle(
              fontFamily: AppFonts.barlowCondensed,
              color: palette.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onToggle != null)
          TreinoTappable(onTap: onToggle, child: header)
        else
          header,
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.hairline),
            // Wrap en vez de grid fija: con el maxWidth 480 de TreinoDialog
            // termina en 1 columna, con dialogs más anchos (fuera del kit)
            // aprovecharía 2.
            child: Wrap(
              spacing: AppSpacing.s12,
              runSpacing: AppSpacing.s8,
              children: [
                for (final c in children)
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 240),
                    child: SizedBox(width: 270, child: c),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Campo numérico opcional del form de mediciones/rendimiento — acepta coma
/// o punto como decimal. Extraído de `_NuevaMedicionField`
/// (`alumno_detail_screen.dart`, ADR-A3-04).
class MedicionFormField extends StatelessWidget {
  const MedicionFormField({
    super.key,
    required this.label,
    required this.suffix,
    required this.controller,
    required this.palette,
  });

  final String label;
  final String suffix;
  final TextEditingController controller;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: TextStyle(color: palette.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: palette.textMuted, fontSize: 12),
          suffix: Text(
            suffix,
            style: TextStyle(color: palette.textMuted, fontSize: 11),
          ),
          isDense: true,
          filled: true,
          fillColor: palette.bgCard,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s8,
            vertical: AppSpacing.s8,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide(color: palette.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide(color: palette.accent, width: 1.5),
          ),
        ),
        validator: (v) {
          final s = v?.trim().replaceAll(',', '.') ?? '';
          if (s.isEmpty) return null; // opcional
          final parsed = double.tryParse(s);
          if (parsed == null) return 'Número inválido'; // i18n: Fase W2
          if (parsed < 0 || parsed > 500) {
            return 'Fuera de rango'; // i18n: Fase W2
          }
          return null;
        },
      ),
    );
  }
}
