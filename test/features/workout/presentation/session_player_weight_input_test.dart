// Focused regression test for the weight-input stale-value bug in
// _RepsSetRow (_onWeightChanged) inside SessionPlayerScreen.
//
// Bug: clearing the weight field (empty -> parsed==null) or typing a value
// out of [0,500] left _weightKg at its previous value, so both the summary
// row text and the value logged on check reflected a stale weight instead of
// what the user saw/intended.
//
// Fix: empty/unparseable -> 0, out-of-range -> clamped to [0,500], with
// setState so the displayed summary stays in sync with what will be logged.

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

    // User clears the weight field.
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();

    // Summary now reflects 0 kg, not the stale 60.
    expect(find.textContaining('0 kg'), findsWidgets);

    // Tap the check circle to log the set.
    await tester.tap(find.byIcon(TreinoIcon.checkCircleEmpty));
    await tester.pump();

    expect(loggedWeight, 0.0);
  });

  testWidgets('out-of-range weight (>500) is clamped to 500 on log',
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

    await tester.enterText(find.byType(TextField), '600');
    await tester.pump();

    await tester.tap(find.byIcon(TreinoIcon.checkCircleEmpty));
    await tester.pump();

    expect(loggedWeight, 500.0);
  });
}
