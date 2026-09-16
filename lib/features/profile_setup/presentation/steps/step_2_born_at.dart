import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../application/profile_setup_notifier.dart';
import '../../application/profile_setup_providers.dart';
import '../../domain/profile_setup_validators.dart';
import '../widgets/born_at_field.dart';

/// Step 2: fecha de nacimiento — el gate de edad mínima de la cuenta.
///
/// Va SEGUNDO y no último a propósito: si alguien no llega a la edad mínima se
/// tiene que enterar antes de entregar gimnasio, experiencia, género, peso y
/// altura. Hacerlo abandonar en el último paso, después de haber cargado sus
/// medidas corporales, es exactamente lo contrario de minimizar datos.
class Step2BornAt extends ConsumerWidget {
  const Step2BornAt({super.key});

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
            'FECHA DE NACIMIENTO', // i18n: Fase 6 Etapa 3
            style: GoogleFonts.barlowCondensed(
              color: palette.textMuted,
              fontSize: AppTextSize.caption,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          BornAtField(
            key: const Key('profile_setup_born_at_field'),
            value: bornAt,
            errorText: error,
            onTap: () async {
              // El notifier se lee ANTES del await: después del picker este
              // widget pudo haberse desmontado y `ref` ya no es seguro.
              final notifier = ref.read(profileSetupNotifierProvider.notifier);
              final picked = await pickBornAt(context, bornAt);
              if (picked != null) notifier.updateBornAt(picked);
            },
          ),
          const SizedBox(height: 18),
          Text(
            'La usamos para verificar la edad mínima de la cuenta. No se '
            'muestra en tu perfil.', // i18n: Fase 6 Etapa 3
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
