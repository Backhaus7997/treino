// Focused regression test for the weight-input stale-value bug in
// _RepsSetRow (_onWeightChanged) inside SessionPlayerScreen.
//
// Bug: clearing the weight field (empty -> parsed==null) left _weightKg at its
// previous value; and an out-of-range value (>500) was silently clamped only on
// log while the field kept showing the typed number, so what the athlete saw
// diverged from what got logged (QA-WKT-002).
//
// Fix: empty/unparseable -> 0 with setState (summary stays in sync); and a
// BoundedNumberFormatter now rejects any keystroke over the 500 kg cap at the
// source, so the field can never display a value that differs from what is
// logged.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/application/session_init.dart';
import 'package:treino/features/workout/application/session_notifier.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/application/session_state.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/workout/presentation/session_player_screen.dart';

import '../../../features/workout/application/stub_factories.dart';

// Stub notifier that captures the weight passed to logSet without running
// real Firestore logic.
class _CapturingNotifier extends SessionNotifier {
  _CapturingNotifier(this._state, {required this.onLog});
  final SessionState _state;
  final void Function(double weightKg) onLog;

  @override
  Future<SessionState> build(SessionInit arg) async => _state;

  @override
  Future<void> logSet(SetLog setLog) async => onLog(setLog.weightKg);
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
  // One pending current reps-set with planned weight 60kg, no logs yet.
  // The current row auto-expands, so its weight TextField is visible.
  SessionState pendingState() => SessionState(
        session: makeSession(),
        day: makeDay(
          dayNumber: 1,
          slots: [
            makeSlot(
              exerciseId: 'e1',
              exerciseName: 'Press de banca',
              targetSets: 1,
              targetWeightKg: 60.0,
            ),
          ],
        ),
        setLogs: const [],
        currentExerciseIndex: 0,
        elapsedSeconds: 0,
      );

  testWidgets(
      'cleared weight field logs 0, not the stale planned weight',
      (tester) async {
    double? loggedWeight;
    await tester.pumpWidget(
      _wrap(
        const SessionPlayerScreen(init: _kInit),
        [
          sessionNotifierProvider.overrideWith(
            () => _CapturingNotifier(
              pendingState(),
              onLog: (w) => loggedWeight = w,
            ),
          ),
        ],
      ),
    );
    await tester.pump();

    // Sanity: the field starts pre-filled with the planned weight.
    expect(find.text('60'), findsWidgets);

    // User clears the weight field. The row now has TWO TextFields (reps +
    // weight); weight is the second one — same visual order (reps on the
    // left, weight on the right).
    await tester.enterText(find.byType(TextField).last, '');
    await tester.pump();

    // Summary now reflects 0 kg, not the stale 60.
    expect(find.textContaining('0 kg'), findsWidgets);

    // Tap the check circle to log the set.
    await tester.tap(find.byIcon(TreinoIcon.checkCircleEmpty));
    await tester.pump();

    expect(loggedWeight, 0.0);
  });

  testWidgets(
      'weight over the 500 cap is rejected at input; the field and the log '
      'never diverge', (tester) async {
    double? loggedWeight;
    await tester.pumpWidget(
      _wrap(
        const SessionPlayerScreen(init: _kInit),
        [
          sessionNotifierProvider.overrideWith(
            () => _CapturingNotifier(
              pendingState(),
              onLog: (w) => loggedWeight = w,
            ),
          ),
        ],
      ),
    );
    await tester.pump();

    // Weight field is the second TextField (row now has reps + weight).
    final weightField = find.byType(TextField).last;

    // Exactly the cap is accepted.
    await tester.enterText(weightField, '500');
    await tester.pump();
    expect(find.textContaining('500 kg'), findsWidgets);

    // An over-cap value is rejected at the source: the field keeps the last
    // valid value (500) instead of showing 600, so display == what gets logged.
    await tester.enterText(weightField, '600');
    await tester.pump();
    expect(find.text('600'), findsNothing);

    await tester.tap(find.byIcon(TreinoIcon.checkCircleEmpty));
    await tester.pump();

    // Logged value matches what the field showed (500), never the rejected 600.
    expect(loggedWeight, 500.0);
  });
}
