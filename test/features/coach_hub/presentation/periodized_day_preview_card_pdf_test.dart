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
}
