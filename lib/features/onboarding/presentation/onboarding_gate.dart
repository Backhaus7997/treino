import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_l10n.dart';
import '../../profile/application/user_providers.dart';
import '../application/onboarding_providers.dart';
import '../../profile/domain/user_role.dart';
import 'onboarding_flow.dart';
import 'athlete_onboarding_slides.dart';
import 'trainer_onboarding_slides.dart';

/// Invisible widget that runs the welcome tour once, right after login.
///
/// Placement: a sibling inside the home shell's [Stack], next to
/// `PermissionGate`. It renders [SizedBox.shrink] — zero layout impact.
///
/// Deliberately NOT a router gate. `authRedirect` already carries seven gates
/// across two roles and has produced #429, #499 and #615; a tour is not a
/// precondition for anything, and putting informational content behind a
/// blocking redirect is the category error that made #429. The worst case here
/// is that the tour does not appear — nobody is locked out of the app.
///
/// The seen-flag is written AFTER the tour closes, never before: a failed write
/// must not be able to trap anyone inside it.
class OnboardingGate extends ConsumerStatefulWidget {
  const OnboardingGate({super.key});

  @override
  ConsumerState<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends ConsumerState<OnboardingGate> {
  /// The uid this instance has already presented the tour for.
  ///
  /// Instance latch. `userProfileProvider` is a stream and re-emits, so without
  /// it the tour would be pushed on top of itself between the dismissal and the
  /// arrival of the updated snapshot.
  ///
  /// Keyed by account rather than a plain `bool` so a second account signing in
  /// on the same device still gets its own tour. Today this widget is disposed
  /// on sign-out anyway — it lives inside the `ShellRoute` (home_screen.dart:60)
  /// and `/login` is a top-level route — but that makes the guarantee a property
  /// of the router's topology rather than of this gate. The uid key keeps it
  /// here, next to the latch it belongs to, and matches how
  /// [onboardingDismissedProvider] scopes the same decision.
  String? _presentedFor;

  @override
  Widget build(BuildContext context) {
    final surface = ref.watch(pendingMobileTourProvider);
    final uid = ref.watch(
      userProfileProvider.select((async) => async.valueOrNull?.uid),
    );
    final role = ref.watch(
      userProfileProvider.select((async) => async.valueOrNull?.role),
    );

    if (surface != null && role != null && uid != _presentedFor) {
      _presentedFor = uid;
      // Riverpod forbids mutating providers during build, and the navigator is
      // not ready to push mid-frame either.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final l10n = AppL10n.of(context);
        // Both roles now have a hi-fi deck. Same shell, different slides —
        // the schematic tour is gone from the mobile path.
        final slides = role == UserRole.athlete
            ? athleteOnboardingSlides
            : trainerOnboardingSlides;

        ref.read(onboardingTourOpenProvider.notifier).state = true;
        try {
          await Navigator.of(context, rootNavigator: true).push<void>(
            PageRouteBuilder<void>(
              opaque: true,
              barrierDismissible: false,
              transitionsBuilder: (_, animation, __, child) =>
                  FadeTransition(opacity: animation, child: child),
              // Pushed on the ROOT navigator so it covers the TreinoBottomBar,
              // and as a plain PageRoute rather than a PopupRoute — the bottom
              // bar closes popups with `popUntil((r) => r is! PopupRoute)` on
              // tab taps (router.dart), which would dismiss the tour by
              // accident.
              pageBuilder: (routeContext, __, ___) => OnboardingFlow(
                slides: slides,
                // The ROUTE context, never this widget's: the gate lives in the
                // screen underneath, and popping with its context closed the
                // SCREEN and left a black window.
                onFinish: () => Navigator.of(routeContext).pop(),
                onSkip: () => Navigator.of(routeContext).pop(),
                skipLabel: l10n.onboardingTourSkip,
                nextLabel: l10n.onboardingTourNext,
                finishLabel: l10n.onboardingTourFinish,
                lastStepLabel: 'LISTO', // i18n
                stepSemanticsLabel: l10n.onboardingTourProgress,
              ),
            ),
          );
        } finally {
          if (mounted) {
            ref.read(onboardingTourOpenProvider.notifier).state = false;
          }
          // Persist only after the route is gone. Failures are swallowed by the
          // controller and guarded by its session flag.
          await ref.read(onboardingControllerProvider).markSeen(surface);
        }
      });
    }

    return const SizedBox.shrink();
  }
}
