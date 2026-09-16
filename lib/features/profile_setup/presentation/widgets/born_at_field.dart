import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/motion/treino_tappable.dart';

/// Edad con la que abre el picker. Arrancar en el año en curso obligaría a
/// scrollear dos décadas a mano en el caso típico.
const int _kInitialAgeGuess = 25;

/// Año más viejo ofrecido. Mismo piso que el editor de perfil.
const int _kFirstYear = 1920;

/// Abre el date picker de fecha de nacimiento y devuelve lo elegido, ya
/// normalizado a **fecha-only UTC**. `null` si el usuario canceló.
///
/// Compartido por el paso 2 del alta y por el gate de cuentas existentes: si
/// cada uno armara su propio `showDatePicker`, los límites del calendario
/// podrían divergir sin que ningún test lo note — y un rango distinto en cada
/// superficie significa que la misma persona puede o no cargar su fecha real
/// según por dónde entró.
Future<DateTime?> pickBornAt(BuildContext context, DateTime? current) async {
  final now = DateTime.now();
  final picked = await showDatePicker(
    context: context,
    initialDate: current ?? DateTime(now.year - _kInitialAgeGuess, 1, 1),
    firstDate: DateTime(_kFirstYear),
    // `lastDate: now` y NO "hoy menos la edad mínima". Un picker que
    // directamente no ofrece los últimos años deja al usuario buscando una
    // fecha real que no está, sin ninguna pista de por qué. Preferimos que la
    // pueda elegir y que el validador le diga en castellano qué pasa.
    lastDate: now,
    helpText: 'Fecha de nacimiento', // i18n: Fase 6 Etapa 3
  );
  if (picked == null) return null;
  // Misma forma con la que la persiste el editor de perfil (`_pickBornAt` en
  // profile_edit_personal_screen.dart), así que el campo tiene UNA sola
  // representación en toda la app.
  return DateTime.utc(picked.year, picked.month, picked.day);
}

/// Campo tappable que imita el estilo de un input de texto: muestra la fecha
/// formateada, o el hint en muted cuando está vacío, y pinta el borde en
/// `highlight` cuando [errorText] no es null.
///
/// Compartido por `Step2BornAt` (alta) y `BirthDateGateScreen` (cuentas
/// existentes) por el mismo motivo que [pickBornAt]: dos superficies que piden
/// el MISMO dato tienen que verse igual.
class BornAtField extends StatelessWidget {
  const BornAtField({
    super.key,
    required this.value,
    required this.onTap,
    this.errorText,
  });

  final DateTime? value;
  final VoidCallback onTap;

  /// Mensaje de error a mostrar debajo. `null` = sin error.
  final String? errorText;

  static String formatDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final hasError = errorText != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TreinoTappable(
          onTap: onTap,
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: palette.bgCard,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(
                color: hasError
                    ? palette.highlight
                    : palette.textMuted.withValues(alpha: 0.2),
              ),
            ),
            alignment: Alignment.centerLeft,
            child: Text(
              value == null ? 'DD/MM/AAAA' : formatDate(value!),
              style: GoogleFonts.barlow(
                color: value == null ? palette.textMuted : palette.textPrimary,
                fontSize: AppTextSize.body,
              ),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 8),
          Text(
            errorText!,
            style: GoogleFonts.barlow(
              color: palette.highlight,
              fontSize: AppTextSize.caption,
            ),
          ),
        ],
      ],
    );
  }
}
