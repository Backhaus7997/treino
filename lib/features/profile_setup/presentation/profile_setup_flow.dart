import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_l10n.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/presentation/widgets/terms_checkbox.dart';
import '../../profile/application/user_providers.dart';
import '../application/profile_setup_notifier.dart';
import '../application/profile_setup_providers.dart';
import 'steps/step_1_username_avatar.dart';
import 'steps/step_2_gym.dart';
import 'steps/step_3_experience_gender.dart';
import 'steps/step_4_weight_height.dart';
import 'widgets/profile_setup_footer.dart';
import 'widgets/profile_setup_header.dart';

/// Shell del flow ProfileSetup. Renderiza header + PageView con los 4 steps +
/// footer con VOLVER + SIGUIENTE/EMPEZAR. El PageView se sincroniza con el
/// `currentStep` del notifier.
class ProfileSetupFlow extends ConsumerStatefulWidget {
  const ProfileSetupFlow({super.key});

  @override
  ConsumerState<ProfileSetupFlow> createState() => _ProfileSetupFlowState();
}

class _ProfileSetupFlowState extends ConsumerState<ProfileSetupFlow> {
  final _pageController = PageController();

  // No hardcoded `\n` — the header (maxLines: 2 + softWrap) wraps these for us,
  // so they stay correct under large OS text scaling and odd viewports (F4).
  static const List<String> _titles = [
    '¿CÓMO TE LLAMÁS?',
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

    // QA-AUTH-001 (issue #434): cuentas OAuth nuevas (Google/Apple) nunca
    // pasaron por el checkbox de Register. Mismo gate que register_screen —
    // mostramos el snackbar y NO disparamos submit. Email ya tiene perfil
    // (creado por signUpWithEmail) así que este gate no le aplica.
    final needsTermsConsent = ref.read(userProfileProvider).valueOrNull == null;
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
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppL10n.of(context).profileSetupSaveError),
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
    if (!mounted) return;

    try {
      await ref.read(authNotifierProvider.notifier).cancelOnboarding();
      if (!mounted) return;
      context.go('/welcome');
    } catch (_) {
      if (!mounted) return;
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
          duration: AppMotion.slow,
          curve: AppMotion.standard,
        );
      },
    );

    final state = ref.watch(profileSetupNotifierProvider);
    // OAuth nuevo (sin perfil aún) — ver comentario de _onPrimary.
    final needsTermsConsent =
        ref.watch(userProfileProvider).valueOrNull == null;

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
                        onPressed: _onCancel,
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
                        Step2Gym(),
                        Step3ExperienceGender(),
                        Step4WeightHeight(),
                      ],
                    ),
                  ),
                  // Terms checkbox — solo en el último step y solo para OAuth
                  // nuevo (email ya aceptó en Register). QA-AUTH-001 (#434).
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
                    onPrimary: state.canGoNext ? _onPrimary : null,
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
