import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_l10n.dart';
import '../../profile/application/user_providers.dart';
import '../application/onboarding_providers.dart';
import '../domain/onboarding_surface.dart';
import 'custom_exercise_onboarding_slides.dart';
import 'onboarding_card_content.dart';
import 'custom_exercise_onboarding_view.dart';

/// Runs the "Creá tus propios ejercicios" onboarding once, the first time a
/// user opens the routine editor in CREATE mode.
///
/// Sin issue propia: nace del handoff de diseño "Onboarding Crear Ejercicios",
/// no de un ticket. No confundir con #628, que es otra feature (comentario y
/// foto por ejercicio durante la sesión).
///
/// Call it from `initState` behind an `addPostFrameCallback`: `initState` has no
/// `Localizations` ancestor resolved yet, and the navigator is not ready to
/// present mid-frame.
///
/// ── Why it is a function and not a gate widget ──────────────────────────────
/// The welcome tour uses `OnboardingGate`, an invisible widget in the home
/// shell's `Stack`, because it must fire on whatever screen the user lands on
/// after login. This one is anchored to exactly two screens and must NOT fire
/// on any other, so the trigger belongs at those two call sites. A widget would
/// have to re-derive "am I on the routine editor, in create mode" from state it
/// does not own.
///
/// Everything is `ref.read`, never `watch`: this runs once, imperatively, from
/// a post-frame callback. A `watch` here would rebuild nothing and only risk
/// re-entry when `userProfileProvider` re-emits.
Future<void> maybeShowCustomExerciseOnboarding({
  required BuildContext context,
  required WidgetRef ref,
  required OnboardingSurface surface,
}) async {
  // Wait for the profile before deciding anything. `userProfileProvider` is a
  // STREAM: on the first post-frame it is usually still `AsyncLoading`, so
  // every guard below would read `valueOrNull == null`, conclude "nothing to
  // show" and return — permanently, because this runs once and never retries.
  // The welcome tour does not have this problem: `OnboardingGate` is a widget
  // that WATCHES and re-evaluates on each emission. A one-shot callback has to
  // await instead.
  try {
    await ref.read(userProfileProvider.future);
  } catch (_) {
    // An errored profile stream is already routed to `/profile-unavailable`
    // (#544). Nothing to onboard on top of.
    return;
  }
  if (!context.mounted) return;

  // The welcome tour owns the screen, or is about to. Two modals stacked on one
  // frame is the failure this provider exists to prevent, and it was found on a
  // device rather than in a test — a widget test happily renders both and
  // reports success.
  if (ref.read(onboardingBlocksProvider)) return;

  if (!ref.read(shouldShowTourProvider(surface))) return;

  final slides = customExerciseSlidesFor(surface);
  if (slides == null || slides.isEmpty) return;

  if (!context.mounted) return;
  final l10n = AppL10n.of(context);
  final palette = AppPalette.of(context);
  final isWeb = surface == OnboardingSurface.customExerciseTrainerWeb;

  ref.read(onboardingTourOpenProvider.notifier).state = true;
  try {
    if (isWeb) {
      await showDialog<void>(
        context: context,
        // Exits are SALTAR and the CTA. Both persist the flag; a stray click on
        // the scrim should not decide whether the user ever sees this.
        barrierDismissible: false,
        barrierColor: palette.scrimDark.withValues(alpha: 0.66),
        builder: (dialogContext) => _OnboardingDialog(
          slides: slides,
          l10n: l10n,
          onClose: () => Navigator.of(dialogContext).pop(),
        ),
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        // Without this the sheet is pushed under `_ShellScaffold` and the
        // bottom bar sits on top of it.
        useRootNavigator: true,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        barrierColor: palette.scrimDark.withValues(alpha: 0.66),
        builder: (sheetContext) => _OnboardingSheet(
          slides: slides,
          l10n: l10n,
          onClose: () => Navigator.of(sheetContext).pop(),
        ),
      );
    }
  } finally {
    if (context.mounted) {
      ref.read(onboardingTourOpenProvider.notifier).state = false;
    }
    // Persist however it closed — CTA, SALTAR, Android back, or a route torn
    // down under us. Marking only on the two buttons is how an onboarding comes
    // back forever for anyone who pressed back once.
    //
    // The controller swallows write failures behind its session flag, so this
    // never throws into the caller's `initState`.
    await ref.read(onboardingControllerProvider).markSeen(surface);
  }
}

/// Mobile presentation: bottom sheet, content owns its chrome.
///
/// Pattern A (transparent host + a `Container` that draws the radius) rather
/// than passing `shape:` to the host — passing both double-paints the corner.
class _OnboardingSheet extends StatelessWidget {
  const _OnboardingSheet({
    required this.slides,
    required this.l10n,
    required this.onClose,
  });

  final List<OnboardingCardContent> slides;
  final AppL10n l10n;
  final VoidCallback onClose;

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
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          child: CustomExerciseOnboardingView(
            slides: slides,
            onFinish: onClose,
            onSkip: onClose,
            skipLabel: l10n.onboardingTourSkip,
            nextLabel: l10n.onboardingTourNext,
            finishLabel: l10n.onboardingCustomExerciseCta,
            stepSemanticsLabel: (current, total) =>
                l10n.onboardingTourProgress(current, total),
          ),
        ),
      ),
    );
  }
}

/// Coach Hub presentation: a centred 780pt card.
class _OnboardingDialog extends StatelessWidget {
  const _OnboardingDialog({
    required this.slides,
    required this.l10n,
    required this.onClose,
  });

  final List<OnboardingCardContent> slides;
  final AppL10n l10n;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Dialog(
      backgroundColor: palette.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: palette.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: CustomExerciseOnboardingView(
            slides: slides,
            layout: CustomExerciseOnboardingLayout.dialog,
            onFinish: onClose,
            onSkip: onClose,
            skipLabel: l10n.onboardingTourSkip,
            nextLabel: l10n.onboardingTourNext,
            finishLabel: l10n.onboardingCustomExerciseCta,
            stepSemanticsLabel: (current, total) =>
                l10n.onboardingTourProgress(current, total),
          ),
        ),
      ),
    );
  }
}
