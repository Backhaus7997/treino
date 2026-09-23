import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/moderation/moderation_guard.dart';
import '../../../l10n/app_l10n.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/presentation/widgets/terms_checkbox.dart';
import '../application/perfil_asegurado_provider.dart';
import '../application/profile_setup_notifier.dart';
import '../application/profile_setup_providers.dart';
import '../application/terms_consent_provider.dart';
import 'steps/step_1_username_avatar.dart';
import 'steps/step_2_born_at.dart';
import 'steps/step_3_gym.dart';
import 'steps/step_4_experience_gender.dart';
import 'steps/step_5_weight_height.dart';
import 'widgets/profile_setup_footer.dart';
import 'widgets/profile_setup_header.dart';

/// Shell del flow ProfileSetup. Renderiza header + PageView con los 5 steps +
/// footer con VOLVER + SIGUIENTE/EMPEZAR. El PageView se sincroniza con el
/// `currentStep` del notifier.
class ProfileSetupFlow extends ConsumerStatefulWidget {
  const ProfileSetupFlow({super.key});

  @override
  ConsumerState<ProfileSetupFlow> createState() => _ProfileSetupFlowState();
}

class _ProfileSetupFlowState extends ConsumerState<ProfileSetupFlow> {
  final _pageController = PageController();

  /// Hay una cancelación de cuenta en curso. Entre confirmar y terminar puede
  /// haber hasta 10 s de espera (el intento en vuelo) más la baja de la
  /// cuenta; un segundo «Cancelar cuenta» en ese rato dispararía otra baja, y
  /// si ésa fallaba, volvía a habilitar los reintentos con la primera todavía
  /// en curso.
  ///
  /// Mientras dure, la pantalla tampoco deja avanzar: un submit en el medio de
  /// la baja recrearía el perfil entre el barrido de los docs y el borrado de
  /// la cuenta de Auth, y quedaría huérfano.
  bool _cancelando = false;

  // No hardcoded `\n` — the header (maxLines: 2 + softWrap) wraps these for us,
  // so they stay correct under large OS text scaling and odd viewports (F4).
  static const List<String> _titles = [
    '¿CÓMO TE LLAMÁS?',
    '¿CUÁNDO NACISTE?',
    '¿DÓNDE ENTRENÁS?',
    'NIVEL DE EXPERIENCIA',
    'PESO Y ALTURA',
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _onPrimary() async {
    final state = ref.read(profileSetupNotifierProvider);
    final notifier = ref.read(profileSetupNotifierProvider.notifier);
    if (!state.isLastStep) {
      notifier.goNext();
      return;
    }

    // QA-AUTH-001 (issue #434): quien no tiene consentimiento registrado
    // —las altas con Google/Apple nunca pasaron por el checkbox de Register—
    // lo da acá. Mismo gate que register_screen: snackbar y NO se dispara el
    // submit. Si todavía no se sabe (`null`), se pide: ver
    // [termsConsentRequiredProvider].
    final needsTermsConsent = ref.read(termsConsentRequiredProvider) ?? true;
    if (needsTermsConsent && !state.termsAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Aceptá los Términos y la Política de Privacidad para continuar',
          ),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }

    // Submit final: persiste el draft a Firestore. NO navegamos a mano desde
    // acá. El redirect del router saca al atleta de /profile-setup en cuanto
    // userProfileProvider emite el displayName recién guardado: RouterRefreshNotifier
    // re-dispara authRedirect → onboarding-complete gate → /home (testeado en
    // router_redirect_test: "complete + /profile-setup → /home"). El viejo
    // `context.go('/home')` manual corría una carrera contra ese stream —
    // navegaba ANTES de que el snapshot actualizara, el gate rebotaba a
    // /profile-setup y recién después volvía a /home: flicker visible (audit F3).
    try {
      await notifier.submit();
      // QA-PRO-106 (issue #430): el upload del avatar es best-effort — si
      // falló, el perfil YA quedó guardado y el router navega a /home solo.
      // El aviso va por el ScaffoldMessenger root, así que sobrevive esa
      // navegación; sin esto la foto elegida se pierde en silencio.
      if (!mounted) return;
      if (ref.read(profileSetupNotifierProvider).avatarUploadFailed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No pudimos subir tu foto — reintentá desde Perfil.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      // El handle publico se persiste como `displayName`, asi que pasa por el
      // filtro de terminos vetados (`UserRepository.update`). `profileSetupSaveError`
      // invita a reintentar, y para un bloqueo eso es consejo falso: el mismo
      // handle va a fallar siempre. Peor aca que en cualquier otra pantalla —
      // es el onboarding, y el usuario todavia no entro a la app.
      final copy = e is ModerationBlockedException
          ? AppL10n.of(context).moderationBlockedMessage
          : AppL10n.of(context).profileSetupSaveError;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(copy),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _onBack() {
    ref.read(profileSetupNotifierProvider.notifier).goBack();
  }

  /// Hard-cancel the onboarding from step 0. Shows a confirmation dialog, and
  /// if confirmed, deletes the Firestore profile + Firebase Auth user and
  /// navigates to /welcome. On failure shows a SnackBar and keeps the user
  /// on the current step.
  Future<void> _onCancel() async {
    if (_cancelando) return;
    final palette = AppPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.bgCard,
        title: Text(AppL10n.of(context).profileSetupCancelDialogTitle),
        content: Text(
          AppL10n.of(context).profileSetupCancelDialogBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Volver al setup'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Cancelar cuenta',
              style: TextStyle(color: palette.highlight),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted || _cancelando) return;
    setState(() => _cancelando = true);

    // Frena los reintentos de `users/{uid}` ANTES de borrar la cuenta, y espera
    // al que ya esté en vuelo: un doc escrito después del borrado quedaría
    // huérfano, con el mail de alguien que pidió no tener cuenta. Ver
    // [altaCanceladaProvider] e [IntentoDelPerfil].
    final auth = ref.read(authNotifierProvider.notifier);
    final intento = ref.read(intentoDelPerfilProvider);
    ref.read(altaCanceladaProvider.notifier).state = true;
    await intento.esperar();
    try {
      await auth.cancelOnboarding();
      if (!mounted) return;
      context.go('/welcome');
    } catch (_) {
      if (!mounted) return;
      setState(() => _cancelando = false);
      // La cuenta sigue viva: los reintentos vuelven a correr.
      ref.read(altaCanceladaProvider.notifier).state = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppL10n.of(context).profileSetupCancelAccountError),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    // Sync PageView con currentStep cuando cambia.
    ref.listen<int>(
      profileSetupNotifierProvider.select(
        (ProfileSetupState s) => s.currentStep,
      ),
      (prev, next) {
        if (!_pageController.hasClients) return;
        _pageController.animateToPage(
          next,
          duration: AppMotion.resolve(context, AppMotion.slow),
          curve: AppMotion.standard,
        );
      },
    );

    final state = ref.watch(profileSetupNotifierProvider);
    // Sin consentimiento registrado, o todavía sin saberlo — ver _onPrimary.
    final needsTermsConsent = ref.watch(termsConsentRequiredProvider) ?? true;
    // Mientras dure el alta, reintenta crear `users/{uid}` si el login no lo
    // dejó. El resultado no se usa: watchearlo es lo que lo mantiene vivo.
    ref.watch(perfilAseguradoProvider);

    return Scaffold(
      backgroundColor: palette.bg,
      body: MediaQuery(
        // Clamp OS text scaling: huge accessibility settings would otherwise
        // grow the fixed header into the PageView body and overflow (audit F4).
        data: MediaQuery.of(context).copyWith(
          textScaler: MediaQuery.textScalerOf(context).clamp(
            minScaleFactor: 1.0,
            maxScaleFactor: 1.3,
          ),
        ),
        child: AppBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                children: [
                  // Cancel-onboarding affordance — only visible on step 0.
                  // Tapping triggers a confirmation dialog; on confirm, the
                  // Firebase Auth user and Firestore profile are deleted and
                  // the user lands back on /welcome (REQ: hard cancel).
                  if (state.currentStep == 0) ...[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        key: const Key('profile_setup_cancel_button'),
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          TreinoIcon.close,
                          color: palette.textPrimary,
                        ),
                        onPressed: _cancelando ? null : _onCancel,
                        tooltip: 'Cancelar creación de cuenta',
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  ProfileSetupHeader(
                    currentStep: state.currentStep,
                    title: _titles[state.currentStep],
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      children: const [
                        Step1UsernameAvatar(),
                        Step2BornAt(),
                        Step3Gym(),
                        Step4ExperienceGender(),
                        Step5WeightHeight(),
                      ],
                    ),
                  ),
                  // Terms checkbox — solo en el último step y solo sin
                  // consentimiento registrado (email ya aceptó en Register).
                  // QA-AUTH-001 (#434).
                  if (state.isLastStep && needsTermsConsent) ...[
                    const SizedBox(height: 12),
                    TermsCheckbox(
                      value: state.termsAccepted,
                      onChanged: ref
                          .read(profileSetupNotifierProvider.notifier)
                          .updateTermsAccepted,
                    ),
                  ],
                  const SizedBox(height: 12),
                  ProfileSetupFooter(
                    onBack: state.currentStep == 0 ? null : _onBack,
                    onPrimary:
                        state.canGoNext && !_cancelando ? _onPrimary : null,
                    primaryLabel: state.isLastStep ? 'EMPEZAR' : null,
                    primaryLoading: state.isSubmitting,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
