// Vista previa del import en diseño neutro: un solo acento (sólo en lo que se
// toca), el estado de cada fila como marca chica con su label para el lector,
// una línea gris de datos por ejercicio y las superseries como UN bloque
// (encabezado, riel, A1/A2 y el descanso una sola vez).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/data/exercise_matcher.dart';
import 'package:treino/features/coach_hub/data/periodized_import_draft.dart';
import 'package:treino/features/coach_hub/domain/periodized_plan.dart';
import 'package:treino/features/coach_hub/presentation/widgets/periodized_plan_preview.dart';
import 'package:treino/features/workout/domain/set_enums.dart';
import 'package:treino/features/workout/domain/set_spec.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/l10n/app_l10n_es.dart';

import 'periodized_draft_fixtures.dart';

MatcherExercise _m(String id, String name) =>
    MatcherExercise(id: id, name: name, muscleGroup: 'x');

PeriodizedExercise _ex(int c, String name, {int reps = 8, String? note}) =>
    PeriodizedExercise(
      component: c,
      rawName: name,
      weeks: [
        [for (var i = 0; i < 3; i++) SetSpec(reps: reps)]
      ],
      note: note,
    );

ExerciseKey _k(int row, [int c = 0]) => (dayNumber: 1, row: row, component: c);

/// Día con: un simple, una superserie (2), un simple, una triserie (3) y un
/// circuito (4). Descansos distintos para poder buscarlos.
PeriodizedDay _blocksDay() => PeriodizedDay(dayNumber: 1, rows: [
      PeriodizedRow(
          position: 1,
          number: 1,
          restSeconds: 120,
          exercises: [_ex(0, 'Sentadilla')]),
      PeriodizedRow(position: 2, number: 2, restSeconds: 90, exercises: [
        _ex(0, 'Press militar', reps: 10),
        _ex(1, 'Dominadas', reps: 6),
      ]),
      PeriodizedRow(
          position: 3,
          number: 3,
          restSeconds: 60,
          exercises: [_ex(0, 'Hip thrust')]),
      PeriodizedRow(position: 4, number: 4, restSeconds: 75, exercises: [
        _ex(0, 'Curl'),
        _ex(1, 'Extensión'),
        _ex(2, 'Plancha'),
      ]),
      PeriodizedRow(position: 5, number: 5, restSeconds: 150, exercises: [
        _ex(0, 'Burpees'),
        _ex(1, 'Saltos'),
        _ex(2, 'Escaladores'),
        _ex(3, 'Sprint'),
      ]),
    ]);

/// Todos resueltos menos lo que se pase en [pending] (sugerencia) y
/// [noMatch] (sin nada).
PeriodizedImportDraft _draftFor(
  PeriodizedDay day, {
  Set<ExerciseKey> pending = const {},
  Set<ExerciseKey> noMatch = const {},
}) {
  final keys = [
    for (final r in day.rows)
      for (final e in r.exercises)
        (dayNumber: 1, row: r.position, component: e.component)
  ];
  return PeriodizedImportDraft(
    plan: PeriodizedPlan(numWeeks: 1, days: [day]),
    warnings: const [],
    name: 'p',
    assignments: {
      for (final k in keys)
        if (!pending.contains(k) && !noMatch.contains(k))
          k: _m(
              'id-${k.row}-${k.component}',
              day.rows
                  .firstWhere((r) => r.position == k.row)
                  .exercises[k.component]
                  .rawName),
    },
    suggestions: {
      for (final k in pending) k: _m('s-${k.row}', 'Sugerido ${k.row}')
    },
  );
}

Future<void> _pumpCard(
  WidgetTester tester,
  PeriodizedDay day,
  PeriodizedImportDraft draft, {
  bool collapse = false,
}) async {
  tester.view.physicalSize = const Size(500, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
          onPickManual: (_, __) {},
          onCreateCustom: (_, __) {},
          onUseAlternative: (_) {},
          collapseResolved: collapse,
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Colores de todos los textos (planos o rich) debajo de [of].
Iterable<Color?> _textColors(WidgetTester tester, Finder of) => [
      for (final t in tester.widgetList<Text>(
          find.descendant(of: of, matching: find.byType(Text))))
        t.style?.color ?? t.textSpan?.style?.color,
      for (final r in tester.widgetList<RichText>(
          find.descendant(of: of, matching: find.byType(RichText))))
        r.text.style?.color,
    ];

void main() {
  const palette = AppPalette.mintMagenta;

  group('bloques de varios ejercicios', () {
    testWidgets(
        'encabezado SUPERSERIE (2), TRISERIE (3) y CIRCUITO (4+) con el '
        'descanso al final', (tester) async {
      final day = _blocksDay();
      await _pumpCard(tester, day, _draftFor(day));

      expect(
          find.text('SUPERSERIE · 2 ejercicios · descanso 90 s al final',
              findRichText: true),
          findsOneWidget);
      expect(
          find.text('TRISERIE · 3 ejercicios · descanso 75 s al final',
              findRichText: true),
          findsOneWidget);
      expect(
          find.text('CIRCUITO · 4 ejercicios · descanso 2 min 30 s al final',
              findRichText: true),
          findsOneWidget);
      // El eslabón, una vez por bloque.
      expect(find.byIcon(TreinoIcon.supersetLink), findsNWidgets(3));
    });

    testWidgets(
        'el descanso va UNA vez, en el encabezado, no en cada componente',
        (tester) async {
      final day = _blocksDay();
      await _pumpCard(tester, day, _draftFor(day));

      // «90 s» aparece sólo en el encabezado de la superserie…
      expect(find.textContaining('90 s', findRichText: true), findsOneWidget);
      // …y los componentes llevan sólo sus series.
      expect(find.text('3 × 10'), findsOneWidget);
      expect(find.text('3 × 6'), findsOneWidget);
      // El simple sí lleva el suyo al final de su línea.
      expect(find.text('3 × 8 · 2 min'), findsOneWidget);
      expect(find.text('3 × 8 · 1 min'), findsOneWidget);
    });

    testWidgets(
        'A1/A2… por posición entre los bloques del día; los simples no '
        'gastan letra', (tester) async {
      final day = _blocksDay();
      await _pumpCard(tester, day, _draftFor(day));

      for (final p in ['A1', 'A2', 'B1', 'B2', 'B3', 'C1', 'C2', 'C3', 'C4']) {
        expect(find.text(p), findsOneWidget, reason: p);
      }
      expect(find.text('A3'), findsNothing);
      // A2 es Dominadas: el prefijo va en la fila de su componente.
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('ex-1-2-1')),
              matching: find.text('A2')),
          findsOneWidget);
    });

    testWidgets('el riel une los componentes, con un divisor entre cada uno',
        (tester) async {
      final day = _blocksDay();
      await _pumpCard(tester, day, _draftFor(day));

      final rail = find.byKey(const ValueKey('block-rail-1-4'));
      expect(rail, findsOneWidget);
      for (final c in [0, 1, 2]) {
        expect(
            find.descendant(
                of: rail, matching: find.byKey(ValueKey('ex-1-4-$c'))),
            findsOneWidget);
      }
      final deco = tester.widget<Container>(rail).decoration! as BoxDecoration;
      expect((deco.border! as Border).left.color, palette.borderStrong);
    });

    testWidgets('mobile: un componente plegado queda adentro del bloque',
        (tester) async {
      final day = _blocksDay();
      await _pumpCard(tester, day, _draftFor(day, pending: {_k(2)}),
          collapse: true);

      final rail = find.byKey(const ValueKey('block-rail-1-2'));
      expect(
          find.descendant(
              of: rail, matching: find.byKey(const ValueKey('ex-1-2-0'))),
          findsOneWidget);
      expect(
          find.descendant(
              of: rail,
              matching: find.byKey(const ValueKey('ex-folded-1-2-1'))),
          findsOneWidget);
      // Plegado, el componente conserva su A2 y no arrastra el descanso.
      expect(
          find.text('Dominadas  ·  3 × 6', findRichText: true), findsOneWidget);
    });
  });

  group('marca de estado', () {
    testWidgets('pendiente, sin match y resuelto, cada una con su label',
        (tester) async {
      final day = _blocksDay();
      await _pumpCard(
          tester, day, _draftFor(day, pending: {_k(1)}, noMatch: {_k(3)}));

      expect(find.bySemanticsLabel('sugerencia por confirmar'), findsOneWidget);
      expect(find.bySemanticsLabel('sin ejercicio de la biblioteca'),
          findsOneWidget);
      // Los otros 9 de los 11 componentes están resueltos.
      expect(find.bySemanticsLabel('Resuelto'), findsNWidgets(9));
      // Las pastillas viejas no están.
      expect(find.text('sugerencia pendiente'), findsNothing);
      expect(find.text('sin match'), findsNothing);
    });

    testWidgets('distinguibles sin color: punto lleno ámbar vs anillo hueco',
        (tester) async {
      final day = _blocksDay();
      await _pumpCard(
          tester, day, _draftFor(day, pending: {_k(1)}, noMatch: {_k(3)}));

      BoxDecoration decoOf(String key) {
        final mark = find.byKey(ValueKey(key));
        return tester
            .widget<Container>(
                find.descendant(of: mark, matching: find.byType(Container)))
            .decoration! as BoxDecoration;
      }

      final pending = decoOf('status-pending-${_k(1)}');
      expect(pending.shape, BoxShape.circle);
      expect(pending.color, palette.warning);
      expect(pending.border, isNull);

      final noMatch = decoOf('status-noMatch-${_k(3)}');
      expect(noMatch.shape, BoxShape.circle);
      expect(noMatch.color, isNull);
      expect((noMatch.border! as Border).top.color, palette.dangerText);
    });

    testWidgets('un resuelto lleva el ✓ gris y nada en acento', (tester) async {
      final day = _blocksDay();
      await _pumpCard(tester, day, _draftFor(day));

      final row = find.byKey(const ValueKey('ex-1-1-0'));
      final check = tester.widget<Icon>(
          find.descendant(of: row, matching: find.byIcon(TreinoIcon.check)));
      expect(check.color, palette.textFaint);
      expect(_textColors(tester, row), isNot(contains(palette.accentText)));
      expect(_textColors(tester, row), isNot(contains(palette.accent)));
    });

    testWidgets('en una fila pendiente, sólo «Confirmar» va en acento',
        (tester) async {
      final day = _blocksDay();
      await _pumpCard(tester, day, _draftFor(day, pending: {_k(1)}));

      final row = find.byKey(const ValueKey('ex-1-1-0'));
      final accentTexts = [
        for (final t in tester.widgetList<Text>(
            find.descendant(of: row, matching: find.byType(Text))))
          if (t.style?.color == palette.accentText) t.data,
      ];
      expect(accentTexts, ['Confirmar']);
      // La sugerencia, como dato gris con la flecha, y legible para el lector.
      expect(find.bySemanticsLabel('Sugerencia: Sugerido 1'), findsOneWidget);
      expect(
          tester
              .widget<Text>(
                  find.descendant(of: row, matching: find.text('Sugerido 1')))
              .style
              ?.color,
          palette.textMuted);
    });
  });

  group('línea de datos', () {
    final l10n = AppL10nEs();

    test('descanso compacto', () {
      expect(formatRestCompact(45), '45 s');
      expect(formatRestCompact(60), '1 min');
      expect(formatRestCompact(90), '90 s');
      expect(formatRestCompact(120), '2 min');
      expect(formatRestCompact(150), '2 min 30 s');
      expect(formatRestCompact(0), '');
    });

    test('series, carga, nota y descanso en un renglón con « · »', () {
      expect(
          exerciseDataLine([
            for (var i = 0; i < 4; i++)
              const SetSpec(repsMin: 8, repsMax: 10, weightKg: 60)
          ], l10n: l10n, restSeconds: 120),
          '4 × 8–10 · 60 kg · 2 min');
      expect(
          exerciseDataLine(
              [for (var i = 0; i < 3; i++) const SetSpec(reps: 12)],
              l10n: l10n, note: 'RIR 2', restSeconds: 60),
          '3 × 12 · RIR 2 · 1 min');
      expect(
          exerciseDataLine([
            for (var i = 0; i < 3; i++) const SetSpec(repsMin: 10, repsMax: 12)
          ], l10n: l10n, note: '16 kg c/u'),
          '3 × 10–12 · 16 kg c/u');
      expect(
          exerciseDataLine(const [
            SetSpec(type: SetType.failure),
            SetSpec(durationSeconds: 90),
            SetSpec(distanceMeters: 200),
          ], l10n: l10n),
          '3 series · al fallo · 1 min 30 s · 200 m');
    });

    test('blockLetter: A…Z y después AA', () {
      expect(blockLetter(0), 'A');
      expect(blockLetter(25), 'Z');
      expect(blockLetter(26), 'AA');
      expect(blockLetter(27), 'AB');
    });
  });

  group('aviso de pendientes', () {
    testWidgets('superficie neutra con una línea gris', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(
          body: PendingResolutionNotice(
              pendingSuggestions: 16, withoutSuggestion: 1),
        ),
      ));
      final text = tester.widget<Text>(
          find.text('16 sugerencias por confirmar · 1 sin match'));
      expect(text.style?.color, palette.textMuted);
    });
  });

  group('Coach Hub', () {
    testWidgets('dibuja el mismo bloque: encabezado, riel, A1/A2 y marcas',
        (tester) async {
      final day = _blocksDay();
      await pumpPreview(
          tester, _draftFor(day, pending: {_k(2, 0)}), MockRoutineRepo());

      expect(
          find.text('SUPERSERIE · 2 ejercicios · descanso 90 s al final',
              findRichText: true),
          findsOneWidget);
      final rail = find.byKey(const ValueKey('block-rail-1-2'));
      expect(rail, findsOneWidget);
      // El Hub no pliega: los dos componentes, desplegados, dentro del riel.
      for (final c in [0, 1]) {
        expect(
            find.descendant(
                of: rail, matching: find.byKey(ValueKey('ex-1-2-$c'))),
            findsOneWidget);
      }
      expect(find.byKey(const ValueKey('ex-folded-1-2-1')), findsNothing);
      expect(
          find.descendant(of: rail, matching: find.text('A1')), findsOneWidget);
      expect(
          find.descendant(of: rail, matching: find.text('A2')), findsOneWidget);
      expect(find.bySemanticsLabel('sugerencia por confirmar'), findsOneWidget);
      expect(find.byKey(const Key('hub_import_pending')), findsOneWidget);
      expect(find.text('1 sugerencia por confirmar'), findsOneWidget);
    });
  });
}
