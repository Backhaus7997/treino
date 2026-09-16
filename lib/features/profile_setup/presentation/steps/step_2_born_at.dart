import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/motion/treino_tappable.dart';
import '../../application/profile_setup_notifier.dart';
import '../../application/profile_setup_providers.dart';
import '../../domain/profile_setup_validators.dart';

/// Step 2: fecha de nacimiento — el gate de edad mínima de la cuenta.
///
/// Va SEGUNDO y no último a propósito: si alguien no llega a la edad mínima se
/// tiene que enterar antes de entregar gimnasio, experiencia, género, peso y
/// altura. Hacerlo abandonar en el último paso, después de haber cargado sus
/// medidas corporales, es exactamente lo contrario de minimizar datos.
class Step2BornAt extends ConsumerWidget {
  const Step2BornAt({super.key});

  /// Edad con la que abre el picker. Arrancar en el año en curso obligaría a
  /// scrollear dos décadas a mano en el caso típico.
  static const int _initialAgeGuess = 25;

  /// Año más viejo ofrecido. Mismo piso que el editor de perfil.
  static const int _firstYear = 1920;

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref,
    DateTime? current,
  ) async {
    // El notifier se lee ANTES del await: después del picker este widget pudo
    // haberse desmontado y `ref` ya no es seguro.
    final notifier = ref.read(profileSetupNotifierProvider.notifier);
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime(now.year - _initialAgeGuess, 1, 1),
      firstDate: DateTime(_firstYear),
      // `lastDate: now` y NO "hoy menos 16 años". Un picker que directamente no
      // ofrece los últimos 16 años deja al usuario buscando una fecha real que
      // no está, sin ninguna pista de por qué. Preferimos que la pueda elegir y
      // que el validador le diga en castellano qué pasa.
      lastDate: now,
      helpText: 'Fecha de nacimiento',
    );
    if (picked == null) return;
    notifier.updateBornAt(
      // Fecha-only UTC — misma forma con la que la persiste el editor de perfil
      // (`_pickBornAt` en profile_edit_personal_screen.dart), así que el campo
      // tiene una sola representación en toda la app.
      DateTime.utc(picked.year, picked.month, picked.day),
    );
  }

  static String _format(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final bornAt = ref.watch(
      profileSetupNotifierProvider.select(
        (ProfileSetupState s) => s.draft.bornAt,
      ),
    );
    // Sólo mostramos error cuando YA eligió algo: un rojo antes del primer tap
    // es ruido, y el botón SIGUIENTE ya está deshabilitado mientras sea null.
    final error =
        bornAt == null ? null : ProfileSetupValidators.validateBornAt(bornAt);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            'FECHA DE NACIMIENTO',
            style: GoogleFonts.barlowCondensed(
              color: palette.textMuted,
              fontSize: AppTextSize.caption,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          TreinoTappable(
            key: const Key('profile_setup_born_at_field'),
            onTap: () => _pick(context, ref, bornAt),
            child: Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: palette.bgCard,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: error != null
                      ? palette.highlight
                      : palette.textMuted.withValues(alpha: 0.2),
                ),
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                bornAt == null ? 'DD/MM/AAAA' : _format(bornAt),
                style: GoogleFonts.barlow(
                  color:
                      bornAt == null ? palette.textMuted : palette.textPrimary,
                  fontSize: AppTextSize.body,
                ),
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error,
              key: const Key('profile_setup_born_at_error'),
              style: GoogleFonts.barlow(
                color: palette.highlight,
                fontSize: AppTextSize.caption,
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            'La usamos para verificar la edad mínima de la cuenta. No se '
            'muestra en tu perfil.',
            style: GoogleFonts.barlow(
              color: palette.textMuted,
              fontSize: AppTextSize.caption,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
