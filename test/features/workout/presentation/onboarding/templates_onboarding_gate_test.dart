import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/onboarding/domain/onboarding_surface.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/presentation/onboarding/templates_onboarding_gate.dart';
import 'package:treino/features/workout/presentation/onboarding/templates_onboarding_view.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Captures EVERY update, not just the last one: finishing the flow writes
/// twice — the answers, then the seen-flag — and a single-slot capture would
/// silently hide one of them.
class _CapturingUserRepository extends Fake implements UserRepository {
  final updates = <Map<String, Object?>>[];

  int get updateCount => updates.length;

  Map<String, Object?>? get lastUpdate => updates.isEmpty ? null : updates.last;

  Map<String, Object?>? updateWithKey(String key) {
    for (final u in updates) {
      if (u.containsKey(key)) return u;
    }
    return null;
  }

  @override
  Future<void> update(String uid, Map<String, Object?> partial) async {
    updates.add(partial);
  }
}

/// The three WELCOME tours marked as seen.
///
/// Without this the welcome tour is still pending, `onboardingBlocksProvider`
/// is true, and this onboarding correctly refuses to stack on top of it — which
/// is its own test below, not the precondition for every other one.
const _toursSeen = <String, int>{
  'athleteMobile': 1,
  'trainerMobile': 1,
  'trainerWeb': 1,
};

UserProfile _profile({
  UserRole role = UserRole.athlete,
  Map<String, int> onboardingSeen = _toursSeen,
}) =>
    UserProfile(
      uid: 'u1',
      email: 'u1@treino.app',
      displayName: 'martin',
      role: role,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      onboardingSeen: onboardingSeen,
      trainerBio: role == UserRole.trainer ? 'bio' : null,
      trainerSpecialty: role == UserRole.trainer ? 'fuerza' : null,
      trainerMonthlyRate: role == UserRole.trainer ? 30000 : null,
      trainerOffersOnline: role == UserRole.trainer,
    );

/// Stands in for PlantillasTab: fires the gate once from a post-frame callback,
/// exactly as `_PlantillasTabState.initState` does.
class _Host extends ConsumerStatefulWidget {
  const _Host();

  @override
  ConsumerState<_Host> createState() => _HostState();
}

class _HostState extends ConsumerState<_Host> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      maybeShowTemplatesOnboarding(context: context, ref: ref);
    });
  }

  @override
  Widget build(BuildContext context) => const Text('GRILLA-DE-PLANTILLAS');
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required _CapturingUserRepository repo,
  UserProfile? profile,
  Stream<UserProfile?>? profiles,
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userRepositoryProvider.overrideWithValue(repo),
        userProfileProvider
            .overrideWith((ref) => profiles ?? Stream.value(profile)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(body: _Host()),
      ),
    ),
  );
  // Several frames: the profile stream resolves, then the post-frame callback
  // presents, then the sheet route animates in.
  await _settle(tester);
}

Future<void> _tapAndSettle(WidgetTester tester, Key key) async {
  // The sheet is capped at 90% of the viewport and scrolls: on a 390x844
  // surface the CTA sits below the fold on the taller steps, and `tap` refuses
  // to hit an off-screen target. Scroll it in first — that is also what a real
  // user does.
  await tester.ensureVisible(find.byKey(key));
  await _settle(tester);
  await tester.tap(find.byKey(key));
  await _settle(tester);
}

void main() {
  group('maybeShowTemplatesOnboarding — first-entry gate', () {
    testWidgets('presents the sheet for an athlete who has not seen it',
        (tester) async {
      await _pump(tester,
          repo: _CapturingUserRepository(), profile: _profile());

      expect(find.byType(TemplatesOnboardingView), findsOneWidget);
      expect(find.text('¿CUÁNTOS DÍAS PODÉS ENTRENAR?'), findsOneWidget);
    });

    testWidgets('does NOT present when the surface is already seen',
        (tester) async {
      final repo = _CapturingUserRepository();
      await _pump(
        tester,
        repo: repo,
        profile: _profile(
          onboardingSeen: {
            ..._toursSeen,
            // Derived, never the literal 1: `currentVersion` is also the QA
            // lever for re-triggering the flow on a device, so a hardcoded
            // version turns a local bump into a red test that says nothing
            // about the behaviour under test.
            'templatesAthleteMobile':
                OnboardingSurface.templatesAthleteMobile.currentVersion,
          },
        ),
      );

      expect(find.byType(TemplatesOnboardingView), findsNothing);
      expect(find.text('GRILLA-DE-PLANTILLAS'), findsOneWidget);
      expect(repo.updateCount, 0, reason: 'nothing to persist');
    });

    testWidgets('does NOT stack on top of the pending welcome tour',
        (tester) async {
      // Empty map → the welcome tour is still due, so onboardingBlocksProvider
      // is true. Two modals on one frame is the bug this guards.
      await _pump(
        tester,
        repo: _CapturingUserRepository(),
        profile: _profile(onboardingSeen: const {}),
      );

      expect(find.byType(TemplatesOnboardingView), findsNothing);
    });

    testWidgets('presents once the pending welcome tour clears',
        (tester) async {
      // Same starting point as the test above — and the other half of it.
      // Waiting is not the same as giving up: this function gets ONE attempt
      // per mount (initState, on a tab that keeps itself alive), so an athlete
      // who reaches PLANTILLAS before the welcome tour has run would otherwise
      // spend that attempt on a `return` and miss the visit that IS their
      // first one.
      final profiles = StreamController<UserProfile?>();
      addTearDown(profiles.close);

      await _pump(
        tester,
        repo: _CapturingUserRepository(),
        profiles: profiles.stream,
      );

      profiles.add(_profile(onboardingSeen: const {}));
      await _settle(tester);
      expect(find.byType(TemplatesOnboardingView), findsNothing);

      // The welcome tour ran on HomeScreen and marked itself seen.
      profiles.add(_profile());
      await _settle(tester);

      expect(find.byType(TemplatesOnboardingView), findsOneWidget);
      expect(find.text('¿CUÁNTOS DÍAS PODÉS ENTRENAR?'), findsOneWidget);
    });

    testWidgets('does NOT present for a trainer', (tester) async {
      // The trainer half of the handoff declares metadata ON the routine at
      // publish time, which needs `Routine.goals` (#635 PR#1). Until that
      // exists, a trainer must not get this flow.
      await _pump(
        tester,
        repo: _CapturingUserRepository(),
        profile: _profile(role: UserRole.trainer),
      );

      expect(find.byType(TemplatesOnboardingView), findsNothing);
    });

    testWidgets('does NOT present when there is no profile', (tester) async {
      await _pump(tester, repo: _CapturingUserRepository(), profile: null);

      expect(find.byType(TemplatesOnboardingView), findsNothing);
    });
  });

  group('maybeShowTemplatesOnboarding — skip', () {
    testWidgets('SALTAR closes it, marks it seen, and persists NO answers',
        (tester) async {
      final repo = _CapturingUserRepository();
      await _pump(tester, repo: repo, profile: _profile());

      // Answer step 1 first, to prove SALTAR discards even a real selection.
      await _tapAndSettle(
        tester,
        templatesOnboardingOptionKey('days', '3'),
      );
      await _tapAndSettle(tester, templatesOnboardingSkipKey);

      expect(find.byType(TemplatesOnboardingView), findsNothing);
      expect(
        repo.updateWithKey('templatePreferences'),
        isNull,
        reason: 'SALTAR must not write answers the user chose to abandon',
      );
      expect(repo.updateWithKey('onboardingSeen'), isNotNull);
    });

    testWidgets('SALTAR stays reachable on the LAST step', (tester) async {
      final repo = _CapturingUserRepository();
      await _pump(tester, repo: repo, profile: _profile());

      for (var i = 0; i < 3; i++) {
        await _tapAndSettle(tester, templatesOnboardingCtaKey);
      }

      expect(find.text('ESTO NO ES UN EXAMEN'), findsOneWidget);
      expect(find.byKey(templatesOnboardingSkipKey), findsOneWidget);
    });
  });

  group('maybeShowTemplatesOnboarding — versioned persistence', () {
    testWidgets('marks the surface seen at its CURRENT version',
        (tester) async {
      final repo = _CapturingUserRepository();
      await _pump(tester, repo: repo, profile: _profile());

      await _tapAndSettle(tester, templatesOnboardingSkipKey);

      final seen =
          repo.updateWithKey('onboardingSeen')!['onboardingSeen']! as Map;
      expect(
        seen['templatesAthleteMobile'],
        OnboardingSurface.templatesAthleteMobile.currentVersion,
      );
    });

    testWidgets('preserves the OTHER surfaces already in the map',
        (tester) async {
      // The payload is the whole map with one entry replaced, never a
      // single-key partial — see OnboardingController.markSeen.
      final repo = _CapturingUserRepository();
      await _pump(tester, repo: repo, profile: _profile());

      await _tapAndSettle(tester, templatesOnboardingSkipKey);

      final seen =
          repo.updateWithKey('onboardingSeen')!['onboardingSeen']! as Map;
      expect(seen['athleteMobile'], 1);
      expect(seen['trainerMobile'], 1);
      expect(seen['trainerWeb'], 1);
    });

    testWidgets('persists the four answers when the CTA finishes the flow',
        (tester) async {
      final repo = _CapturingUserRepository();
      await _pump(tester, repo: repo, profile: _profile());

      await _tapAndSettle(tester, templatesOnboardingOptionKey('days', '3'));
      await _tapAndSettle(tester, templatesOnboardingCtaKey);

      await _tapAndSettle(
          tester, templatesOnboardingOptionKey('minutes', '45'));
      await _tapAndSettle(tester, templatesOnboardingCtaKey);

      await _tapAndSettle(
        tester,
        templatesOnboardingOptionKey('goal', 'health'),
      );
      await _tapAndSettle(tester, templatesOnboardingCtaKey);

      await _tapAndSettle(
          tester, templatesOnboardingOptionKey('zones', 'back'));
      await _tapAndSettle(
          tester, templatesOnboardingOptionKey('zones', 'core'));
      await _tapAndSettle(tester, templatesOnboardingCtaKey);

      expect(find.byType(TemplatesOnboardingView), findsNothing);

      final prefs = repo
          .updateWithKey('templatePreferences')!['templatePreferences']! as Map;
      expect(prefs['daysPerWeek'], 3);
      expect(prefs['minutesPerSession'], 45);
      expect(prefs['goal'], 'health');
      expect(
        (prefs['priorityMuscleGroups']! as List).toSet(),
        {'back', 'core'},
      );

      expect(repo.updateWithKey('onboardingSeen'), isNotNull);
    });

    testWidgets('writes NO preferences map when nothing was answered',
        (tester) async {
      // Tapping through without choosing anything must not stamp an all-null
      // map on the document. "Did they see it" is onboardingSeen's job.
      final repo = _CapturingUserRepository();
      await _pump(tester, repo: repo, profile: _profile());

      for (var i = 0; i < 4; i++) {
        await _tapAndSettle(tester, templatesOnboardingCtaKey);
      }

      expect(find.byType(TemplatesOnboardingView), findsNothing);
      expect(repo.updateWithKey('templatePreferences'), isNull);
      expect(repo.updateWithKey('onboardingSeen'), isNotNull);
    });
  });
}
