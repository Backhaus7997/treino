import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_background.dart';
import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../auth/presentation/widgets/auth_pill_button.dart';
import '../application/onboarding_providers.dart';
import '../domain/onboarding_surface.dart';
import 'widgets/onboarding_page.dart';

/// Tour de bienvenida del ALUMNO en mobile (issue #627, slice 1).
///
/// 4 pantallas full-screen, swipeables, con SALTAR visible desde la primera.
/// Se muestra una sola vez: el gate de `authRedirect` lo dispara cuando
/// `users/{uid}.onboardingSeen` todavía no tiene la versión actual de
/// [OnboardingSurface.athleteMobile].
///
/// Salidas (siempre hay una, lección de #429):
/// - SALTAR, desde cualquier página.
/// - EMPEZAR en la última.
/// - ACTIVAR RANKINGS en la última, que además aterriza en `/feed?tab=rankings`.
///
/// Las tres persisten el flag y navegan IGUAL aunque el write falle: el
/// escape hatch de sesión (`onboardingDismissedProvider`) lo garantiza, y el
/// usuario se entera por snackbar de que puede volver a verlo.
class AthleteOnboardingScreen extends ConsumerStatefulWidget {
  const AthleteOnboardingScreen({super.key});

  @override
  ConsumerState<AthleteOnboardingScreen> createState() =>
      _AthleteOnboardingScreenState();
}

class _AthleteOnboardingScreenState
    extends ConsumerState<AthleteOnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  static const int _totalPages = 4;
  static const _surface = OnboardingSurface.athleteMobile;

  bool _leaving = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _isLastPage => _currentPage == _totalPages - 1;

  void _onPrimary() {
    if (!_isLastPage) {
      _pageController.nextPage(
        duration: AppMotion.resolve(context, AppMotion.slow),
        curve: AppMotion.standard,
      );
      return;
    }
    _leave('/home');
  }

  /// Persiste el flag y sale a [destination]. Nunca queda a mitad de camino:
  /// si el write falla avisamos, pero navegamos igual.
  Future<void> _leave(String destination) async {
    if (_leaving) return;
    setState(() => _leaving = true);

    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    final saved =
        await ref.read(onboardingControllerProvider).markSeen(_surface);

    if (!saved) {
      // El messenger raíz sobrevive la navegación de abajo — sin eso el aviso
      // se iría con la pantalla (mismo criterio que QA-PRO-106 / #430).
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.onboardingSaveError),
          duration: const Duration(seconds: 4),
        ),
      );
    }
    router.go(destination);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    final pages = <Widget>[
      OnboardingPage(
        icon: TreinoIcon.tabWorkout,
        title: l10n.onboardingAthleteTrainTitle,
        body: l10n.onboardingAthleteTrainBody,
      ),
      OnboardingPage(
        icon: TreinoIcon.chartBar,
        title: l10n.onboardingAthleteProgressTitle,
        body: l10n.onboardingAthleteProgressBody,
      ),
      OnboardingPage(
        icon: TreinoIcon.tabCoach,
        title: l10n.onboardingAthleteCoachTitle,
        body: l10n.onboardingAthleteCoachBody,
      ),
      OnboardingPage(
        icon: TreinoIcon.ranking,
        title: l10n.onboardingAthleteCommunityTitle,
        body: l10n.onboardingAthleteCommunityBody,
        footer: OutlinedButton(
          key: const Key('onboarding_rankings_cta'),
          onPressed: _leaving ? null : () => _leave('/feed?tab=rankings'),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: palette.border),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
          child: Text(
            l10n.onboardingAthleteCommunityRankingsCta,
            style: GoogleFonts.barlow(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: palette.textPrimary,
            ),
          ),
        ),
      ),
    ];

    return Scaffold(
      backgroundColor: palette.bg,
      body: MediaQuery(
        // Mismo clamp que ProfileSetupFlow: con el escalado de texto del SO al
        // máximo, el header fijo se comería el PageView.
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        l10n.onboardingStepLabel(_currentPage + 1, _totalPages),
                        style: GoogleFonts.barlowCondensed(
                          color: palette.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        key: const Key('onboarding_skip_button'),
                        onPressed: _leaving ? null : () => _leave('/home'),
                        child: Text(
                          l10n.onboardingSkipCta,
                          style: GoogleFonts.barlow(
                            color: palette.textMuted,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ProgressSegments(
                    currentPage: _currentPage,
                    totalPages: _totalPages,
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: PageView(
                      key: const Key('onboarding_page_view'),
                      controller: _pageController,
                      onPageChanged: (i) => setState(() => _currentPage = i),
                      children: pages,
                    ),
                  ),
                  const SizedBox(height: 12),
                  AuthPillButton(
                    key: const Key('onboarding_primary_button'),
                    label: _isLastPage
                        ? l10n.onboardingFinishCta
                        : l10n.onboardingNextCta,
                    onPressed: _leaving ? null : _onPrimary,
                    isLoading: _leaving,
                    showArrow: false,
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

/// Barra de progreso segmentada — mismo lenguaje visual que
/// `ProfileSetupHeader`, así el tour se lee como continuación del setup.
class _ProgressSegments extends StatelessWidget {
  const _ProgressSegments({
    required this.currentPage,
    required this.totalPages,
  });

  final int currentPage;
  final int totalPages;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: List.generate(totalPages, (i) {
        final filled = i <= currentPage;
        return Expanded(
          child: AnimatedContainer(
            duration: AppMotion.resolve(context, AppMotion.fast),
            curve: AppMotion.standard,
            margin: EdgeInsets.only(right: i == totalPages - 1 ? 0 : 8),
            height: 4,
            decoration: BoxDecoration(
              color: filled ? palette.accent : palette.border,
              borderRadius: BorderRadius.circular(9999),
            ),
          ),
        );
      }),
    );
  }
}
