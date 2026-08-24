// #645 — TimeFitSheet: el atleta declara cuánto tiempo tiene y la app le
// PROPONE qué sacar. La decisión final es siempre suya.
//
// Los ejercicios de estos tests usan `durationSeconds` + `restSeconds: 0` para
// que cada uno valga exactamente los minutos que dice y los números de la hoja
// se lean de un vistazo.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/presentation/widgets/time_fit_sheet.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../application/stub_factories.dart';

RoutineSlot _slot(String id, String name, int minutes) => makeSlot(
      exerciseId: id,
      exerciseName: name,
      targetSets: 1,
      restSeconds: 0,
      durationSeconds: minutes * 60,
    );

/// Tres ejercicios de 10 minutos: la sesión completa son 30.
RoutineDay _day() => makeDay(dayNumber: 1, slots: [
      _slot('e1', 'Press de banca', 10),
      _slot('e2', 'Sentadilla', 10),
      _slot('e3', 'Remo con barra', 10),
    ]);

Future<void> _pumpSheet(
  WidgetTester tester, {
  required void Function(List<String>) onApply,
  Set<String> lockedExerciseIds = const {},
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      locale: const Locale('es', 'AR'),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: Scaffold(
        body: TimeFitSheet(
          day: _day(),
          week: 0,
          lockedExerciseIds: lockedExerciseIds,
          onApply: onApply,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('TimeFitSheet', () {
    testWidgets('arranca mostrando cuánto dura la sesión y sin propuesta',
        (tester) async {
      await _pumpSheet(tester, onApply: (_) {});
      expect(find.text('Esta sesión son ~30 min'), findsOneWidget);
      expect(find.textContaining('Si sacás esto'), findsNothing);
      // Todas las franjas disponibles, ninguna elegida todavía.
      for (final choice in kTimeFitChoices) {
        expect(find.text('$choice min'), findsOneWidget);
      }
    });

    testWidgets('una franja corta propone sacar los últimos del día',
        (tester) async {
      await _pumpSheet(tester, onApply: (_) {});
      await tester.tap(find.text('20 min'));
      await tester.pumpAndSettle();

      expect(
        find.text('Si sacás esto, la sesión queda en ~20 min:'),
        findsOneWidget,
      );
      expect(find.text('Remo con barra'), findsOneWidget);
    });

    testWidgets('elegir una franja NO aplica nada — la app sugiere',
        (tester) async {
      List<String>? applied;
      await _pumpSheet(tester, onApply: (ids) => applied = ids);
      await tester.tap(find.text('20 min'));
      await tester.pumpAndSettle();
      expect(applied, isNull);
    });

    testWidgets('una franja que ya entra no propone recorte y deja el CTA off',
        (tester) async {
      await _pumpSheet(tester, onApply: (_) {});
      await tester.tap(find.text('45 min'));
      await tester.pumpAndSettle();

      expect(
        find.text('Con 45 min ya entrás. No hace falta sacar nada.'),
        findsOneWidget,
      );
      final apply = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('AJUSTAR HOY'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(apply.onPressed, isNull, reason: 'no hay nada que aplicar');
    });

    testWidgets(
        'no propone sacar un ejercicio con series hechas ni lo que quedó '
        'detrás', (tester) async {
      await _pumpSheet(
        tester,
        onApply: (_) {},
        lockedExerciseIds: const {'e3'},
      );
      await tester.tap(find.text('20 min'));
      await tester.pumpAndSettle();

      expect(
        find.text('No hay nada que sacar sin dejar la sesión vacía.'),
        findsOneWidget,
      );
    });

    testWidgets('AJUSTAR HOY entrega los ids propuestos', (tester) async {
      List<String>? applied;
      await _pumpSheet(tester, onApply: (ids) => applied = ids);
      await tester.tap(find.text('20 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('AJUSTAR HOY'));
      await tester.pumpAndSettle();

      expect(applied, equals(['e3']));
    });

    testWidgets('cambiar de franja recalcula la propuesta', (tester) async {
      await _pumpSheet(tester, onApply: (_) {});
      await tester.tap(find.text('20 min'));
      await tester.pumpAndSettle();
      expect(find.text('Remo con barra'), findsOneWidget);

      await tester.tap(find.text('30 min'));
      await tester.pumpAndSettle();
      expect(
        find.text('Con 30 min ya entrás. No hace falta sacar nada.'),
        findsOneWidget,
      );
      expect(find.text('Remo con barra'), findsNothing);
    });
  });
}
