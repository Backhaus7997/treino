import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../onboarding/application/onboarding_providers.dart'
    show onboardingBlocksProvider;
import '../application/trainer_location_consent_providers.dart';
import '../application/user_providers.dart';

/// consentimiento-legal-versionado — R7, D-E.
///
/// Consent prompt for publishing a trainer's location. Exactly THREE exits,
/// ALL of which stamp `trainerLocationConsentPromptedAt`:
///
///  - ACEPTAR → [UserRepository.grantTrainerLocationConsent].
///  - APAGAR LA PUBLICACIÓN → [UserRepository.revokeTrainerLocationConsent].
///  - deliberate close (drag / back) → stamps ONLY `promptedAt`, via a plain
///    `update()` partial (no grant, no revoke — design's data-flow diagram).
///
/// All three writes happen from INSIDE this widget (not the caller's
/// `finally`, unlike `custom_exercise_onboarding_gate.dart`'s tour) so the
/// full 3-way contract is testable against this widget alone.
///
/// Present via `showModalBottomSheet(isDismissible: false, enableDrag:
/// true, ...)` — same pattern as `custom_exercise_onboarding_gate.dart`'s
/// `_OnboardingSheet`: blocks the accidental scrim tap, allows the
/// deliberate drag-away exit. A `PopScope` here intercepts BOTH drag and
/// back-button dismissal (they resolve through the same `Navigator.pop`),
/// and no-ops if a button already handled the exit.
class TrainerLocationConsentSheet extends ConsumerStatefulWidget {
  const TrainerLocationConsentSheet({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<TrainerLocationConsentSheet> createState() =>
      _TrainerLocationConsentSheetState();
}

class _TrainerLocationConsentSheetState
    extends ConsumerState<TrainerLocationConsentSheet> {
  /// Set the moment ANY of the 3 exits starts running its write, so the
  /// `PopScope` interception below never double-writes.
  bool _decided = false;
  bool _busy = false;

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    _decided = true;
    await ref
        .read(userRepositoryProvider)
        .grantTrainerLocationConsent(widget.uid);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _revoke() async {
    if (_busy) return;
    setState(() => _busy = true);
    _decided = true;
    await ref
        .read(userRepositoryProvider)
        .revokeTrainerLocationConsent(widget.uid);
    if (mounted) Navigator.of(context).pop();
  }

  /// Deliberate close without choosing (drag or back). Stamps ONLY
  /// `promptedAt` — never routed through grant/revoke, since neither
  /// consent decision was made.
  Future<void> _stampPromptedOnly() async {
    if (_decided) return;
    _decided = true;
    await ref.read(userRepositoryProvider).update(widget.uid, {
      'trainerLocationConsentPromptedAt':
          Timestamp.fromDate(DateTime.now().toUtc()),
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) unawaited(_stampPromptedOnly());
      },
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.9,
        ),
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
          border: Border(top: BorderSide(color: palette.border)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(TreinoIcon.mapPin, color: palette.accent, size: 28),
                const SizedBox(height: 12),
                Text(
                  l10n.trainerLocationConsentSheetTitle,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: palette.textPrimary,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.trainerLocationConsentSheetBody,
                  style: TextStyle(color: palette.textMuted, fontSize: 14),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  key: const Key('trainer_location_consent_accept_button'),
                  onPressed: _busy ? null : _accept,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.accent,
                    minimumSize: const Size.fromHeight(48),
                    shape: const StadiumBorder(),
                  ),
                  child: Text(l10n.trainerLocationConsentSheetAccept),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const Key('trainer_location_consent_revoke_button'),
                  onPressed: _busy ? null : _revoke,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: palette.textMuted,
                    side: BorderSide(color: palette.border),
                    minimumSize: const Size.fromHeight(48),
                    shape: const StadiumBorder(),
                  ),
                  child: Text(l10n.trainerLocationConsentSheetRevoke),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Invisible widget that presents [TrainerLocationConsentSheet] once, the
/// first time a trainer with a published (or about-to-be-relevant) location
/// has neither granted nor been asked for consent.
///
/// Mirrors `OnboardingGate` (`../../onboarding/presentation/onboarding_gate.dart`):
/// instance-level uid latch (a stream re-emission for the SAME trainer must
/// not re-show it), `addPostFrameCallback` (Riverpod forbids mutating
/// providers mid-build and the navigator is not ready mid-frame), and waits
/// on `!onboardingBlocksProvider` — same condition `PermissionGate` waits on
/// (`permission_gate.dart:49-51`) — so the welcome tour / permission prompt
/// never stacks with this one on the same frame.
class TrainerLocationConsentGate extends ConsumerStatefulWidget {
  const TrainerLocationConsentGate({super.key});

  @override
  ConsumerState<TrainerLocationConsentGate> createState() =>
      _TrainerLocationConsentGateState();
}

class _TrainerLocationConsentGateState
    extends ConsumerState<TrainerLocationConsentGate> {
  /// The uid this instance has already presented the sheet for.
  String? _presentedFor;

  @override
  Widget build(BuildContext context) {
    final shouldAsk = ref.watch(shouldAskTrainerLocationConsentProvider);
    final uid = ref.watch(
      userProfileProvider.select((async) => async.valueOrNull?.uid),
    );
    final onboardingPending = ref.watch(onboardingBlocksProvider);

    if (shouldAsk &&
        uid != null &&
        uid != _presentedFor &&
        !onboardingPending) {
      _presentedFor = uid;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(trainerLocationConsentDismissedProvider.notifier)
            .markDismissed();
        showModalBottomSheet<void>(
          context: context,
          useRootNavigator: true,
          isScrollControlled: true,
          enableDrag: true,
          isDismissible: false,
          backgroundColor: Colors.transparent,
          barrierColor: AppPalette.of(context).scrimDark.withValues(
                alpha: 0.66,
              ),
          builder: (_) => TrainerLocationConsentSheet(uid: uid),
        );
      });
    }

    return const SizedBox.shrink();
  }
}
