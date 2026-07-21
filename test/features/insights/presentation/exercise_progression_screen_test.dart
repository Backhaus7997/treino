import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/insights/domain/chart_period.dart';
import 'package:treino/features/insights/presentation/exercise_progression_screen.dart';
import 'package:treino/features/workout/application/exercise_progression_providers.dart';
import 'package:treino/features/workout/domain/exercise_progression.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_progression_chart.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_progression_section.dart';
import 'package:treino/l10n/app_l10n.dart';

ExerciseListEntry _e(String id, String name,
        {Set<ChartPeriod> periods = const {}}) =>
    ExerciseListEntry(
        exerciseId: id, exerciseName: name, periodsWithData: periods);

/// 14 ejercicios logueados — a propósito por encima de [kPickerChipCap] (10),
/// para que el recorte de chips sea observable.
final _many = [
  _e('e1', 'Press banca'),
  _e('e2', 'Sentadilla'),
  _e('e3', 'Peso muerto'),
  _e('e4', 'Remo con barra'),
  _e('e5', 'Press militar'),
  _e('e6', 'Dominadas'),
  _e('e7', 'Curl de bíceps'),
  _e('e8', 'Extensión de tríceps'),
  _e('e9', 'Prensa'),
  _e('e10', 'Elevaciones laterales'),
  _e('e11', 'Zancadas'),
  _e('e12', 'Face pull'),
  _e('e13', 'Hip thrust'),
  _e('e14', 'Curl femoral'),
];

Widget _wrap({
  required List<Override> overrides,
  String? initialExerciseId,
}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(
          body: ExerciseProgressionScreen(
            uid: 'u1',
            initialExerciseId: initialExerciseId,
          ),
        ),
      ),
    );

void main() {
  testWidgets('renderiza el buscador — la pantalla del alumno lo pide',
      (tester) async {
    await tester.pumpWidget(_wrap(overrides: [
      athleteExerciseListProvider('u1').overrideWith((ref) async => _many),
    ]));
    await tester.pumpAndSettle();

    // UNA sola vez: el header de la pantalla. La sección NO repite el título
    // (sectionTitle: null) — en el shell del coach sí lo lleva, porque ahí
    // convive con otras secciones.
    expect(find.text('EVOLUCIÓN POR EJERCICIO'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Buscar ejercicio…'), findsOneWidget);
  });

  testWidgets(
      'con el buscador vacío la chip row se recorta a kPickerChipCap — no el '
      'carrusel infinito de antes', (tester) async {
    await tester.pumpWidget(_wrap(overrides: [
      athleteExerciseListProvider('u1').overrideWith((ref) async => _many),
    ]));
    await tester.pumpAndSettle();

    // Los primeros 10 sí; el 11º en adelante, no.
    expect(find.text('Press banca'), findsOneWidget); // #1
    expect(find.text('Elevaciones laterales'), findsOneWidget); // #10
    expect(find.text('Zancadas'), findsNothing); // #11
    expect(find.text('Curl femoral'), findsNothing); // #14
  });

  testWidgets(
      'tipear filtra SOBRE LOS EJERCICIOS PROPIOS y alcanza los ocultos',
      (tester) async {
    await tester.pumpWidget(_wrap(overrides: [
      athleteExerciseListProvider('u1').overrideWith((ref) async => _many),
    ]));
    await tester.pumpAndSettle();

    // 'Curl femoral' es el #14 — fuera del cap, invisible sin buscar.
    expect(find.text('Curl femoral'), findsNothing);

    await tester.enterText(find.byType(TextField), 'femoral');
    await tester.pumpAndSettle();

    expect(find.text('Curl femoral'), findsOneWidget);
    // Y los que no matchean desaparecen.
    expect(find.text('Press banca'), findsNothing);
  });

  testWidgets('la búsqueda tolera acentos (foldSearch)', (tester) async {
    await tester.pumpWidget(_wrap(overrides: [
      athleteExerciseListProvider('u1').overrideWith((ref) async => _many),
    ]));
    await tester.pumpAndSettle();

    // Sin tilde en la query, con tilde en el nombre ('Curl de bíceps').
    await tester.enterText(find.byType(TextField), 'biceps');
    await tester.pumpAndSettle();

    expect(find.text('Curl de bíceps'), findsOneWidget);
  });

  testWidgets('sin coincidencias → mensaje que aclara que busca en LO TUYO',
      (tester) async {
    await tester.pumpWidget(_wrap(overrides: [
      athleteExerciseListProvider('u1').overrideWith((ref) async => _many),
    ]));
    await tester.pumpAndSettle();

    // Existe en el catálogo pero el atleta nunca lo entrenó → no tiene
    // progresión, y por diseño NO aparece (ése es el ADR).
    await tester.enterText(find.byType(TextField), 'burpee');
    await tester.pumpAndSettle();

    expect(
      find.text('Ningún ejercicio tuyo coincide con la búsqueda.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'initialExerciseId preselecciona — es como llega desde "Ejercicios '
      'frecuentes"', (tester) async {
    await tester.pumpWidget(_wrap(
      overrides: [
        athleteExerciseListProvider('u1').overrideWith((ref) async => _many),
      ],
      // 'Peso muerto', que NO es el default (el default sería el primero).
      initialExerciseId: 'e3',
    ));
    await tester.pumpAndSettle();

    final row =
        tester.widget<ExercisePickerRow>(find.byType(ExercisePickerRow));
    expect(row.selectedId, 'e3');
  });

  // ── #377 — preselección acotada por el período activo ──────────────────────

  String selectedChip(WidgetTester tester) => tester
      .widget<ExercisePickerRow>(find.byType(ExercisePickerRow))
      .selectedId!;

  Future<void> switchPeriod(
      WidgetTester tester, String fromLabel, String toLabel) async {
    await tester.tap(find.text(fromLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text(toLabel).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
      '#377: abre preseleccionando el más reciente CON datos en el período — '
      'no el primero global', (tester) async {
    // e1 y e2 (los más recientes) quedaron fuera de la ventana default
    // last30d; e3 es el más reciente con datos adentro. Antes del fix la
    // pantalla abría en e1 con el chart en "Sin datos para este ejercicio.".
    await tester.pumpWidget(_wrap(overrides: [
      athleteExerciseListProvider('u1').overrideWith((ref) async => [
            _e('e1', 'Press banca'),
            _e('e2', 'Sentadilla'),
            _e('e3', 'Peso muerto', periods: {ChartPeriod.last30d}),
          ]),
    ]));
    await tester.pumpAndSettle();

    expect(selectedChip(tester), 'e3');
    // Membership intacta: e1 sigue disponible en el picker.
    expect(find.text('Press banca'), findsOneWidget);
  });

  testWidgets(
      '#377: si NINGÚN ejercicio tiene datos en el período, cae al más '
      'reciente global (default histórico)', (tester) async {
    await tester.pumpWidget(_wrap(overrides: [
      athleteExerciseListProvider('u1').overrideWith((ref) async => [
            _e('e1', 'Press banca'),
            _e('e2', 'Sentadilla'),
          ]),
    ]));
    await tester.pumpAndSettle();

    expect(selectedChip(tester), 'e1');
  });

  testWidgets('#377: al cambiar el período la preselección se re-acota',
      (tester) async {
    await tester.pumpWidget(_wrap(overrides: [
      athleteExerciseListProvider('u1').overrideWith((ref) async => [
            _e('e1', 'Press banca', periods: {ChartPeriod.last30d}),
            _e('e2', 'Sentadilla',
                periods: {ChartPeriod.last30d, ChartPeriod.thisWeek}),
          ]),
    ]));
    await tester.pumpAndSettle();

    expect(selectedChip(tester), 'e1');

    // Esta semana: e1 queda sin datos → preselección salta a e2.
    await switchPeriod(tester, 'Últimos 30 días', 'Esta semana');
    expect(selectedChip(tester), 'e2');

    // De vuelta a 30 días: sin selección explícita, vuelve el default (e1).
    await switchPeriod(tester, 'Esta semana', 'Últimos 30 días');
    expect(selectedChip(tester), 'e1');
  });

  testWidgets(
      '#377: la selección explícita se respeta en su período, se re-acota al '
      'cambiar y se recuerda al volver', (tester) async {
    await tester.pumpWidget(_wrap(overrides: [
      athleteExerciseListProvider('u1').overrideWith((ref) async => [
            _e('e1', 'Press banca', periods: {ChartPeriod.last30d}),
            _e('e2', 'Sentadilla', periods: {ChartPeriod.last30d}),
            _e('e3', 'Peso muerto', periods: {ChartPeriod.thisWeek}),
          ]),
    ]));
    await tester.pumpAndSettle();

    // Elección explícita del usuario en last30d.
    await tester.tap(find.text('Sentadilla'));
    await tester.pumpAndSettle();
    expect(selectedChip(tester), 'e2');

    // Esta semana: e2 quedó sin datos → preselección acotada (e3)…
    await switchPeriod(tester, 'Últimos 30 días', 'Esta semana');
    expect(selectedChip(tester), 'e3');

    // …pero la elección NO se olvida: volver a 30 días la restaura.
    await switchPeriod(tester, 'Esta semana', 'Últimos 30 días');
    expect(selectedChip(tester), 'e2');
  });

  testWidgets(
      '#377: si el preseleccionado cae más allá del cap de chips, entra a la '
      'fila igual (reemplaza al último) — el chart no nombra al ejercicio en '
      'ningún otro lado', (tester) async {
    // Los 14 de _many no tienen datos en last30d; el único con datos es el
    // #14 ('Curl femoral'), que el cap posicional de 10 dejaría invisible.
    final manyWithOldTail = [
      for (final e in _many.take(13)) e,
      _e('e14', 'Curl femoral', periods: {ChartPeriod.last30d}),
    ];

    await tester.pumpWidget(_wrap(overrides: [
      athleteExerciseListProvider('u1')
          .overrideWith((ref) async => manyWithOldTail),
    ]));
    await tester.pumpAndSettle();

    // Preseleccionado Y visible como chip…
    expect(selectedChip(tester), 'e14');
    expect(find.text('Curl femoral'), findsOneWidget);
    // …a costa del último del cap (#10), no de los más recientes.
    expect(find.text('Elevaciones laterales'), findsNothing);
    expect(find.text('Press banca'), findsOneWidget); // #1 sigue
  });

  testWidgets(
      '#377: tocar un chip sin datos en el período activo SÍ se respeta — '
      'el empty state es respuesta a una acción, no un estado de apertura',
      (tester) async {
    await tester.pumpWidget(_wrap(overrides: [
      athleteExerciseListProvider('u1').overrideWith((ref) async => [
            _e('e1', 'Press banca', periods: {ChartPeriod.last30d}),
            _e('e2', 'Sentadilla'),
          ]),
    ]));
    await tester.pumpAndSettle();

    expect(selectedChip(tester), 'e1');

    await tester.tap(find.text('Sentadilla'));
    await tester.pumpAndSettle();
    expect(selectedChip(tester), 'e2');
  });
}
