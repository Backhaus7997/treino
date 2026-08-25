import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/motion/treino_tappable.dart';
import '../../../../l10n/app_l10n.dart';
import '../../domain/check_in.dart';
import '../wellbeing_check_in_sheet.dart' show feelingLabel;

/// Piezas compartidas por los DOS puntos de captura del check-in: el resumen
/// post-entreno y la tarjeta diaria de Inicio.
///
/// Viven acá y no duplicadas en cada pantalla por el glifo: [WellbeingMoodGlyph]
/// carga el arreglo de #456 (el fallback explícito a la fuente de emoji y el
/// FittedBox que hace escalar en vez de desbordar). Duplicarlo garantizaba que
/// el próximo que lo tocara arreglara una copia sola.

/// Un emoji de la escala, tappable.
class WellbeingMoodEmoji extends StatelessWidget {
  const WellbeingMoodEmoji({
    super.key,
    required this.feeling,
    required this.onTap,
  });

  final CheckInFeeling feeling;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: feelingLabel(AppL10n.of(context), feeling),
      child: TreinoTappable(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: WellbeingMoodGlyph(feeling.emoji),
        ),
      ),
    );
  }
}

/// FittedBox por glifo: cuando un emoji mide más ancho de lo esperado (tofu
/// .notdef, font scale grande) la fila escala en vez de desbordar (#456).
class WellbeingMoodGlyph extends StatelessWidget {
  const WellbeingMoodGlyph(this.emoji, {super.key, this.fontSize = 28});

  final String emoji;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          emoji,
          // #456: on the iOS simulator (iPhone 16e / iOS 26.3) these glyphs can
          // render as tofu "?" — the theme's Barlow families carry no emoji and
          // the automatic platform fallback doesn't kick in there (likely an
          // engine/Impeller simulator issue). The explicit fallback pins the
          // system emoji font; physical-device verification is still pending.
          style: TextStyle(
            fontSize: fontSize,
            fontFamilyFallback: const ['Apple Color Emoji'],
          ),
        ),
      ),
    );
  }
}

/// La fila de los 5 niveles. Tocar uno abre el sheet ya precargado con él, así
/// el tap no se pierde y registrar cuesta dos toques.
class WellbeingMoodScale extends StatelessWidget {
  const WellbeingMoodScale({super.key, required this.onSelect});

  final ValueChanged<CheckInFeeling> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final feeling in CheckInFeeling.displayOrder)
          Flexible(
            child: WellbeingMoodEmoji(
              feeling: feeling,
              onTap: () => onSelect(feeling),
            ),
          ),
      ],
    );
  }
}

/// Estado "ya registrado": el registro existe y el sheet abre precargado para
/// editarlo, sobre el MISMO documento.
class WellbeingCheckInRecorded extends StatelessWidget {
  const WellbeingCheckInRecorded({
    super.key,
    required this.checkIn,
    required this.onEdit,
  });

  final CheckIn checkIn;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
            child: WellbeingMoodGlyph(checkIn.feeling.emoji, fontSize: 24)),
        const SizedBox(width: 8),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              l10n.wellbeingSavedLabel,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: palette.accent,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
        TextButton(
          onPressed: onEdit,
          child: Text(
            l10n.wellbeingEditButton,
            style: GoogleFonts.barlow(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: palette.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}
