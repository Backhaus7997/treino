// El editor nunca se queda mudo al agregar un ejercicio (#862, revisión en
// device del 01/09).
//
// El bug: elegir en el picker un ejercicio que el día YA tiene no hacía nada.
// `_addSupersetForDay` y `_pickExercisesForDay` filtraban los repetidos con un
// `return` mudo adentro del `setState`, y el usuario veía un botón que no
// respondía. Un ejercicio por día es invariante del dominio (QA-WKT-004): lo
// que faltaba no era permitirlo, era decirlo.
//
// La raíz: `showExercisePicker` acepta `alreadySelectedIds` para pre-marcar lo
// que el día ya tiene —está en ADR-RER-01— y ninguna de las tres llamadas del
// editor se lo pasaba.
//
// Lo que importa afirmar acá no es el parser —eso vive en
// `quick_entry_parser_test.dart`, sin widgets— sino que el ejercicio que entra
// por el atajo sea INDISTINGUIBLE de uno agregado por el picker, y que el
// picker siga estando.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/features/workout/application/custom_exercise_providers.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart'
    show routineRepositoryProvider;
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/application/user_routines_providers.dart'
    show userCreatedRoutinesProvider;
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/custom_exercise.dart';
import 'package:treino/features/workout/presentation/routine_editor_mode.dart';
import 'package:treino/features/workout/presentation/routine_editor_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

import 'package:treino/features/workout/presentation/widgets/exercise_card.dart';
import 'package:treino/features/workout/presentation/widgets/superset_block.dart';

import '../../../fixtures/exercises.dart';
import '../../../fixtures/routine_editor_ui.dart';
import '../../../helpers/fake_analytics_service.dart';

class _MockRoutineRepository extends Mock implements RoutineRepository {}

Future<void> _pumpEditor(WidgetTester tester) async {
  usarViewportAlto(tester);
  const uid = 'user-1';
  final router = GoRouter(
    initialLocation: '/workout/editor',
    routes: [
      GoRoute(
        path: '/workout/editor',
        pageBuilder: (context, state) => const NoTransitionPage(
          child: RoutineEditorScreen(mode: SelfCreating()),
        ),
      ),
      GoRoute(
        path: '/workout',
        pageBuilder: (_, __) => const NoTransitionPage(
          child: Scaffold(body: Center(child: Text('WorkoutHome'))),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue(uid),
        routineRepositoryProvider.overrideWithValue(_MockRoutineRepository()),
        exercisesProvider.overrideWith((ref) async => kExerciseSeed),
        customExercisesForTrainerStreamProvider(uid).overrideWith(
          (ref) => Stream<List<CustomExercise>>.value(const <CustomExercise>[]),
        ),
        analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
        userCreatedRoutinesProvider(uid).overrideWith(
          (ref) => Stream.value(const []),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  Future<void> agregarSuelto(WidgetTester tester, String nombre) async {
    await desplazarHastaAgregarEjercicio(tester);
    await tester.tap(find.text('Agregar ejercicio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(nombre).first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Agregar 1').first);
    await tester.pumpAndSettle();
  }

  Future<void> abrirSuperserie(WidgetTester tester) async {
    final boton = find.byKey(const Key('add_superset_button'));
    await desplazarHasta(tester, boton);
    await tester.tap(boton);
    await tester.pumpAndSettle();
  }

  testWidgets('dos ejercicios nuevos arman el bloque', (tester) async {
    await _pumpEditor(tester);
    await abrirSuperserie(tester);
    await tester.tap(find.text('Press de Banca').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Press Militar').first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Agregar 2').first);
    await tester.pumpAndSettle();

    expect(find.byType(SupersetBlock), findsOneWidget);
    expect(find.byType(ExerciseCard), findsNWidgets(2));
  });

  testWidgets('el picker llega con lo que el día ya tiene pre-marcado',
      (tester) async {
    // Es lo que evita el problema de raíz: el usuario VE que ese ejercicio ya
    // está, en vez de elegirlo y que no pase nada.
    await _pumpEditor(tester);
    await agregarSuelto(tester, 'Press de Banca');
    await abrirSuperserie(tester);

    expect(find.textContaining('Agregar 1'), findsWidgets,
        reason: 'el picker abre con un ejercicio ya seleccionado — el que el '
            'día tiene');
  });

  testWidgets('elegir SÓLO repetidos avisa en vez de quedarse mudo',
      (tester) async {
    await _pumpEditor(tester);
    await agregarSuelto(tester, 'Press de Banca');
    final antes = find.byType(ExerciseCard).evaluate().length;

    await abrirSuperserie(tester);
    // Viene pre-marcado; se confirma tal cual, sin sumar ninguno nuevo.
    await tester.tap(find.textContaining('Agregar 1').first);
    await tester.pumpAndSettle();

    expect(find.byType(ExerciseCard), findsNWidgets(antes),
        reason: 'un ejercicio por día es invariante (QA-WKT-004)');
    expect(find.text('Esos ejercicios ya estaban en el día.'), findsOneWidget,
        reason: 'ESTE es el bug reportado: antes no pasaba nada y el botón '
            'parecía roto');
  });

  testWidgets('un solo ejercicio nuevo entra suelto, no como superserie falsa',
      (tester) async {
    await _pumpEditor(tester);
    await abrirSuperserie(tester);
    await tester.tap(find.text('Press de Banca').first);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Agregar 1').first);
    await tester.pumpAndSettle();

    expect(find.byType(ExerciseCard), findsOneWidget,
        reason: 'el ejercicio entra: el usuario lo quería');
    expect(find.byType(SupersetBlock), findsNothing,
        reason: 'un bloque magenta con UN ejercicio adentro miente sobre lo '
            'que es');
    expect(
      find.textContaining('Una superserie necesita dos'),
      findsOneWidget,
      reason: 'y se dice por qué no quedó agrupado',
    );
  });
}
