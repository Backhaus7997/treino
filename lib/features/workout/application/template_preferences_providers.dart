import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart';
import '../domain/template_preferences.dart';

final templatePreferencesControllerProvider =
    Provider<TemplatePreferencesController>(
  (ref) => TemplatePreferencesController(ref),
);

/// Persists the PLANTILLAS mini-onboarding answers (#635 PR#2).
///
/// Separate from [OnboardingController] on purpose: that one owns "has this
/// user seen this surface", which every onboarding shares. This owns the
/// ANSWERS, which only this flow produces. Folding them together would put a
/// workout-domain payload inside the generic tour controller.
class TemplatePreferencesController {
  TemplatePreferencesController(this._ref);

  final Ref _ref;

  /// Writes [preferences] to `users/{uid}.templatePreferences`.
  ///
  /// Nothing is written when the athlete answered nothing: SALTAR on step 1
  /// should not stamp an all-null map on the document just to prove the flow
  /// ran. "Did they see it" is `onboardingSeen`'s job, and it is recorded
  /// separately on every exit path.
  ///
  /// The whole map is sent, never a partial: `users/{uid}` has no key allowlist
  /// in firestore.rules (:65-80), so this is a plain owner write, but
  /// `fake_cloud_firestore` replaces top-level keys outright instead of
  /// deep-merging — a partial would make every test against the fake lie.
  ///
  /// Failures are swallowed and logged, matching `OnboardingController.markSeen`:
  /// the flow has already closed by the time this runs, and re-opening a modal
  /// because Firestore is unreachable is the dead-end class of bug #429.
  Future<void> save(TemplatePreferences preferences) async {
    if (preferences.isEmpty) return;

    final profile = _ref.read(userProfileProvider).valueOrNull;
    if (profile == null) return;

    try {
      await _ref.read(userRepositoryProvider).update(
        profile.uid,
        {'templatePreferences': preferences.toJson()},
      );
    } catch (e) {
      developer.log(
        'saveTemplatePreferences failed: $e',
        name: 'templates-onboarding',
      );
    }
  }
}

/// Las preferencias de plantillas del atleta firmado, o vacías si no respondió
/// (#635 PR#3).
///
/// `select` sobre el campo y no `watch` del perfil entero: el stream de
/// `users/{uid}` re-emite por cualquier cambio —una foto de perfil, un flag de
/// onboarding, el peso— y sin esto el ranking de PLANTILLAS se recalcularía
/// con cada uno.
///
/// Vacío y ausente colapsan al mismo valor a propósito: quien saltó el
/// cuestionario y quien lo respondió sin elegir nada están en el mismo estado
/// —sin señal— y el scoring los trata igual.
final athleteTemplatePreferencesProvider = Provider<TemplatePreferences>((ref) {
  return ref.watch(
        userProfileProvider
            .select((p) => p.valueOrNull?.templatePreferences),
      ) ??
      const TemplatePreferences();
});
