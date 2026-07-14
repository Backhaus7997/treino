import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/insights/presentation/exercise_progression_screen.dart';
import 'package:treino/features/workout/application/exercise_progression_providers.dart';
import 'package:treino/features/workout/domain/exercise_progression.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_progression_chart.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_progression_section.dart';
import 'package:treino/l10n/app_l10n.dart';

ExerciseListEntry _e(String id, String name) =>
    ExerciseListEntry(exerciseId: id, exerciseName: name);

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
}
