// Lo que la tarjeta de día suma para el PDF: el texto fuente plegado, la
// alternativa del extractor (sólo si la pantalla la ofrece) y que el chip de
// estado baje de renglón en vez de desbordar.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/data/exercise_matcher.dart';
import 'package:treino/features/coach_hub/data/periodized_import_draft.dart';
import 'package:treino/features/coach_hub/domain/periodized_plan.dart';
import 'package:treino/features/coach_hub/presentation/widgets/periodized_plan_preview.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/workout/domain/set_enums.dart';
import 'package:treino/features/workout/domain/set_spec.dart';
import 'package:treino/l10n/app_l10n.dart';

const _key = (dayNumber: 1, row: 1, component: 0);
final _remo =
    MatcherExercise(id: 'r', name: 'Remo con barra', muscleGroup: 'back');
final _remoM =
    MatcherExercise(id: 'rm', name: 'Remo con mancuerna', muscleGroup: 'back');

PeriodizedDay _day(String name, {String? src}) =>
    PeriodizedDay(dayNumber: 1, rows: [
      PeriodizedRow(position: 1, number: 1, restSeconds: 60, exercises: [
        PeriodizedExercise(
          component: 0,
          rawName: name,
          weeks: const [
            [SetSpec(reps: 8)]
          ],
          sourceText: src,
        ),
      ]),
    ]);

PeriodizedImportDraft _draft(PeriodizedDay day) => PeriodizedImportDraft(
      plan: PeriodizedPlan(numWeeks: 1, days: [day]),
      warnings: const [],
      name: 'p',
      assignments: const {},
      suggestions: {_key: _remo},
      alternatives: {_key: _remoM},
    );

/// Sentadilla 5×5 a 80 kg, ya resuelta (confirmada).
PeriodizedDay _squatDay() => PeriodizedDay(dayNumber: 1, rows: [
      PeriodizedRow(position: 1, number: 1, restSeconds: 120, exercises: [
        PeriodizedExercise(
          component: 0,
          rawName: 'Sentadilla trasera',
          weeks: [
            [for (var i = 0; i < 5; i++) const SetSpec(reps: 5, weightKg: 80)]
          ],
          sourceText: 'Sentadilla trasera 5x5 80kg',
        ),
      ]),
    ]);

final _squat = MatcherExercise(
    id: 'sq', name: 'Sentadilla (Barra)', muscleGroup: 'quadriceps');

PeriodizedImportDraft _resolvedSquat() => PeriodizedImportDraft(
      plan: PeriodizedPlan(numWeeks: 1, days: [_squatDay()]),
      warnings: const [],
      name: 'p',
      assignments: {_key: _squat},
      suggestions: const {},
    );

Future<List<ExerciseKey>> _pumpCard(
  WidgetTester tester,
  PeriodizedDay day,
  PeriodizedImportDraft draft, {
  required bool collapse,
}) async {
  final picked = <ExerciseKey>[];
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark(),
    localizationsDelegates: AppL10n.localizationsDelegates,
    supportedLocales: AppL10n.supportedLocales,
    locale: const Locale('es', 'AR'),
    home: Scaffold(
      body: SingleChildScrollView(
        child: PeriodizedDayPreviewCard(
          day: day,
          week: 0,
          draft: draft,
          onConfirmSuggestion: (_) {},
          onPickManual: (k, _) => picked.add(k),
          onCreateCustom: (_, __) {},
          onUseAlternative: (_) {},
          collapseResolved: collapse,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return picked;
}

Future<List<ExerciseKey>> _pump(
  WidgetTester tester,
  PeriodizedDay day, {
  bool offerAlternative = true,
  double width = 400,
}) async {
  final used = <ExerciseKey>[];
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark(),
    localizationsDelegates: AppL10n.localizationsDelegates,
    supportedLocales: AppL10n.supportedLocales,
    locale: const Locale('es', 'AR'),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: width,
          child: SingleChildScrollView(
            child: PeriodizedDayPreviewCard(
              day: day,
              week: 0,
              draft: _draft(day),
              onConfirmSuggestion: (_) {},
              onPickManual: (_, __) {},
              onCreateCustom: (_, __) {},
              onUseAlternative: offerAlternative ? used.add : null,
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return used;
}

void main() {
  testWidgets('el texto del PDF arranca plegado y se despliega',
      (tester) async {
    await _pump(tester, _day('Remo', src: 'Remo 4x8 c/ pausa'));
    expect(find.text('Remo 4x8 c/ pausa'), findsNothing);

    await tester.tap(find.text('Ver texto del PDF'));
    await tester.pumpAndSettle();
    expect(find.text('Remo 4x8 c/ pausa'), findsOneWidget);
  });

  testWidgets('sin texto fuente (Excel) no hay nada que desplegar',
      (tester) async {
    await _pump(tester, _day('Remo'));
    expect(find.text('Ver texto del PDF'), findsNothing);
  });

  testWidgets('la alternativa se muestra y «Usar alternativa» avisa la clave',
      (tester) async {
    final used = await _pump(tester, _day('Remo'));
    expect(find.text('Alternativa: Remo con mancuerna'), findsOneWidget);

    await tester.tap(find.text('Usar alternativa'));
    expect(used, [_key]);
  });

  testWidgets('sin callback (Coach Hub) la alternativa no aparece',
      (tester) async {
    await _pump(tester, _day('Remo'), offerAlternative: false);
    expect(find.textContaining('Alternativa'), findsNothing);
    expect(find.text('Usar alternativa'), findsNothing);
  });

  testWidgets('angosto y con letra grande el chip de estado no desborda',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(tester, _day('Press inclinado con mancuernas y pausa'),
        width: 240);

    expect(tester.takeException(), isNull);
    expect(find.text('sugerencia pendiente'), findsOneWidget);
  });

  group('resuelto plegado (mobile)', () {
    const line = 'Sentadilla (Barra)  ·  5 × 5 · 80 kg';

    testWidgets('UNA línea: ejercicio de la biblioteca, series con carga y ✓',
        (tester) async {
      await _pumpCard(tester, _squatDay(), _resolvedSquat(), collapse: true);

      expect(find.text(line, findRichText: true), findsOneWidget);
      expect(find.byIcon(TreinoIcon.check), findsOneWidget);
      // Plegado: ni acciones, ni texto del PDF, ni el chip del descanso.
      expect(find.text('Cambiar'), findsNothing);
      expect(find.text('Ver texto del PDF'), findsNothing);
      expect(find.text('Descanso 120 s'), findsNothing);
    });

    testWidgets('tocarla la despliega con «Cambiar» y el texto del PDF',
        (tester) async {
      final picked = await _pumpCard(tester, _squatDay(), _resolvedSquat(),
          collapse: true);

      await tester.tap(find.text(line, findRichText: true));
      await tester.pumpAndSettle();

      expect(find.text('Sentadilla (Barra)'), findsOneWidget);
      expect(find.text('5 × 5 · 80 kg'), findsOneWidget);
      expect(find.text('Ver texto del PDF'), findsOneWidget);
      expect(find.text('Descanso 120 s'), findsOneWidget);
      await tester.tap(find.text('Cambiar'));
      expect(picked, [_key]);

      // El encabezado la vuelve a plegar.
      await tester.tap(find.text('Sentadilla (Barra)'));
      await tester.pumpAndSettle();
      expect(find.text(line, findRichText: true), findsOneWidget);
    });

    testWidgets('lo que pide atención no se pliega', (tester) async {
      await _pumpCard(tester, _day('Remo'), _draft(_day('Remo')),
          collapse: true);
      expect(find.text('sugerencia pendiente'), findsOneWidget);
      expect(find.text('Confirmar'), findsOneWidget);
    });

    testWidgets('sin collapseResolved (Coach Hub) se ve como siempre',
        (tester) async {
      await _pumpCard(tester, _squatDay(), _resolvedSquat(), collapse: false);

      expect(find.text(line, findRichText: true), findsNothing);
      expect(find.text('Sentadilla (Barra)'), findsOneWidget);
      expect(find.text('5 × 5 · 80 kg'), findsOneWidget);
      expect(find.text('Descanso 120 s'), findsOneWidget);
      expect(find.text('Cambiar'), findsNothing);
    });
  });

  group('describeWeekSets', () {
    test('la carga va pegada a su grupo, con coma decimal', () {
      expect(
          describeWeekSets([
            for (var i = 0; i < 5; i++) const SetSpec(reps: 5, weightKg: 80)
          ]),
          '5 × 5 · 80 kg');
      expect(
          describeWeekSets(const [
            SetSpec(reps: 10, weightKg: 60),
            SetSpec(reps: 8, weightKg: 62.5),
          ], localeName: 'es_AR'),
          '1 × 10 · 60 kg + 1 × 8 · 62,5 kg');
    });

    test('sin carga (o en 0) queda como antes', () {
      expect(
          describeWeekSets(const [
            SetSpec(reps: 8),
            SetSpec(reps: 8),
            SetSpec(reps: 8, weightKg: 0),
          ]),
          '3 × 8');
    });

    test('el rango se muestra en vez de «N series»', () {
      expect(
          describeWeekSets(const [
            SetSpec(repsMin: 8, repsMax: 10, weightKg: 60),
            SetSpec(repsMin: 8, repsMax: 10, weightKg: 60),
          ]),
          '2 × 8–10 · 60 kg');
    });

    test('al fallo con carga: la cantidad y el peso', () {
      expect(
          describeWeekSets(
              const [SetSpec(type: SetType.failure, weightKg: 50)]),
          '1 serie · 50 kg');
    });
  });
}
