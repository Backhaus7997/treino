import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_l10n.dart';
import '../../profile/application/user_providers.dart';
import '../application/onboarding_providers.dart';
import '../domain/onboarding_surface.dart';
import 'onboarding_card_copy.dart';
import 'onboarding_tour_view.dart';

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
  /// Instance latch. `userProfileProvider` is a stream and re-emits, so without
  /// this the tour would be pushed on top of itself between the dismissal and
  /// the arrival of the updated snapshot.
  bool _presenting = false;

  @override
  Widget build(BuildContext context) {
    final surface = ref.watch(pendingMobileTourProvider);
    final role = ref.watch(
      userProfileProvider.select((async) => async.valueOrNull?.role),
    );

    if (surface != null && role != null && !_presenting) {
      _presenting = true;
      // Riverpod forbids mutating providers during build, and the navigator is
      // not ready to push mid-frame either.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final l10n = AppL10n.of(context);
        final slides = [
          for (final module in surface.slides)
            if (mobileCardContent(module, role, l10n) case final c?) c,
        ];
        if (slides.isEmpty) return;

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
              pageBuilder: (routeContext, __, ___) => OnboardingTourView(
                slides: slides,
                // The DIALOG/route context, never this widget's: the gate lives
                // in the screen underneath, and popping with its context closed
                // the SCREEN and left a black window.
                onFinish: () => Navigator.of(routeContext).pop(),
                onSkip: () => Navigator.of(routeContext).pop(),
                skipLabel: l10n.onboardingTourSkip,
                nextLabel: l10n.onboardingTourNext,
                finishLabel: l10n.onboardingTourFinish,
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
