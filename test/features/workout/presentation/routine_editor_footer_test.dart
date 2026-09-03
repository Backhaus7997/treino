// El pie del editor cableado con la validación real (#868).
//
// Hasta este slice la validación corría al tocar guardar y salía por
// `SnackBar`. Estos tests afirman lo que cambió: corre mientras se tipea, dice
// TODOS los problemas y no sólo el primero, y el CTA apagado sigue llevando al
// lugar donde falta algo.
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
import 'package:treino/features/workout/presentation/widgets/editor_footer_bar.dart';
import 'package:treino/l10n/app_l10n.dart';

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

Future<void> _agregarPressDeBanca(WidgetTester tester) async {
  await desplazarHastaAgregarEjercicio(tester);
  await tester.tap(find.text('Agregar ejercicio'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Press de Banca').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Agregar 1 ejercicio'));
  await tester.pumpAndSettle();
  // Desde este cambio el ejercicio agregado nace PLEGADO: quien avisa
  // que le falta completar sets es el borde rojo, no la card abierta.
  await expandirEjercicios(tester);
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

String _lineaDelPie(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('footer_status_line'))).data!;

void main() {
  testWidgets('la línea se actualiza mientras se tipea, sin guardar',
      (tester) async {
    await _pumpEditor(tester);

    // Sin nombre y sin ejercicios: dos problemas de arranque.
    expect(_lineaDelPie(tester), contains('Falta el nombre'));

    await tester.enterText(
        find.byKey(const Key('editor_name_field')), 'Empuje');
    await tester.pumpAndSettle();

    expect(_lineaDelPie(tester), isNot(contains('Falta el nombre')),
        reason: 'la validación corre en cada frame de tipeo: no hace falta '
            'tocar guardar para enterarse');
    expect(_lineaDelPie(tester), contains('sin ejercicios'),
        reason: 'y el problema que sigue aparece solo');
  });

  testWidgets('con todo cargado muestra el resumen y cuenta bien',
      (tester) async {
    await _pumpEditor(tester);
    await tester.enterText(
        find.byKey(const Key('editor_name_field')), 'Empuje');
    await tester.pumpAndSettle();
    await _agregarPressDeBanca(tester);
    await desplazarHasta(tester, celdasConHint('reps').at(0));
    await tester.enterText(celdasConHint('reps').at(0), '8');
    await tester.pumpAndSettle();

    final linea = _lineaDelPie(tester);
    expect(linea, contains('todo listo'));
    expect(linea, contains('1 día'), reason: 'el plan arranca con un día');
    expect(linea, contains('1 set'),
        reason: 'un ejercicio recién agregado trae un set');
  });

  testWidgets('junta hasta dos problemas en la misma línea', (tester) async {
    await _pumpEditor(tester);
    await _agregarPressDeBanca(tester);

    final linea = _lineaDelPie(tester);
    expect(linea, contains('Falta el nombre'));
    expect(linea, contains('·'),
        reason: 'el nombre falta Y el set está incompleto: los dos problemas '
            'entran en la misma línea, que es la diferencia entre corregir en '
            'una pasada o descubrirlos de a uno');
    expect(linea, contains('sin completar'));
  });

  testWidgets('el CTA apagado no guarda pero tampoco queda mudo',
      (tester) async {
    await _pumpEditor(tester);

    final cta = find.byKey(const Key('footer_submit_button'));
    await desplazarHasta(tester, cta);
    expect(tester.widget<ElevatedButton>(cta).onPressed, isNotNull,
        reason: 'un botón muerto no explica por qué no se puede guardar');

    await tester.tap(cta);
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget,
        reason: 'el tap dice qué falta');
  });

  testWidgets('IR aparece sólo cuando el problema vive en un día',
      (tester) async {
    await _pumpEditor(tester);

    // Sin nombre y con el día vacío: el primer problema con día es el día 1.
    expect(find.byKey(const Key('footer_go_to_problem')), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('editor_name_field')), 'Empuje');
    await tester.pumpAndSettle();
    await _agregarPressDeBanca(tester);
    await desplazarHasta(tester, celdasConHint('reps').at(0));
    await tester.enterText(celdasConHint('reps').at(0), '8');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('footer_go_to_problem')), findsNothing,
        reason: 'sin problemas no hay a dónde ir');
  });

  testWidgets('el resumen NO confunde días con sets', (tester) async {
    // Los dos son enteros y viajan juntos a la misma clave l10n. Un test con
    // 1 día y 1 set no distingue el orden: pasa igual invertido. Por eso acá
    // los números son distintos — es exactamente el bug que se coló.
    await _pumpEditor(tester);
    await tester.enterText(
        find.byKey(const Key('editor_name_field')), 'Empuje');
    await tester.pumpAndSettle();
    await _agregarPressDeBanca(tester);
    await desplazarHasta(tester, celdasConHint('reps').at(0));
    await tester.enterText(celdasConHint('reps').at(0), '8');
    await tester.pumpAndSettle();

    // Tres sets, un día: si los argumentos se invierten dice "3 días · 1 set".
    await _tocar(tester, find.byKey(const Key('add_set_button')));
    await _tocar(tester, find.byKey(const Key('add_set_button')));
    await tester.enterText(celdasConHint('reps').at(1), '8');
    await tester.pumpAndSettle();
    await tester.enterText(celdasConHint('reps').at(2), '8');
    await tester.pumpAndSettle();

    final linea = _lineaDelPie(tester);
    expect(linea, contains('1 día'));
    expect(linea, contains('3 sets'));
    expect(linea, isNot(contains('3 días')));
  });

  testWidgets('el problema nombra el día correcto, no la cantidad',
      (tester) async {
    // Mismo riesgo: `(dia, count)` invertido convierte "1 set sin completar en
    // el día 3" en "día 1: 3 sets sin completar".
    await _pumpEditor(tester);
    await tester.enterText(
        find.byKey(const Key('editor_name_field')), 'Empuje');
    await tester.pumpAndSettle();
    await _agregarPressDeBanca(tester);
    // Un solo set, sin reps: el día 1 tiene exactamente 1 problema.
    final linea = _lineaDelPie(tester);
    expect(linea, contains('Día 1'));
    expect(linea, contains('1 set sin completar'));
  });

  testWidgets('el pie está fuera del scroll', (tester) async {
    await _pumpEditor(tester);
    expect(find.byType(EditorFooterBar), findsOneWidget);

    final antes = tester.getTopLeft(find.byType(EditorFooterBar));
    await tester.drag(find.byType(ListView).first, const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.byType(EditorFooterBar)), antes,
        reason: 'scrollear el contenido no puede mover el pie: si se va de '
            'pantalla, la validación en vivo deja de estar a la vista');
  });
}
