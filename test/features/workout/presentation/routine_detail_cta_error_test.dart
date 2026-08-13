// Regression tests for #497 — the periodized CTA bar used to hide the ENTIRE
// action when `planProgressProvider` errored.
//
// `_PeriodizedCTABar.build` wrapped the completion SIGNAL and the ACTION in one
// `progressAsync.when(error: SizedBox.shrink())`. Plan progress is only needed
// to decide the signal (banner/chip) and the button LABEL — it is not needed to
// start a workout, which only needs the routine and the day the parent already
// resolved. So an error there took away the one control the screen exists for.
//
// The original design (periodized-plan-repeat, tasks 1.8) treated `error` as "a
// state, not a gate" on the assumption it was transient. #497 showed it was not:
// `routineByIdProvider` cached the AsyncError for the container's lifetime, so
// the CTA stayed gone for good. That provider no longer caches failures, and
// this bar no longer withholds the action while it is failing.
//
// `skipOffstage: false` throughout — the CTA bar sits below the fold in the
// test viewport, same as the sibling periodized tests.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show userProfileProvider;
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider, sessionsByUidProvider;
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/presentation/routine_detail_screen.dart';

const _uid = 'u1';

UserProfile _athleteProfile() => UserProfile(
      uid: _uid,
      email: 'u1@test.com',
      displayName: 'Atleta',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Routine _periodizedRoutine() => const Routine(
      id: 'routine-p',
      name: 'Plan Periodizado',
      level: ExperienceLevel.intermediate,
      days: [
        RoutineDay(
          dayNumber: 1,
          name: 'Push',
          slots: [
            RoutineSlot(
              exerciseId: 'bench',
              exerciseName: 'Press de Banca',
              muscleGroup: 'Pecho',
              targetSets: 3,
              targetRepsMin: 8,
              targetRepsMax: 12,
              restSeconds: 90,
            ),
          ],
        ),
      ],
      numWeeks: 2,
    );

/// Same shape as the periodized harness, but `sessionsByUidProvider` fails so
/// `planProgressProvider` resolves to an error.
Widget _wrapWithFailingProgress(Routine routine) {
  return ProviderScope(
    overrides: [
      routineByIdStreamProvider(routine.id)
          .overrideWith((ref) => Stream.value(routine)),
      routineByIdProvider(routine.id).overrideWith((ref) async => routine),
      currentUidProvider.overrideWithValue(_uid),
      userProfileProvider
          .overrideWith((ref) => Stream.value(_athleteProfile())),
      sessionsByUidProvider(_uid)
          .overrideWith((ref) async => throw Exception('sin señal')),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: RoutineDetailScreen(routineId: routine.id)),
    ),
  );
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('SCENARIO-497-010 — periodized CTA survives a plan-progress error', () {
    testWidgets('the EMPEZAR action is still rendered and tappable',
        (tester) async {
      final routine = _periodizedRoutine();
      await tester.pumpWidget(_wrapWithFailingProgress(routine));
      await _settle(tester);

      expect(find.text('EMPEZAR', skipOffstage: false), findsOneWidget);

      final button = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'EMPEZAR', skipOffstage: false),
      );
      expect(
        button.onPressed,
        isNotNull,
        reason: 'a failed progress fetch must not disable the action',
      );
    });

    testWidgets(
        'no completion signal is shown while progress is unknown '
        '(the label falls back to EMPEZAR, never REPETIR)', (tester) async {
      final routine = _periodizedRoutine();
      await tester.pumpWidget(_wrapWithFailingProgress(routine));
      await _settle(tester);

      expect(find.text('REPETIR', skipOffstage: false), findsNothing);
      expect(find.text('PLAN COMPLETADO', skipOffstage: false), findsNothing);
      expect(find.text('COMPLETADO', skipOffstage: false), findsNothing);
    });
  });
}
