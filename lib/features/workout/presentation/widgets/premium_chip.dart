import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';

/// Candado de la grilla PLANTILLAS — marca una plantilla del catálogo que el
/// alumno **no** puede usar con su plan actual (paywall del alumno suelto,
/// `docs/paywall-alumno-suelto.md` §4.1.1).
///
/// Mismo molde visual que [CoachChip] a propósito: la grilla ya enseñó que una
/// píldora arriba de la card significa «algo que saber sobre esta plantilla».
/// Cambia el color y suma el ícono, no el lenguaje.
///
/// Va en `textMuted` y no en `highlight`: el candado informa, no vende. Un
/// badge que grita compite por atención con las plantillas que el alumno SÍ
/// puede usar, que son las que queremos que toque primero.
///
/// **Sólo se dibuja cuando la plantilla está realmente bloqueada para quien
/// mira** — nunca sobre una que el alumno puede abrir. Un candado que se abre
/// al tocarlo es una mentira, y encima entrena a ignorar los candados.
class PremiumChip extends StatelessWidget {
  const PremiumChip({required this.routineId, super.key});

  final String routineId;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = palette.textMuted;
    return Container(
      key: Key('routine_premium_chip_$routineId'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(TreinoIcon.lock, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            AppL10n.of(context).workoutPlantillasPremiumChip,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 1.2,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
