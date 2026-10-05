import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/features/coach_hub/application/hub_onboarding_controller.dart';
import 'package:treino/features/coach_hub/presentation/onboarding/onboarding_widgets.dart';
import 'package:treino/features/coach_hub/presentation/widgets/button/treino_button.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile_setup/domain/profile_setup_validators.dart';
import 'package:treino/features/profile_setup/presentation/widgets/born_at_field.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Abre el picker de fecha de nacimiento. Es [pickBornAt] salvo en los tests.
typedef ElegirFecha = Future<DateTime?> Function(
  BuildContext context,
  DateTime? actual,
);

/// Paso `age`: la fecha de nacimiento, con el mismo campo, el mismo picker y el
/// mismo validador (13 años) que el alta de mobile. Escribe SOLO `bornAt`.
class PasoEdad extends ConsumerStatefulWidget {
  const PasoEdad({super.key, this.elegirFecha = pickBornAt});

  final ElegirFecha elegirFecha;

  @override
  ConsumerState<PasoEdad> createState() => _PasoEdadState();
}

class _PasoEdadState extends ConsumerState<PasoEdad> {
  late DateTime? _fecha = ref.read(userProfileProvider).valueOrNull?.bornAt;
  String? _errorFecha;

  Future<void> _elegir() async {
    final elegida = await widget.elegirFecha(context, _fecha);
    if (elegida == null || !mounted) return;
    setState(() {
      _fecha = elegida;
      _errorFecha = null;
    });
  }

  Future<void> _continuar() async {
    final error = ProfileSetupValidators.validateBornAt(_fecha);
    if (error != null) {
      setState(() => _errorFecha = error);
      return;
    }
    await ref.read(hubOnboardingControllerProvider.notifier).guardarEdad(
          _fecha!,
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final escritura = ref.watch(hubOnboardingControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnboardingEncabezado(
          titulo: l10n.coachHubOnboardingAgeTitle,
          cuerpo: l10n.coachHubOnboardingAgeBody,
        ),
        const SizedBox(height: AppSpacing.s20),
        OnboardingEtiqueta(l10n.coachHubOnboardingAgeLabel),
        const SizedBox(height: AppSpacing.s8),
        BornAtField(
          value: _fecha,
          onTap: _elegir,
          errorText: _errorFecha,
        ),
        if (escritura.hasError) ...[
          const SizedBox(height: AppSpacing.s12),
          OnboardingError(
            mensajeDeErrorDeEscritura(l10n, escritura.error!),
          ),
        ],
        const SizedBox(height: AppSpacing.s20),
        TreinoButton(
          label: l10n.coachHubOnboardingContinue,
          expand: true,
          loading: escritura.isLoading,
          onPressed: escritura.isLoading ? null : _continuar,
        ),
      ],
    );
  }
}
