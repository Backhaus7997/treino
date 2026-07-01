// Tests for editable reps on the active session player (2026-07-01).
//
// Before this change, the reps of a set were locked to the planned value
// (`repsMax` for rep ranges). The athlete had no way to record having done
// more or fewer reps than programmed. This suite covers:
//   - reps field pre-fills with plannedReps and can be edited before check
//   - the edited reps value is what gets logged on check (not the planned)
//   - clearing/typing 0 reps blocks the check (no zero-rep set created)
//   - the digits-only formatter rejects non-digit input
//   - rep-range specs (min/max) preload with repsMax but accept anything

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/workout/application/session_init.dart';
import 'package:treino/features/workout/application/session_notifier.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/application/session_state.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/features/workout/presentation/session_player_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../features/workout/application/stub_factories.dart';

/// Stub that captures the ENTIRE SetLog so tests can assert on both reps
/// and weight — the weight-only suite predates editable reps.
class _CapturingNotifier extends SessionNotifier {
  _CapturingNotifier(this._state, {required this.onLog});
  final SessionState _state;
  final void Function(SetLog log) onLog;

  int logCallCount = 0;

  @override
  Future<SessionState> build(SessionInit arg) async => _state;

  @override
  Future<void> logSet(SetLog setLog) async {
    logCallCount++;
    onLog(setLog);
  }
}

const _kInit = FreshSession(routineId: 'r1', dayNumber: 1);

Widget _wrap(Widget w, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(body: w),
      ),
    );

void main() {
  // A helper that returns a pending state with a single reps set. The spec
  // is derived from the slot's `targetRepsMin`/`targetRepsMax` — a single
  // number is expressed by passing both equal.
  SessionState pendingStateWith({
    int plannedReps = 10,
    int? repsMin,
    int? repsMax,
    double plannedWeight = 60.0,
  }) {
    return SessionState(
      session: makeSession(),
      day: makeDay(
        dayNumber: 1,
        slots: [
          makeSlot(
            exerciseId: 'e1',
            exerciseName: 'Press de banca',
            targetSets: 1,
            targetRepsMin: repsMin ?? plannedReps,
            targetRepsMax: repsMax ?? plannedReps,
            targetWeightKg: plannedWeight,
          ),
        ],
      ),
      setLogs: const [],
      currentExerciseIndex: 0,
      elapsedSeconds: 0,
    );
  }

  testWidgets(
      'reps field is prefilled with the planned reps on a pending row',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SessionPlayerScreen(init: _kInit),
        [
          sessionNotifierProvider.overrideWith(
            () => _CapturingNotifier(
              pendingStateWith(plannedReps: 10),
              onLog: (_) {},
            ),
          ),
        ],
      ),
    );
    await tester.pump();

    // Two TextFields in the current row: reps (first, left) + weight
    // (second, right). Reps prefilled with the planned value.
    final fields = tester.widgetList<TextField>(find.byType(TextField)).toList();
    expect(fields.length, greaterThanOrEqualTo(2));
    expect(fields.first.controller?.text, '10');
  });

  testWidgets(
      'editing reps before check → the check logs the EDITED value',
      (tester) async {
    SetLog? logged;
    await tester.pumpWidget(
      _wrap(
        const SessionPlayerScreen(init: _kInit),
        [
          sessionNotifierProvider.overrideWith(
            () => _CapturingNotifier(
              pendingStateWith(plannedReps: 10),
              onLog: (log) => logged = log,
            ),
          ),
        ],
      ),
    );
    await tester.pump();

    // Athlete did 8 reps instead of the planned 10.
    await tester.enterText(find.byType(TextField).first, '8');
    await tester.pump();

    await tester.tap(find.byIcon(TreinoIcon.checkCircleEmpty));
    await tester.pump();

    expect(logged, isNotNull);
    expect(logged!.reps, 8);
    expect(logged!.weightKg, 60.0);
  });

  testWidgets(
      'athlete can log MORE reps than planned — range is a hint, not a jail',
      (tester) async {
    SetLog? logged;
    await tester.pumpWidget(
      _wrap(
        const SessionPlayerScreen(init: _kInit),
        [
          sessionNotifierProvider.overrideWith(
            () => _CapturingNotifier(
              pendingStateWith(repsMin: 8, repsMax: 12, plannedWeight: 60),
              onLog: (log) => logged = log,
            ),
          ),
        ],
      ),
    );
    await tester.pump();

    // Range prefills with repsMax (12). Athlete blew past it to 15.
    await tester.enterText(find.byType(TextField).first, '15');
    await tester.pump();

    await tester.tap(find.byIcon(TreinoIcon.checkCircleEmpty));
    await tester.pump();

    expect(logged, isNotNull);
    expect(logged!.reps, 15);
  });

  testWidgets(
      'clearing reps → check is a no-op (no zero-rep set logged)',
      (tester) async {
    SetLog? logged;
    late _CapturingNotifier notifier;
    await tester.pumpWidget(
      _wrap(
        const SessionPlayerScreen(init: _kInit),
        [
          sessionNotifierProvider.overrideWith(() {
            notifier = _CapturingNotifier(
              pendingStateWith(plannedReps: 10),
              onLog: (log) => logged = log,
            );
            return notifier;
          }),
        ],
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();

    await tester.tap(find.byIcon(TreinoIcon.checkCircleEmpty));
    await tester.pump();

    expect(logged, isNull, reason: 'zero-rep sets must not be logged');
    expect(notifier.logCallCount, 0);
  });

  testWidgets(
      'reps field rejects non-digit input via digitsOnly formatter',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SessionPlayerScreen(init: _kInit),
        [
          sessionNotifierProvider.overrideWith(
            () => _CapturingNotifier(
              pendingStateWith(plannedReps: 10),
              onLog: (_) {},
            ),
          ),
        ],
      ),
    );
    await tester.pump();

    // Non-digit chars are filtered out by FilteringTextInputFormatter.
    // The formatter runs on each keystroke; pasting "abc" leaves the field
    // empty, and "1a2b3" resolves to "123".
    await tester.enterText(find.byType(TextField).first, 'abc');
    await tester.pump();
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields.first.controller?.text, '');

    await tester.enterText(find.byType(TextField).first, '1a2b3');
    await tester.pump();
    final updated = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(updated.first.controller?.text, '123');
  });

  testWidgets(
      'reps field caps at 3 digits (max 999)',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const SessionPlayerScreen(init: _kInit),
        [
          sessionNotifierProvider.overrideWith(
            () => _CapturingNotifier(
              pendingStateWith(plannedReps: 10),
              onLog: (_) {},
            ),
          ),
        ],
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, '9999');
    await tester.pump();
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields.first.controller?.text, '999');
  });
}
