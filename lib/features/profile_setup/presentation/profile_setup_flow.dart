import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_palette.dart';
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
    if (state.isLastStep) {
      // Submit final — stub hasta Etapa 3 (UserRepository).
      // TODO(etapa3): cuando UserRepository exista, llamar
      // `notifier.submit()` que mapea el draft a UserProfile y lo
      // persiste en Firestore + uploadea avatar a Storage.
      await notifier.submit();
      if (mounted) context.go('/home');
      return;
    }
    notifier.goNext();
  }

  void _onBack() {
    ref.read(profileSetupNotifierProvider.notifier).goBack();
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
