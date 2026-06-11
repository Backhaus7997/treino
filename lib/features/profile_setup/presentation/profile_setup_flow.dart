import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../auth/application/auth_providers.dart';
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

  static const List<String> _titles = [
    '¿CÓMO TE\nLLAMÁS?',
    '¿DÓNDE\nENTRENÁS?',
    'NIVEL DE\nEXPERIENCIA',
    'PESO Y\nALTURA',
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

    // Submit final: persiste el draft a Firestore. La navegación a /home la
    // resuelve el redirect del router en cuanto el stream de userProfileProvider
    // emite el perfil completo (ver authRedirect → onboarding-complete gate).
    // El `context.go('/home')` se mantiene como fast-path de intención; si el
    // stream todavía no actualizó, el redirect rebota a /profile-setup y la
    // misma regla nos lleva a /home apenas llega el snapshot.
    try {
      await notifier.submit();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pudimos guardar tu perfil. Probá de nuevo.'),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    if (mounted) context.go('/home');
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
        title: const Text('¿Cancelar la creación de tu cuenta?'),
        content: const Text(
          'Vamos a borrar tu cuenta. Esta acción no se puede deshacer.',
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
        const SnackBar(
          content: Text('No pudimos cancelar la cuenta. Probá de nuevo.'),
          duration: Duration(seconds: 3),
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
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      },
    );

    final state = ref.watch(profileSetupNotifierProvider);

    return Scaffold(
      backgroundColor: palette.bg,
      body: AppBackground(
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
    );
  }
}
