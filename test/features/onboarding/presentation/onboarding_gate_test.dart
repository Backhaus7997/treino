import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/onboarding/application/onboarding_providers.dart';
import 'package:treino/features/onboarding/domain/onboarding_surface.dart';
import 'package:treino/features/onboarding/presentation/onboarding_gate.dart';
import 'package:treino/features/onboarding/presentation/onboarding_flow.dart';

import '../../../helpers/layout_failure.dart';
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

UserProfile _profile({
  UserRole role = UserRole.athlete,
  String? displayName = 'martin',
  Map<String, int> onboardingSeen = const {},
}) =>
    UserProfile(
      uid: 'u1',
      email: 'u1@treino.app',
      displayName: displayName,
      role: role,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      onboardingSeen: onboardingSeen,
      // A trainer with an INCOMPLETE professional profile is owned by the
      // /profile/edit-trainer gate and must not get a tour.
      trainerBio: role == UserRole.trainer ? 'bio' : null,
      trainerSpecialty: role == UserRole.trainer ? 'fuerza' : null,
      trainerMonthlyRate: role == UserRole.trainer ? 30000 : null,
      trainerOffersOnline: role == UserRole.trainer,
    );

Future<void> _pump(
  WidgetTester tester, {
  required _CapturingUserRepository repo,
  UserProfile? profile,
  Stream<UserProfile?>? profileStream,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        userRepositoryProvider.overrideWithValue(repo),
        userProfileProvider.overrideWith(
          (ref) => profileStream ?? Stream.value(profile),
        ),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: Locale('es', 'AR'),
        home: Scaffold(
          body: Column(
            children: [Text('PANTALLA-DE-ABAJO'), OnboardingGate()],
          ),
        ),
      ),
    ),
  );
  // Repeated pump(), NOT pumpAndSettle(): the trainer's first slide carries a
  // dot that pulses on an infinite loop by design, and pumpAndSettle waits for
  // every animation to stop — it would hang here forever. Several frames are
  // needed because the gate pushes the route from a post-frame callback and the
  // route then fades in.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  // The tour renders real screens, so this settles a lot of widgets.
  // Drain here so every gate test starts clean, failing only on structural
  // breakage rather than the font artifact — see drainLayoutFailure.
  expect(drainLayoutFailure(tester), isNull);
}

void main() {
  group('OnboardingGate', () {
    testWidgets('runs the tour for a fresh athlete', (tester) async {
      await _pump(
        tester,
        repo: _CapturingUserRepository(),
        profile: _profile(),
      );

      expect(find.byType(OnboardingFlow), findsOneWidget);
      expect(find.text('TU RESUMEN DEL DÍA'), findsOneWidget);
    });

    testWidgets('runs the TRAINER tour for a complete trainer', (tester) async {
      await _pump(
        tester,
        repo: _CapturingUserRepository(),
        profile: _profile(role: UserRole.trainer),
      );

      expect(find.text('TU DÍA EN UN PANTALLAZO'), findsOneWidget);
      expect(find.text('TU RESUMEN DEL DÍA'), findsNothing);
    });

    testWidgets('does NOT run for a trainer with an incomplete profile',
        (tester) async {
      // That user belongs to the /profile/edit-trainer gate (ADR-TPO-003).
      await _pump(
        tester,
        repo: _CapturingUserRepository(),
        profile: UserProfile(
          uid: 'u1',
          email: 'u1@treino.app',
          displayName: 'martin',
          role: UserRole.trainer,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );

      expect(find.byType(OnboardingFlow), findsNothing);
    });

    testWidgets('does NOT run once the surface is marked seen', (tester) async {
      await _pump(
        tester,
        repo: _CapturingUserRepository(),
        profile: _profile(
          onboardingSeen: {
            OnboardingSurface.athleteMobile.wireKey:
                OnboardingSurface.athleteMobile.currentVersion,
          },
        ),
      );

      expect(find.byType(OnboardingFlow), findsNothing);
    });

    testWidgets('does NOT run while profile setup is incomplete',
        (tester) async {
      await _pump(
        tester,
        repo: _CapturingUserRepository(),
        profile: _profile(displayName: null),
      );

      expect(find.byType(OnboardingFlow), findsNothing);
    });

    testWidgets('COMENZAR closes the tour and leaves the app usable',
        (tester) async {
      // Regression: popping with the GATE's context instead of the route's
      // closed the screen underneath and left a black window.
      final repo = _CapturingUserRepository();
      await _pump(tester, repo: repo, profile: _profile());

      expect(repo.updateCount, 0, reason: 'nothing written while it is open');

      for (var i = 0; i < OnboardingSurface.athleteMobile.slides.length; i++) {
        await tester.tap(find.byKey(const Key('onboarding_primary_cta')));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(drainLayoutFailure(tester), isNull);
      }

      expect(find.byType(OnboardingFlow), findsNothing);
      expect(find.text('PANTALLA-DE-ABAJO'), findsOneWidget,
          reason: 'the screen under the tour was popped along with it');
      expect(repo.updateCount, 1);
      expect(
        repo.capturedPartial!['onboardingSeen'],
        {
          OnboardingSurface.athleteMobile.wireKey:
              OnboardingSurface.athleteMobile.currentVersion,
        },
      );
    });

    testWidgets('SALTAR closes it too, and persists', (tester) async {
      final repo = _CapturingUserRepository();
      await _pump(tester, repo: repo, profile: _profile());

      await tester.tap(find.byKey(const Key('onboarding_skip_button')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(drainLayoutFailure(tester), isNull);

      expect(find.byType(OnboardingFlow), findsNothing);
      expect(find.text('PANTALLA-DE-ABAJO'), findsOneWidget);
      expect(repo.updateCount, 1);
    });

    testWidgets('it still closes when the write FAILS', (tester) async {
      // Nobody is trapped in a welcome screen because Firestore is down.
      final repo = _CapturingUserRepository()..shouldThrow = true;
      await _pump(tester, repo: repo, profile: _profile());

      await tester.tap(find.byKey(const Key('onboarding_skip_button')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(drainLayoutFailure(tester), isNull);

      expect(find.byType(OnboardingFlow), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a re-emitting profile stream runs the tour ONCE',
        (tester) async {
      // userProfileProvider is a stream: without the latch the tour would be
      // pushed on top of itself.
      final controller = StreamController<UserProfile?>();
      addTearDown(controller.close);

      await _pump(
        tester,
        repo: _CapturingUserRepository(),
        profileStream: controller.stream,
      );

      for (var i = 0; i < 3; i++) {
        controller.add(_profile());
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(drainLayoutFailure(tester), isNull);
      }

      expect(find.byType(OnboardingFlow), findsOneWidget);
    });

    testWidgets('blocks other prompts while pending, releases after',
        (tester) async {
      // This is what defers the push-permission and location prompts.
      final container = ProviderContainer(
        overrides: [
          userRepositoryProvider.overrideWithValue(_CapturingUserRepository()),
          userProfileProvider.overrideWith((ref) => Stream.value(_profile())),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            locale: Locale('es', 'AR'),
            home: Scaffold(body: OnboardingGate()),
          ),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(drainLayoutFailure(tester), isNull);

      expect(container.read(onboardingBlocksProvider), isTrue);

      await tester.tap(find.byKey(const Key('onboarding_skip_button')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(drainLayoutFailure(tester), isNull);

      expect(container.read(onboardingBlocksProvider), isFalse);
    });
  });
}
