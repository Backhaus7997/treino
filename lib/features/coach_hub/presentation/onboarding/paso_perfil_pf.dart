import 'package:flutter/material.dart';
import 'package:treino/features/coach_hub/presentation/onboarding/onboarding_widgets.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Paso `pf`: PLACEHOLDER hasta el batch 8 (bio, especialidad, tarifa,
/// modalidad y ubicación). Solo dice qué falta; no escribe nada.
class PasoPerfilPf extends StatelessWidget {
  const PasoPerfilPf({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return OnboardingEncabezado(
      titulo: l10n.coachHubOnboardingPfTitle,
      cuerpo: l10n.coachHubOnboardingPfPlaceholder,
    );
  }
}
