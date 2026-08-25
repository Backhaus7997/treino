import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/onboarding/domain/onboarding_surface.dart';
import 'package:treino/features/onboarding/presentation/custom_exercise_onboarding_gate.dart';
import 'package:treino/features/onboarding/presentation/custom_exercise_onboarding_view.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/l10n/app_l10n.dart';

class _CapturingUserRepository extends Fake implements UserRepository {
  Map<String, Object?>? capturedPartial;
  int updateCount = 0;
  bool shouldThrow = false;

  @override
  Future<void> update(String uid, Map<String, Object?> partial) async {
    updateCount++;
    capturedPartial = partial;
    if (shouldThrow) throw Exception('simulated failure');
  }
}

/// The three WELCOME tours marked as seen.
///
/// Without this the welcome tour is still pending, `onboardingBlocksProvider`
/// is true, and the feature onboarding correctly refuses to stack on top of it
/// — which is its own test below, not the precondition for every other one.
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

/// Stands in for the routine editor: fires the gate once from a post-frame
/// callback in create mode, exactly as `RoutineEditorScreen.initState` does.
class _Host extends ConsumerStatefulWidget {
  const _Host({required this.surface});

  final OnboardingSurface surface;

  @override
  ConsumerState<_Host> createState() => _HostState();
}

class _HostState extends ConsumerState<_Host> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      maybeShowCustomExerciseOnboarding(
        context: context,
        ref: ref,
        surface: widget.surface,
      );
    });
  }

  @override
  Widget build(BuildContext context) => const Text('EDITOR-DE-RUTINA');
}

Future<void> _pump(
  WidgetTester tester, {
  required _CapturingUserRepository repo,
  UserProfile? profile,
  OnboardingSurface surface = OnboardingSurface.customExerciseAthleteMobile,
  Size size = const Size(390, 844),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userRepositoryProvider.overrideWithValue(repo),
        userProfileProvider.overrideWith((ref) => Stream.value(profile)),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(body: _Host(surface: surface)),
      ),
    ),
  );
  // Several frames: the profile stream resolves, then the post-frame callback
  // presents, then the sheet route animates in.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _tapAndSettle(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  group('maybeShowCustomExerciseOnboarding', () {
    testWidgets('presents the sheet for a user who has not seen it',
        (tester) async {
      await _pump(tester,
          repo: _CapturingUserRepository(), profile: _profile());

      expect(find.byType(CustomExerciseOnboardingView), findsOneWidget);
      expect(find.text('¿FALTA UN EJERCICIO? CREÁLO VOS'), findsOneWidget);
    });

    testWidgets('does NOT present when the surface is already seen',
        (tester) async {
      final repo = _CapturingUserRepository();
      await _pump(
        tester,
        repo: repo,
        profile: _profile(
          onboardingSeen: {..._toursSeen, 'customExerciseAthleteMobile': 1},
        ),
      );

      expect(find.byType(CustomExerciseOnboardingView), findsNothing);
      expect(find.text('EDITOR-DE-RUTINA'), findsOneWidget);
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

      expect(find.byType(CustomExerciseOnboardingView), findsNothing);
    });

    testWidgets('marks the surface seen when the CTA finishes it',
        (tester) async {
      final repo = _CapturingUserRepository();
      await _pump(tester, repo: repo, profile: _profile());

      const cta = Key('custom_exercise_onboarding_primary_cta');
      await _tapAndSettle(tester, cta); // slide 2
      await _tapAndSettle(tester, cta); // slide 3
      await _tapAndSettle(tester, cta); // finish

      expect(find.byType(CustomExerciseOnboardingView), findsNothing);
      expect(repo.updateCount, 1);
      expect(
        repo.capturedPartial,
        {
          'onboardingSeen': {
            ..._toursSeen,
            'customExerciseAthleteMobile': 1,
          },
        },
        reason: 'the WHOLE map is written, never a single-key partial',
      );
    });

    testWidgets('marks the surface seen when the user skips', (tester) async {
      final repo = _CapturingUserRepository();
      await _pump(tester, repo: repo, profile: _profile());

      await _tapAndSettle(
        tester,
        const Key('custom_exercise_onboarding_skip_button'),
      );

      expect(find.byType(CustomExerciseOnboardingView), findsNothing);
      expect(repo.updateCount, 1);
      expect(
        (repo.capturedPartial!['onboardingSeen']!
            as Map)['customExerciseAthleteMobile'],
        1,
        reason: 'skipping is a real exit, not a postponement',
      );
    });

    testWidgets('a failed write still lets the user out', (tester) async {
      final repo = _CapturingUserRepository()..shouldThrow = true;
      await _pump(tester, repo: repo, profile: _profile());

      await _tapAndSettle(
        tester,
        const Key('custom_exercise_onboarding_skip_button'),
      );

      // Nobody is held behind a welcome screen because Firestore is
      // unreachable — that is the dead-end class of bug #429.
      expect(find.byType(CustomExerciseOnboardingView), findsNothing);
      expect(find.text('EDITOR-DE-RUTINA'), findsOneWidget);
      expect(repo.updateCount, 1);
    });

    testWidgets('the trainer surface gets the assign-to-students deck',
        (tester) async {
      await _pump(
        tester,
        repo: _CapturingUserRepository(),
        profile: _profile(role: UserRole.trainer),
        surface: OnboardingSurface.customExerciseTrainerMobile,
      );

      expect(find.byType(CustomExerciseOnboardingView), findsOneWidget);
      expect(find.text('¿FALTA UN EJERCICIO? CREÁLO VOS'), findsOneWidget);
    });

    testWidgets('the web surface presents a Dialog, not a sheet',
        (tester) async {
      await _pump(
        tester,
        repo: _CapturingUserRepository(),
        profile: _profile(role: UserRole.trainer),
        surface: OnboardingSurface.customExerciseTrainerWeb,
        size: const Size(1280, 800),
      );

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(CustomExerciseOnboardingView), findsOneWidget);
    });
  });
}
