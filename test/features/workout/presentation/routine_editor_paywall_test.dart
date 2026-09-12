// Widget tests del gate del paywall del alumno en el editor de rutinas.
//
// Cubren las dos mitades que importan:
//   1. Con el flag APAGADO —el estado en que esto shipea— el editor se
//      comporta EXACTAMENTE como antes. Es el test que garantiza que este PR
//      no le saca nada a los testers de hoy.
//   2. Con el flag encendido, el gate muerde donde tiene que morder y NO
//      muerde donde no: ni al PF, ni al alumno con derecho, ni mientras el
//      entitlement no resolvió.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/features/paywall/application/athlete_entitlement_provider.dart';
import 'package:treino/features/paywall/domain/athlete_entitlement.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
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
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/presentation/routine_editor_mode.dart';
import 'package:treino/features/workout/presentation/routine_editor_screen.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/paywall/application/athlete_checkout.dart';

import '../../../fixtures/exercises.dart';
import '../../../fixtures/routine_editor_ui.dart';
import '../../../helpers/fake_analytics_service.dart';

class _MockRoutineRepository extends Mock implements RoutineRepository {}

Future<void> _pumpEditor(
  WidgetTester tester, {
  required RoutineEditorMode mode,
  required List<Override> overrides,
}) async {
  usarViewportAlto(tester);
  final router = GoRouter(
    initialLocation: '/workout/editor',
    routes: [
      GoRoute(
        path: '/workout/editor',
        pageBuilder: (_, __) => NoTransitionPage(
          child: RoutineEditorScreen(mode: mode),
        ),
      ),
      GoRoute(
        path: '/workout',
        pageBuilder: (_, __) => const NoTransitionPage(
          child: Scaffold(body: Center(child: Text('WorkoutHome'))),
        ),
      ),
      GoRoute(
        path: '/coach',
        pageBuilder: (_, __) => const NoTransitionPage(
          child: Scaffold(body: Center(child: Text('CoachHome'))),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
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

List<Override> _overrides({
  String uid = 'athlete-1',
  bool? paywallEnabled,
  AthleteEntitlement? entitlement,
  List<Routine> userRoutines = const [],
  RoutineRepository? repo,
}) {
  return [
    currentUidProvider.overrideWithValue(uid),
    routineRepositoryProvider
        .overrideWithValue(repo ?? _MockRoutineRepository()),
    exercisesProvider.overrideWith((ref) async => kExerciseSeed),
    customExercisesForTrainerStreamProvider(uid).overrideWith(
      (ref) => Stream<List<CustomExercise>>.value(const <CustomExercise>[]),
    ),
    analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
    userCreatedRoutinesProvider(uid).overrideWith(
      (ref) => Stream<List<Routine>>.value(userRoutines),
    ),
    if (paywallEnabled != null)
      athletePaywallEnabledProvider.overrideWithValue(paywallEnabled),
    if (entitlement != null)
      athleteEntitlementProvider.overrideWithValue(entitlement),
  ];
}

/// Tap en el "+" de la barra de días. Por key: el botón es sólo un ícono y
/// "Agregar día" vive en su `Semantics.label`.
Future<void> _tapAgregarDia(WidgetTester tester) async {
  await cerrarDatosDelPlan(tester);
  final boton = find.byKey(const Key('day_tab_add'));
  await tester.ensureVisible(boton);
  await tester.tap(boton);
  await tester.pumpAndSettle();
}

Future<void> _tapAgregarSemana(WidgetTester tester) async {
  await abrirDatosDelPlan(tester);
  final boton = find.byKey(const Key('add_week_button'));
  await desplazarHasta(tester, boton);
  await tester.tap(boton);
  await tester.pumpAndSettle();
}

Finder get _sheet => find.byKey(const Key('free_plan_limit_grabber'));

/// [n] rutinas propias ya guardadas, para sembrar el cupo.
List<Routine> _rutinas(int n) => [
      for (var i = 0; i < n; i++)
        Routine(
          id: 'mia-$i',
          name: 'Mi rutina $i',
          split: null,
          level: ExperienceLevel.beginner,
          days: const [],
          source: RoutineSource.userCreated,
          visibility: RoutineVisibility.private,
          createdBy: 'athlete-1',
        ),
    ];

/// Lo mínimo que habilita el botón de guardar: nombre, un ejercicio y sus reps.
/// Misma receta que routine_editor_athlete_mode_test.
Future<void> _completarRutinaMinima(WidgetTester tester) async {
  await tester.enterText(
      find.byKey(const Key('editor_name_field')), 'Mi rutina');
  await tester.pumpAndSettle();
  await desplazarHastaAgregarEjercicio(tester);
  await tester.tap(find.text('Agregar ejercicio'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Press de Banca').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Agregar 1 ejercicio'));
  await tester.pumpAndSettle();
  await expandirEjercicios(tester);
  final vacios = find.byType(TextField).evaluate().where((e) {
    final w = e.widget as TextField;
    return w.controller != null && w.controller!.text.isEmpty;
  }).toList();
  await tester.enterText(find.byWidget(vacios.last.widget as TextField), '10');
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const Routine(
        id: '',
        name: '',
        split: null,
        level: ExperienceLevel.beginner,
        days: [],
        source: RoutineSource.userCreated,
        visibility: RoutineVisibility.private,
        numWeeks: 1,
      ),
    );
  });

  group('flag apagado — el estado en que esto shipea', () {
    testWidgets('el alumno free llega al cuarto día sin ver ninguna hoja',
        (tester) async {
      // ESTE es el test que protege a los 8 testers de hoy: nadie puede pagar
      // todavía, así que todos son `free`. Si el gate estuviera activo, este
      // camino quedaría cortado sin salida.
      await _pumpEditor(
        tester,
        mode: const SelfCreating(),
        overrides: _overrides(
          paywallEnabled: false,
          entitlement: AthleteEntitlement.free,
        ),
      );

      await _tapAgregarDia(tester);
      await _tapAgregarDia(tester);
      await _tapAgregarDia(tester); // el que cruzaría el tope de 3

      expect(_sheet, findsNothing);
      expect(find.byKey(const Key('day_tab_3')), findsOneWidget,
          reason: 'con el flag apagado el cuarto día se agrega igual');
    });
  });

  group('flag encendido', () {
    testWidgets('alumno free: el "+" del cuarto día abre la hoja y NO agrega',
        (tester) async {
      await _pumpEditor(
        tester,
        mode: const SelfCreating(),
        overrides: _overrides(
          paywallEnabled: true,
          entitlement: AthleteEntitlement.free,
        ),
      );

      await _tapAgregarDia(tester); // 1 → 2, dentro del tope
      await _tapAgregarDia(tester); // 2 → 3, es el tope y entra
      expect(_sheet, findsNothing,
          reason: 'el tercer día es el tope, y el tope entra: es la forma de '
              'las tres plantillas de principiante que el free sigue gratis');
      expect(find.byKey(const Key('day_tab_2')), findsOneWidget);

      await _tapAgregarDia(tester); // 3 → 4, cruza

      expect(_sheet, findsOneWidget);
      expect(find.byKey(const Key('day_tab_3')), findsNothing,
          reason: 'el día no se agregó');
    });

    testWidgets('la hoja no ofrece un botón de pago que no lleva a ningún lado',
        (tester) async {
      // El motivo cambió y conviene decirlo: antes el CTA no se dibujaba
      // porque `onUpgrade` era null. Ese parámetro ya no existe — la hoja mira
      // `athleteCheckoutProvider` y decide sola.
      //
      // Acá sigue sin dibujarse por la razón CORRECTA: en un test no hay clave
      // del SDK, así que `resolveAthleteCheckout()` devuelve
      // `AthleteCheckoutUnavailable`. Un botón que promete una salida
      // inexistente es peor que no tenerlo, y eso no cambió.
      await _pumpEditor(
        tester,
        mode: const SelfCreating(),
        overrides: _overrides(
          paywallEnabled: true,
          entitlement: AthleteEntitlement.free,
        ),
      );
      await _tapAgregarDia(tester);
      await _tapAgregarDia(tester);
      await _tapAgregarDia(tester); // el que cruza el tope de 3

      expect(_sheet, findsOneWidget);
      expect(find.byKey(const Key('free_plan_limit_upgrade')), findsNothing);
      expect(find.byKey(const Key('free_plan_limit_dismiss')), findsOneWidget);
    });

    testWidgets('con una superficie que SÍ puede cobrar, el CTA aparece',
        (tester) async {
      // La contraparte del test de arriba. Sin este, «no se dibuja el botón»
      // pasaría también si alguien borrara el botón entero.
      await _pumpEditor(
        tester,
        mode: const SelfCreating(),
        overrides: [
          ..._overrides(
            paywallEnabled: true,
            entitlement: AthleteEntitlement.free,
          ),
          athleteCheckoutProvider.overrideWithValue(
            resolveAthleteCheckout(store: _StoreDeMentira()),
          ),
        ],
      );
      await _tapAgregarDia(tester);
      await _tapAgregarDia(tester);
      await _tapAgregarDia(tester);

      expect(_sheet, findsOneWidget);
      expect(find.byKey(const Key('free_plan_limit_upgrade')), findsOneWidget);
    });

    testWidgets('alumno con derecho: no se le gatea nada', (tester) async {
      await _pumpEditor(
        tester,
        mode: const SelfCreating(),
        overrides: _overrides(
          paywallEnabled: true,
          entitlement: AthleteEntitlement.entitled,
        ),
      );

      await _tapAgregarDia(tester);
      await _tapAgregarDia(tester);
      await _tapAgregarDia(tester); // el que gatearía a un free

      expect(_sheet, findsNothing);
      expect(find.byKey(const Key('day_tab_3')), findsOneWidget);
    });

    testWidgets('entitlement unknown: falla ABIERTO, deja pasar',
        (tester) async {
      // El servidor rebota la escritura si no corresponde. Bloquear acá por un
      // read en vuelo sería castigar a quien paga por una red lenta.
      await _pumpEditor(
        tester,
        mode: const SelfCreating(),
        overrides: _overrides(
          paywallEnabled: true,
          entitlement: AthleteEntitlement.unknown,
        ),
      );

      await _tapAgregarDia(tester);
      await _tapAgregarDia(tester);
      await _tapAgregarDia(tester); // el que gatearía a un free confirmado

      expect(_sheet, findsNothing);
      expect(find.byKey(const Key('day_tab_3')), findsOneWidget);
    });

    testWidgets('el PF nunca ve el gate, aunque figure como free',
        (tester) async {
      // El editor del PF escribe `trainer-assigned`, no `user-created`. El PF
      // ya paga por su cupo — este paywall no es el suyo.
      await _pumpEditor(
        tester,
        mode: const TrainerAssigning(athleteId: 'athlete-9'),
        overrides: _overrides(
          uid: 'trainer-1',
          paywallEnabled: true,
          entitlement: AthleteEntitlement.free,
        ),
      );

      await _tapAgregarDia(tester);
      await _tapAgregarDia(tester);
      await _tapAgregarDia(tester); // el que gatearía a un alumno

      expect(_sheet, findsNothing);
      expect(find.byKey(const Key('day_tab_3')), findsOneWidget);
    });

    testWidgets('alumno free: "+ Semana" abre la hoja y no suma la semana',
        (tester) async {
      await _pumpEditor(
        tester,
        mode: const SelfCreating(),
        overrides: _overrides(
          paywallEnabled: true,
          entitlement: AthleteEntitlement.free,
        ),
      );

      await _tapAgregarSemana(tester); // 1 → 2, cruza el tope de 1

      expect(_sheet, findsOneWidget);
      await tester.tap(find.byKey(const Key('free_plan_limit_dismiss')));
      await tester.pumpAndSettle();
      await abrirDatosDelPlan(tester);
      expect(find.byKey(const Key('week_tab_1')), findsNothing,
          reason: 'la semana no se agregó');
    });
    testWidgets(
        'alumno free con 3 rutinas: guardar la cuarta abre la hoja y no crea',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.createUserOwned(
                uid: any(named: 'uid'),
                draft: any(named: 'draft'),
              ))
          .thenAnswer((inv) async =>
              (inv.namedArguments[const Symbol('draft')] as Routine)
                  .copyWith(id: 'no-deberia-llegar'));

      await _pumpEditor(
        tester,
        mode: const SelfCreating(),
        overrides: _overrides(
          paywallEnabled: true,
          entitlement: AthleteEntitlement.free,
          userRoutines: _rutinas(kFreeMaxOwnRoutines),
        ),
      );
      await _completarRutinaMinima(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'CREAR RUTINA'));
      await tester.pumpAndSettle();

      expect(_sheet, findsOneWidget);
      verifyNever(() => repo.createUserOwned(
            uid: any(named: 'uid'),
            draft: any(named: 'draft'),
          ));
    });

    testWidgets('con 2 rutinas todavía puede crear', (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.createUserOwned(
                uid: any(named: 'uid'),
                draft: any(named: 'draft'),
              ))
          .thenAnswer((inv) async =>
              (inv.namedArguments[const Symbol('draft')] as Routine)
                  .copyWith(id: 'gen'));

      await _pumpEditor(
        tester,
        mode: const SelfCreating(),
        overrides: _overrides(
          paywallEnabled: true,
          entitlement: AthleteEntitlement.free,
          userRoutines: _rutinas(kFreeMaxOwnRoutines - 1),
          repo: repo,
        ),
      );
      await _completarRutinaMinima(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'CREAR RUTINA'));
      await tester.pumpAndSettle();

      expect(_sheet, findsNothing);
      verify(() => repo.createUserOwned(
            uid: any(named: 'uid'),
            draft: any(named: 'draft'),
          )).called(1);
    });

    testWidgets('el que paga llega hasta el techo estructural, no a la hoja',
        (tester) async {
      // A las 10 ve el aviso de siempre, NO la hoja de plan pago: venderle el
      // plan a quien ya lo tiene es una promesa rota.
      await _pumpEditor(
        tester,
        mode: const SelfCreating(),
        overrides: _overrides(
          paywallEnabled: true,
          entitlement: AthleteEntitlement.entitled,
          userRoutines: _rutinas(kMaxOwnRoutines),
        ),
      );
      await _completarRutinaMinima(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'CREAR RUTINA'));
      await tester.pumpAndSettle();

      expect(_sheet, findsNothing);
      expect(find.text('Llegaste al máximo de 10 rutinas activas.'),
          findsOneWidget);
    });
  });

  // ── La rutina PROPIA que ya está fuera de la forma free ──────────────────
  //
  // El agujero que quedaba después de cerrar las tres puertas del catálogo.
  // El gate del destino exige `source == RoutineSource.system`, así que una
  // rutina `user-created` no lo cruza nunca: hidrataba el editor entero, el
  // alumno editaba, guardaba, y `firestore.rules` la rebotaba con "No tenés
  // permisos. Recargá la app.".
  //
  // No es un caso de borde. Hoy el flag está apagado y la CF escribe
  // `athletePaywallEnforced: false`, o sea que TODAS las rutinas que existan
  // el día del encendido se armaron sin tope. A eso se suman las dos formas de
  // perder el derecho con la rutina ya guardada: que se termine el vínculo con
  // el PF que pagaba por vos, y que se venza tu suscripción.
  group('rutina propia fuera de tope', () {
    /// Un slot completo. Los días TIENEN que traer ejercicios: `_submit`
    /// valida la rutina antes de mirar el paywall —un plan incompleto tiene un
    /// problema más urgente y un mensaje más específico— así que una rutina
    /// con días vacíos nunca llegaría al chequeo de forma.
    const slot = RoutineSlot(
      exerciseId: 'bench-press',
      exerciseName: 'Press de Banca',
      muscleGroup: 'chest',
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: 90,
      targetReps: [10],
    );

    /// Una rutina propia con [dias] días, como la que quedó de antes.
    Routine mia({int dias = 4, int numWeeks = 1}) => Routine(
          id: 'mia-1',
          name: 'Mi full body',
          split: null,
          level: ExperienceLevel.beginner,
          days: [
            for (var i = 1; i <= dias; i++)
              RoutineDay(dayNumber: i, name: 'Día $i', slots: const [slot]),
          ],
          source: RoutineSource.userCreated,
          visibility: RoutineVisibility.private,
          createdBy: 'athlete-1',
          numWeeks: numWeeks,
        );

    _MockRoutineRepository repoCon(Routine fuente) {
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any())).thenAnswer((_) async => fuente);
      when(() => repo.updateUserOwned(
                uid: any(named: 'uid'),
                draft: any(named: 'draft'),
              ))
          .thenAnswer((inv) async =>
              inv.namedArguments[const Symbol('draft')] as Routine);
      return repo;
    }

    // ⚠️ ESTOS CUATRO TESTS DECÍAN LO CONTRARIO HASTA EL 2026-09-11.
    //
    // Fijaban que al ABRIR una rutina propia fuera de tope aparecía la hoja, y
    // que guardarla sin recortar no escribía. Era correcto para la regla de
    // entonces: `withinFreeRoutineShape` medía el documento RESULTANTE, así que
    // una rutina de 4 días no se podía ni renombrar.
    //
    // Se midió la población real (5 alumnos de 18, y 4 de ellos pasados por
    // SEMANAS y no por días) y "podés entrenarla pero no podés renombrarla"
    // resultó imposible de explicar. Se cambió la REGLA: `noCreceLaForma` de
    // `firestore.rules` deja pasar un update que no agranda la rutina.
    //
    // Lo que estos tests fijan ahora es el espejo de esa regla en el cliente.
    // Y el espejo no es opcional: sin él el cliente sería MÁS ESTRICTO que el
    // servidor, que es el peor lado del error — el alumno ve un candado por
    // algo que el servidor le permite, y no tiene forma de descubrirlo.

    testWidgets('abrirla NO dice nada: ya no hay nada que recortar',
        (tester) async {
      // El aviso al entrar existía porque el alumno TENÍA que hacer algo antes
      // de poder guardar. Ya no. Seguir mostrándolo sería avisarle de un
      // problema que no tiene.
      final repo = repoCon(mia(dias: 4));
      await _pumpEditor(
        tester,
        mode: const SelfCreating(existingRoutineId: 'mia-1'),
        overrides: _overrides(
          paywallEnabled: true,
          entitlement: AthleteEntitlement.free,
          repo: repo,
        ),
      );

      expect(_sheet, findsNothing);
      expect(find.byKey(const Key('editor_name_field')), findsOneWidget);
    });

    testWidgets('EL QUE IMPORTA: renombrarla y guardar SÍ escribe',
        (tester) async {
      // El caso que le daba sentido a todo el trabajo del grandfathering, y el
      // espejo exacto del test de reglas "RENOMBRAR una de 4 días PASA".
      //
      // Si este se pone rojo, el cliente volvió a ser más estricto que el
      // servidor: la escritura ni sale, y el alumno no se entera de que estaba
      // permitida.
      final repo = repoCon(mia(dias: 4));
      await _pumpEditor(
        tester,
        mode: const SelfCreating(existingRoutineId: 'mia-1'),
        overrides: _overrides(
          paywallEnabled: true,
          entitlement: AthleteEntitlement.free,
          repo: repo,
        ),
      );

      await tester.enterText(
        find.byKey(const Key('editor_name_field')),
        'Renombrada',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'GUARDAR CAMBIOS'));
      await tester.pumpAndSettle();

      expect(_sheet, findsNothing);
      verify(() => repo.updateUserOwned(
            uid: any(named: 'uid'),
            draft: any(named: 'draft'),
          )).called(1);
    });

    testWidgets('el eje SEMANAS tampoco molesta al abrir', (tester) async {
      // El eje que de verdad mordía: 4 de los 5 alumnos afectados lo estaban
      // por semanas, y tres de ellos apenas en 2.
      final repo = repoCon(mia(dias: 2, numWeeks: 4));
      await _pumpEditor(
        tester,
        mode: const SelfCreating(existingRoutineId: 'mia-1'),
        overrides: _overrides(
          paywallEnabled: true,
          entitlement: AthleteEntitlement.free,
          repo: repo,
        ),
      );

      expect(_sheet, findsNothing);
    });

    testWidgets('CREAR una de 4 días sigue rebotando', (tester) async {
      // El control que impide que la excepción se derrame. `noCreceLaForma`
      // vive SÓLO en el UPDATE: sin una rutina previa contra qué comparar, el
      // tope se aplica entero.
      //
      // `SelfCreating` SIN `existingRoutineId` es el modo de crear, y el guard
      // del cliente lo distingue a mano porque el servidor lo distingue solo
      // (el CREATE no tiene `resource.data`).
      final repo = repoCon(mia(dias: 4));
      await _pumpEditor(
        tester,
        mode: const SelfCreating(),
        overrides: _overrides(
          paywallEnabled: true,
          entitlement: AthleteEntitlement.free,
          repo: repo,
        ),
      );
      await _tapAgregarDia(tester);
      await _tapAgregarDia(tester);
      await _tapAgregarDia(tester);

      expect(_sheet, findsOneWidget);
    });

    testWidgets('una rutina propia DENTRO del tope no ve nada', (tester) async {
      // El control negativo. Con 3 días —la forma de las plantillas gratis—
      // el alumno free edita y guarda sin ver una sola hoja.
      final repo = repoCon(mia(dias: kFreeMaxRoutineDays));
      await _pumpEditor(
        tester,
        mode: const SelfCreating(existingRoutineId: 'mia-1'),
        overrides: _overrides(
          paywallEnabled: true,
          entitlement: AthleteEntitlement.free,
          repo: repo,
        ),
      );

      expect(_sheet, findsNothing);
      expect(find.byKey(const Key('editor_name_field')), findsOneWidget);
    });

    testWidgets('alumno con derecho: su rutina de 4 días no le dice nada',
        (tester) async {
      final repo = repoCon(mia(dias: 4));
      await _pumpEditor(
        tester,
        mode: const SelfCreating(existingRoutineId: 'mia-1'),
        overrides: _overrides(
          paywallEnabled: true,
          entitlement: AthleteEntitlement.entitled,
          repo: repo,
        ),
      );

      expect(_sheet, findsNothing);
    });

    testWidgets('paywall apagado: nadie ve nada, que es como esto shipea',
        (tester) async {
      final repo = repoCon(mia(dias: 5));
      await _pumpEditor(
        tester,
        mode: const SelfCreating(existingRoutineId: 'mia-1'),
        overrides: _overrides(
          paywallEnabled: false,
          entitlement: AthleteEntitlement.free,
          repo: repo,
        ),
      );

      expect(_sheet, findsNothing);
      expect(find.byKey(const Key('editor_name_field')), findsOneWidget);
    });

    testWidgets('SEMANAS: abrir una de 4 semanas tampoco molesta',
        (tester) async {
      // El gemelo del test de días, sobre el eje que de verdad mordía.
      //
      // Decía `findsOneWidget` hasta el 2026-09-11 —la hoja aparecía al abrir—
      // por la misma razón que los otros: la cláusula medía el resultante.
      // `noCreceLaForma` mide los DOS ejes contra lo que ya había, así que 4
      // semanas se pueden seguir editando mientras no pasen a 5.
      final repo = repoCon(mia(dias: 2, numWeeks: 4));
      await _pumpEditor(
        tester,
        mode: const SelfCreating(existingRoutineId: 'mia-1'),
        overrides: _overrides(
          paywallEnabled: true,
          entitlement: AthleteEntitlement.free,
          repo: repo,
        ),
      );

      // Se chequea el ABRIR y no el guardar, y conviene decir por qué: una
      // rutina de 4 semanas armada con slots sin `weeklySets` no pasa la
      // validación de `_submit`, que corre ANTES del paywall. Forzar un save
      // acá probaría la validación, no el gate.
      //
      // El camino de guardado lo cubre el test de días de arriba, que es el
      // mismo código: `_freePlanBlocksShape` mira los dos ejes en la misma
      // función.
      expect(_sheet, findsNothing);
      expect(find.byKey(const Key('editor_name_field')), findsOneWidget);
    });
  });

  // ── El gate en el DESTINO (no en el botón que lleva acá) ─────────────────
  //
  // El chip "Usar como base" del detalle ya frena, pero es UN call site y la
  // ruta tiene más de una puerta: `treino://` está declarado sin `pathPrefix`,
  // así que `treino:///workout/customize-routine/<id>` entra derecho al editor,
  // y el `redirect` global del router sólo resuelve sesión y rol.
  //
  // Estos tests entran por la ruta, sin pasar por ningún botón — que es
  // exactamente lo que hace el deep link.
  group('personalizar una plantilla del catálogo', () {
    /// La rutina fuente que devuelve el repo cuando el editor la pide.
    Routine plantilla({RoutineSource source = RoutineSource.system}) => Routine(
          id: 'sys-1',
          name: 'Full Body 3 días',
          split: 'FULL BODY',
          level: ExperienceLevel.beginner,
          days: const [],
          source: source,
          visibility: RoutineVisibility.public,
        );

    _MockRoutineRepository repoCon(Routine fuente) {
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any())).thenAnswer((_) async => fuente);
      return repo;
    }

    testWidgets('EL AGUJERO: copiar una rutina AJENA de 4 días sigue rebotando',
        (tester) async {
      // Lo encontró una prueba de mutación, y vale contar cómo: se aflojó a
      // mano el chequeo de modo de `_noCreceRespectoDeLoCargado` para que la
      // excepción alcanzara a `SelfCustomizing`, y NINGÚN test se puso rojo.
      //
      // El motivo por el que no se notaba: al alumno free se le frena
      // `SelfCustomizing` antes, en el gate del catálogo. Pero ese gate mira
      // `isPremium`, así que sólo cubre las plantillas PAGAS. Una rutina
      // pública de OTRO alumno lo pasa, y ahí sí llega a este guard.
      //
      // Y el caso importa: `SelfCustomizing` HIDRATA desde la fuente, así que
      // `_diasAlCargar` queda en 4. Sin el chequeo de modo, el cliente
      // concluiría "no creció" y dejaría guardar un doc NUEVO de 4 días —
      // que el servidor rebota, porque `noCreceLaForma` vive sólo en el
      // UPDATE. El alumno se comería un `permission-denied` crudo.
      // Los días son REALES y con ejercicios, y eso es load-bearing: con
      // `days: []` el editor hidrata un día por defecto, la cuenta pasa de 0 a
      // 1, y el guard bloquea por "creció" — o sea que el test pasaría sin
      // ejercitar el chequeo de modo. Se descubrió mutando.
      const slotAjeno = RoutineSlot(
        exerciseId: 'squat',
        exerciseName: 'Sentadilla',
        muscleGroup: 'legs',
        targetSets: 3,
        targetRepsMin: 8,
        targetRepsMax: 12,
        restSeconds: 90,
        targetReps: [10],
      );
      final ajena = Routine(
        id: 'otra-1',
        name: 'Rutina de otro alumno',
        split: null,
        level: ExperienceLevel.beginner,
        days: [
          for (var i = 1; i <= 4; i++)
            RoutineDay(dayNumber: i, name: 'Día $i', slots: const [slotAjeno]),
        ],
        // NO es del catálogo: el gate de `isPremium` no la toca.
        source: RoutineSource.userCreated,
        visibility: RoutineVisibility.public,
      );
      final repo = repoCon(ajena);
      await _pumpEditor(
        tester,
        mode: const SelfCustomizing(sourceRoutineId: 'otra-1'),
        overrides: _overrides(
          paywallEnabled: true,
          entitlement: AthleteEntitlement.free,
          repo: repo,
        ),
      );

      expect(_sheet, findsOneWidget,
          reason: 'copiar es CREAR: la excepción del "no crece" es del UPDATE');
    });

    testWidgets('alumno free: no entra al editor, ve la hoja', (tester) async {
      final repo = repoCon(plantilla());
      await _pumpEditor(
        tester,
        mode: const SelfCustomizing(sourceRoutineId: 'sys-1'),
        overrides: _overrides(
          paywallEnabled: true,
          entitlement: AthleteEntitlement.free,
          repo: repo,
        ),
      );

      expect(_sheet, findsOneWidget);
      expect(find.byKey(const Key('editor_name_field')), findsNothing,
          reason: 'si el editor se hidrata, el alumno carga todo y recién al '
              'guardar se entera — perdiendo el trabajo');
    });

    testWidgets('alumno con derecho: entra normal', (tester) async {
      final repo = repoCon(plantilla());
      await _pumpEditor(
        tester,
        mode: const SelfCustomizing(sourceRoutineId: 'sys-1'),
        overrides: _overrides(
          paywallEnabled: true,
          entitlement: AthleteEntitlement.entitled,
          repo: repo,
        ),
      );

      expect(_sheet, findsNothing);
      expect(find.byKey(const Key('editor_name_field')), findsOneWidget);
    });

    testWidgets('paywall apagado: entra normal', (tester) async {
      final repo = repoCon(plantilla());
      await _pumpEditor(
        tester,
        mode: const SelfCustomizing(sourceRoutineId: 'sys-1'),
        overrides: _overrides(
          paywallEnabled: false,
          entitlement: AthleteEntitlement.free,
          repo: repo,
        ),
      );

      expect(_sheet, findsNothing);
      expect(find.byKey(const Key('editor_name_field')), findsOneWidget);
    });

    testWidgets('plantilla de un PF: el gate del catálogo NO aplica',
        (tester) async {
      // El gate es del CATÁLOGO (`source == system`). Una plantilla publicada
      // por un PF es contenido de la comunidad y la spec no la cobra — el
      // límite que le corresponde es el de FORMA, y ese lo aplica el detalle.
      final repo = repoCon(plantilla(source: RoutineSource.trainerTemplate));
      await _pumpEditor(
        tester,
        mode: const SelfCustomizing(sourceRoutineId: 'sys-1'),
        overrides: _overrides(
          paywallEnabled: true,
          entitlement: AthleteEntitlement.free,
          repo: repo,
        ),
      );

      expect(_sheet, findsNothing);
      expect(find.byKey(const Key('editor_name_field')), findsOneWidget);
    });
  });
}

/// Lo mínimo para que `resolveAthleteCheckout` devuelva la variante que cobra.
///
/// La hoja de límite sólo mira el TIPO —¿es `AthleteCheckoutOnStore`?— y nunca
/// le pregunta nada a la tienda, así que ningún método de acá se llama.
final class _StoreDeMentira implements AthleteStore {
  @override
  Future<void> identificar(String uid) async => throw UnimplementedError();

  @override
  Future<List<AthletePlanOferta>> ofertas() async => throw UnimplementedError();

  @override
  Future<Set<String>> comprar(AthletePlan plan) async =>
      throw UnimplementedError();

  @override
  Future<Set<String>> restaurar() async => throw UnimplementedError();
}
