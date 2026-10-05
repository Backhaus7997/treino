import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/auth/presentation/widgets/auth_input.dart';
import 'package:treino/features/auth/presentation/widgets/terms_checkbox.dart';
import 'package:treino/features/coach_hub/application/hub_onboarding_controller.dart';
import 'package:treino/features/coach_hub/presentation/onboarding/onboarding_widgets.dart';
import 'package:treino/features/coach_hub/presentation/widgets/button/treino_button.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile_setup/application/terms_consent_provider.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Paso `identity`: nombre y apellido (sin `@handle`) y, si todavía no hay
/// evidencia de consentimiento, el checkbox de términos. Todo va en UNA
/// escritura (`guardarIdentidad`).
class PasoIdentidad extends ConsumerStatefulWidget {
  const PasoIdentidad({super.key});

  @override
  ConsumerState<PasoIdentidad> createState() => _PasoIdentidadState();
}

class _PasoIdentidadState extends ConsumerState<PasoIdentidad> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _nombre;
  late final TextEditingController _apellido;
  bool _acepto = false;

  @override
  void initState() {
    super.initState();
    final perfil = ref.read(userProfileProvider).valueOrNull;
    _nombre = TextEditingController(text: perfil?.firstName ?? '');
    _apellido = TextEditingController(text: perfil?.lastName ?? '');
  }

  @override
  void dispose() {
    _nombre.dispose();
    _apellido.dispose();
    super.dispose();
  }

  Future<void> _continuar(bool pideTerminos) async {
    if (!(_form.currentState?.validate() ?? false)) return;
    await ref.read(hubOnboardingControllerProvider.notifier).guardarIdentidad(
          nombre: _nombre.text,
          apellido: _apellido.text,
          aceptoTerminos: _acepto,
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final escritura = ref.watch(hubOnboardingControllerProvider);
    // `null` (todavía no se sabe) cuenta como «sí»: preguntar de más no le
    // cuesta nada a nadie; preguntar de menos es un alta sin consentimiento.
    final pideTerminos = ref.watch(termsConsentRequiredProvider) != false;
    final puedeContinuar = !escritura.isLoading && (!pideTerminos || _acepto);

    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OnboardingEncabezado(
            titulo: l10n.coachHubOnboardingIdentityTitle,
            cuerpo: l10n.coachHubOnboardingIdentityBody,
          ),
          const SizedBox(height: AppSpacing.s20),
          AuthInput(
            controller: _nombre,
            label: l10n.coachHubOnboardingFirstNameLabel,
            leadingIcon: TreinoIcon.tabProfile,
            autofillHints: const [AutofillHints.givenName],
            textInputAction: TextInputAction.next,
            validator: (v) => (v ?? '').trim().isEmpty
                ? l10n.coachHubOnboardingFirstNameRequired
                : null,
          ),
          const SizedBox(height: AppSpacing.s14),
          AuthInput(
            controller: _apellido,
            label: l10n.coachHubOnboardingLastNameLabel,
            leadingIcon: TreinoIcon.tabProfile,
            autofillHints: const [AutofillHints.familyName],
            textInputAction: TextInputAction.done,
            validator: (v) => (v ?? '').trim().isEmpty
                ? l10n.coachHubOnboardingLastNameRequired
                : null,
          ),
          if (pideTerminos) ...[
            const SizedBox(height: AppSpacing.s14),
            TermsCheckbox(
              value: _acepto,
              onChanged: (v) => setState(() => _acepto = v),
            ),
          ],
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
            onPressed: puedeContinuar ? () => _continuar(pideTerminos) : null,
          ),
        ],
      ),
    );
  }
}
