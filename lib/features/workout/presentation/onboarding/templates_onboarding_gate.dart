import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../onboarding/application/onboarding_providers.dart';
import '../../../onboarding/domain/onboarding_surface.dart';
import '../../../profile/application/user_providers.dart';
import '../../../profile/domain/user_profile.dart';
import '../../../profile/domain/user_role.dart';
import '../../application/template_preferences_providers.dart';
import '../../domain/template_preferences.dart';
import 'templates_onboarding_steps.dart';
import 'templates_onboarding_view.dart';

/// Runs the PLANTILLAS mini-onboarding once, the first time an athlete opens
/// Entrenar → PLANTILLAS (#635 PR#2).
///
/// A function fired from the tab rather than a gate widget, for the same reason
/// `maybeShowCustomExerciseOnboarding` is: this is anchored to exactly one
/// screen and must not fire anywhere else, so the trigger belongs at that call
/// site. `OnboardingGate` is a widget because the welcome tour has to fire on
/// whatever screen the user lands on after login — a different problem.
///
/// Call it from `initState` behind an `addPostFrameCallback`: `initState` has no
/// `Localizations` ancestor resolved yet, and the navigator is not ready to
/// present mid-frame.
///
/// Everything is `ref.read`, never `watch`: this runs once, imperatively.
Future<void> maybeShowTemplatesOnboarding({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  const surface = OnboardingSurface.templatesAthleteMobile;

  // Wait for the profile before deciding anything. `userProfileProvider` is a
  // STREAM: on the first post-frame it is usually still `AsyncLoading`, so every
  // guard below would read `valueOrNull == null`, conclude "nothing to show" and
  // return — permanently, because this runs once and never retries.
  final UserProfile? profile;
  try {
    profile = await ref.read(userProfileProvider.future);
  } catch (_) {
    // An errored profile stream is already routed to `/profile-unavailable`
    // (#544). Nothing to onboard on top of.
    return;
  }
  // The stream is nullable: a signed-out user, or a document that has not been
  // created yet, resolves to null rather than throwing.
  if (profile == null) return;
  if (!context.mounted) return;

  // Athlete-only. A trainer browsing PLANTILLAS is looking at a catalogue to
  // copy from, not choosing a plan for themselves, and their half of the
  // handoff is a different flow entirely — it declares metadata ON the routine
  // at publish time, which needs `Routine.goals` (#635 PR#1).
  if (profile.role != UserRole.athlete) return;

  // The welcome tour owns the screen, or is about to. Two modals stacked on one
  // frame is the failure this provider exists to prevent.
  //
  // WAIT for it instead of returning. What must not happen is STACKING, not
  // this flow — and this function gets exactly ONE attempt per mount, fired
  // from `initState` on a tab that keeps itself alive. So an athlete who
  // reaches PLANTILLAS before the welcome tour has run (a restored route, a
  // deep link) would spend that single attempt on a `return` and never see the
  // mini-onboarding on the visit that IS their first one.
  if (ref.read(onboardingBlocksProvider)) {
    if (!await _awaitUnblocked(ref)) return;
    if (!context.mounted) return;
  }

  if (!ref.read(shouldShowTourProvider(surface))) return;

  if (!context.mounted) return;
  final l10n = AppL10n.of(context);
  final palette = AppPalette.of(context);
  final steps = templatesOnboardingSteps(l10n);

  ref.read(onboardingTourOpenProvider.notifier).state = true;
  try {
    await showModalBottomSheet<void>(
      context: context,
      // Without this the sheet is pushed under `_ShellScaffold` and the bottom
      // bar sits on top of it.
      useRootNavigator: true,
      isScrollControlled: true,
      // NO drag, and no scrim tap. Unlike the slide decks — where dragging the
      // sheet away is a fine way to say "I read it" — this one is a FORM: a
      // half-answered flow closed by a stray downward swipe loses the answers
      // silently and, because `finally` marks the surface seen, never offers
      // them again. The two deliberate exits are SALTAR and the CTA.
      enableDrag: false,
      isDismissible: false,
      backgroundColor: Colors.transparent,
      barrierColor: palette.scrimDark.withValues(alpha: 0.66),
      builder: (sheetContext) => _TemplatesOnboardingSheet(
        steps: steps,
        l10n: l10n,
        onFinish: (preferences) {
          // Persist BEFORE popping: after the pop this callback's `ref` is
          // still valid (it belongs to the caller, not the sheet), but keeping
          // the order explicit means a future refactor cannot make the write
          // depend on a torn-down route.
          ref.read(templatePreferencesControllerProvider).save(preferences);
          Navigator.of(sheetContext).pop();
        },
        onSkip: () => Navigator.of(sheetContext).pop(),
      ),
    );
  } finally {
    if (context.mounted) {
      ref.read(onboardingTourOpenProvider.notifier).state = false;
    }
    // Persist however it closed — CTA, SALTAR, Android back, drag, or a route
    // torn down under us. Marking only on the two buttons is how an onboarding
    // comes back forever for anyone who dismissed it once.
    await ref.read(onboardingControllerProvider).markSeen(surface);
  }
}

/// Completes with `true` once no other onboarding owns the screen.
///
/// Deliberately WITHOUT a timeout. A `Timer` left running past the end of a
/// widget test fails it, and there is nothing sensible to do when it fires
/// anyway. The wait is bounded by the widget instead: `listenManual` closes its
/// subscription when the host element unmounts, so a torn-down tab simply
/// leaves this future hanging and the caller never resumes — which is the right
/// answer, because the screen this flow belongs to is gone. Whatever attempt
/// was owed comes back on the next mount, from `initState` as usual.
Future<bool> _awaitUnblocked(WidgetRef ref) {
  final completer = Completer<bool>();
  final subscription = ref.listenManual<bool>(
    onboardingBlocksProvider,
    (_, blocks) {
      if (!blocks && !completer.isCompleted) completer.complete(true);
    },
  );
  return completer.future.whenComplete(subscription.close);
}

/// Mobile presentation: bottom sheet, content owns its chrome.
///
/// Pattern A (transparent host + a `Container` that draws the radius) rather
/// than passing `shape:` to the host — passing both double-paints the corner.
class _TemplatesOnboardingSheet extends StatelessWidget {
  const _TemplatesOnboardingSheet({
    required this.steps,
    required this.l10n,
    required this.onFinish,
    required this.onSkip,
  });

  final List<TemplatesOnboardingStep> steps;
  final AppL10n l10n;
  final void Function(TemplatePreferences preferences) onFinish;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.9,
      ),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          child: TemplatesOnboardingView(
            steps: steps,
            onFinish: onFinish,
            onSkip: onSkip,
            skipLabel: l10n.onboardingTourSkip,
            nextLabel: l10n.onboardingTourNext,
            finishLabel: l10n.templatesOnboardingCta,
            backLabel: l10n.templatesOnboardingBack,
            stepSemanticsLabel: (current, total) =>
                l10n.onboardingTourProgress(current, total),
          ),
        ),
      ),
    );
  }
}
