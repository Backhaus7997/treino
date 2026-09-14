// El gate del catálogo pago en el RELOJ (Wear OS), y el rechazo del servidor
// que antes moría en un log.
//
// ─── Por qué el reloj necesita su propio gate ───────────────────────────────
//
// El #1066 cerró las tres puertas del catálogo en el TELÉFONO: la grilla,
// "Seguir esta plantilla" y EMPEZAR. El reloj no pasa por ninguna de las tres
// — `WearSessionNotifier` escribe `users/{uid}/sessions` directo con el SDK.
// Sin gate, el alumno free abre el reloj y entrena una plantilla paga.
//
// ─── Por qué no alcanza con la regla de Firestore ───────────────────────────
//
// Porque el reloj crea la sesión con `waitForServer: false`: para cuando el
// servidor rechaza, la pantalla de entreno YA está abierta. La regla es el
// enforcement real y sigue siendo la ley, pero llega tarde para la UX. De ahí
// las dos mitades que cubre este archivo: el gate que frena antes, y el canal
// que hace visible el rechazo cuando el gate no alcanzó.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/paywall/application/athlete_entitlement_provider.dart';
import 'package:treino/features/paywall/domain/athlete_entitlement.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/watch/application/wear_rest_providers.dart';
import 'package:treino/features/watch/application/wear_session_providers.dart';
import 'package:treino/features/watch/data/wear_workout_service.dart';
import 'package:treino/features/watch/presentation/wear/wear_strings.dart';
import 'package:treino/features/watch/presentation/wear/wear_view_models.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/domain/session.dart';

class _MockWorkoutService extends Mock implements WearWorkoutService {}

/// Un repo que crea la sesión en local y después avisa que el servidor la
/// rechazó — exactamente lo que hace Firestore con `waitForServer: false`
/// cuando las reglas deniegan: el `set()` ya se aplicó al caché, y el rechazo
/// llega por el `Future` un rato después.
///
/// EXTIENDE en vez de implementar a propósito. `SessionRepository` no es una
/// interfaz chica —el notifier del reloj le pide `getActive`, `watchRevision`,
/// `listByUid`, `watchSetLogs`…— y un doble que implemente sólo `create` se
/// cae con un `NoSuchMethodError` que no tiene nada que ver con lo que el test
/// quiere probar. Heredando, todo lo demás sigue siendo el repo de verdad y el
/// único comportamiento sustituido es el que importa.
class _RepoQueElServidorRechaza extends SessionRepository {
  _RepoQueElServidorRechaza({required super.firestore});

  void Function(Object error)? _avisar;

  @override
  Future<Session> create({
    required String uid,
    required String routineId,
    required String routineName,
    required DateTime startedAt,
    int dayNumber = 1,
    int weekNumber = 0,
    bool waitForServer = true,
    void Function(Object error)? onServerRejected,
  }) {
    _avisar = onServerRejected;
    return super.create(
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: startedAt,
      dayNumber: dayNumber,
      weekNumber: weekNumber,
    );
  }

  /// Dispara el rechazo del servidor CUANDO EL TEST QUIERE.
  ///
  /// Que el timing lo controle el test no es comodidad: es lo que hace que
  /// esto reproduzca la secuencia real. Con `waitForServer: false` el rechazo
  /// llega DESPUÉS de que el notifier abrió la pantalla de entreno, no
  /// durante el `create`. Un doble que avisara dentro del `create` probaría
  /// una secuencia que no existe — y encima daría verde sin que el estado
  /// `Running` llegara a pisarse nunca.
  void elServidorRechaza() => _avisar?.call('permission-denied');
}

const uid = 'athlete-1';

RoutineSlot _slot(String id) => RoutineSlot(
      exerciseId: id,
      exerciseName: id,
      muscleGroup: 'chest',
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: 90,
      targetReps: const [10],
    );

Routine _plantilla({required bool premium}) => Routine(
      id: 'sys-1',
      name: 'Bro Split — Intermedio',
      split: null,
      level: ExperienceLevel.intermediate,
      days: [
        RoutineDay(dayNumber: 1, name: 'Día 1', slots: [_slot('press')]),
      ],
      source: RoutineSource.system,
      visibility: RoutineVisibility.public,
      isPremium: premium,
      numWeeks: 1,
    );

const hoy = WearTodaysWorkout(
  routineId: 'sys-1',
  dayName: 'Día 1',
  dayNumber: 1,
  routineName: 'Bro Split — Intermedio',
  exercises: [WearExercisePreview(name: 'press', setCount: 3)],
  weekNumber: 0,
  numWeeks: 1,
);

void main() {
  late FakeFirebaseFirestore firestore;
  late SessionRepository repo;
  late _MockWorkoutService nativo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = SessionRepository(firestore: firestore);
    nativo = _MockWorkoutService();
    when(() => nativo.startWorkout()).thenAnswer((_) async => true);
    when(() => nativo.stopWorkout()).thenAnswer((_) async {});
    when(() => nativo.cancelRest()).thenAnswer((_) async {});
  });

  ProviderContainer contenedor({
    required bool premium,
    bool? paywallEnabled,
    AthleteEntitlement? entitlement,
    SessionRepository? repoOverride,
  }) {
    final c = ProviderContainer(
      overrides: [
        currentUidProvider.overrideWithValue(uid),
        sessionRepositoryProvider.overrideWithValue(repoOverride ?? repo),
        routineByIdProvider
            .overrideWith((ref, id) async => _plantilla(premium: premium)),
        wearWorkoutServiceProvider.overrideWithValue(nativo),
        if (paywallEnabled != null)
          athletePaywallEnabledProvider.overrideWithValue(paywallEnabled),
        if (entitlement != null)
          athleteEntitlementProvider.overrideWithValue(entitlement),
      ],
    );
    addTearDown(c.dispose);
    c.listen(wearSessionProvider, (_, __) {});
    return c;
  }

  Future<int> sesionesCreadas() async {
    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .get();
    return snap.docs.length;
  }

  group('flag apagado — el estado en que esto shipea', () {
    test('el free entrena una plantilla paga sin ver nada', () async {
      // El test que garantiza que este PR no le saque nada a los testers de
      // hoy: nadie puede pagar todavía, así que todos son `free`.
      final c = contenedor(
        premium: true,
        paywallEnabled: false,
        entitlement: AthleteEntitlement.free,
      );

      final ok =
          await c.read(wearSessionProvider.notifier).startRoutine('sys-1');

      expect(ok, isTrue);
      expect(await sesionesCreadas(), 1);
    });
  });

  group('flag encendido — desde la lista de rutinas', () {
    test('free + plantilla paga: frena y NO crea la sesión', () async {
      final c = contenedor(
        premium: true,
        paywallEnabled: true,
        entitlement: AthleteEntitlement.free,
      );

      final ok =
          await c.read(wearSessionProvider.notifier).startRoutine('sys-1');

      expect(ok, isFalse);
      expect(
        c.read(wearSessionProvider),
        isA<WearSessionFailed>().having(
          (f) => f.motivo,
          'motivo',
          WearStrings.plantillaPaga,
        ),
      );
      expect(await sesionesCreadas(), 0,
          reason: 'la sesión ni se crea en local: el gate frena ANTES, que es '
              'lo que distingue esto de esperar el deny del servidor');
    });

    test('free + plantilla gratis: entrena normal', () async {
      // La mitad que es fácil romper de más. Gatear el catálogo entero dejaría
      // al free sin nada que entrenar desde el reloj.
      final c = contenedor(
        premium: false,
        paywallEnabled: true,
        entitlement: AthleteEntitlement.free,
      );

      final ok =
          await c.read(wearSessionProvider.notifier).startRoutine('sys-1');

      expect(ok, isTrue);
      expect(await sesionesCreadas(), 1);
    });

    test('con derecho: la plantilla paga se entrena', () async {
      final c = contenedor(
        premium: true,
        paywallEnabled: true,
        entitlement: AthleteEntitlement.entitled,
      );

      final ok =
          await c.read(wearSessionProvider.notifier).startRoutine('sys-1');

      expect(ok, isTrue);
      expect(await sesionesCreadas(), 1);
    });

    test('entitlement unknown: falla ABIERTO', () async {
      // Mismo criterio que el teléfono: el servidor rebota igual si no
      // corresponde. Fallar cerrado le cortaría el entreno a quien paga por un
      // read en vuelo — y en un reloj, con la red del teléfono de por medio,
      // ese caso es mucho más común que en la app.
      final c = contenedor(
        premium: true,
        paywallEnabled: true,
        entitlement: AthleteEntitlement.unknown,
      );

      final ok =
          await c.read(wearSessionProvider.notifier).startRoutine('sys-1');

      expect(ok, isTrue);
      expect(await sesionesCreadas(), 1);
    });
  });

  group('flag encendido — desde el entreno de HOY', () {
    // La otra puerta. `WearTodaysWorkout` no transporta `isPremium`, así que
    // este camino tiene que resolver la rutina para poder gatear.
    //
    // Y no es un caso imposible: el #1066 impide que un free ACTIVE una
    // plantilla paga, pero no toca las que ya estaban activas de antes ni las
    // del que la activó mientras tenía derecho y después lo perdió.
    test('free + plantilla paga: frena y NO crea la sesión', () async {
      final c = contenedor(
        premium: true,
        paywallEnabled: true,
        entitlement: AthleteEntitlement.free,
      );

      await c.read(wearSessionProvider.notifier).start(hoy);

      expect(
        c.read(wearSessionProvider),
        isA<WearSessionFailed>().having(
          (f) => f.motivo,
          'motivo',
          WearStrings.plantillaPaga,
        ),
      );
      expect(await sesionesCreadas(), 0);
    });

    test('free + plantilla gratis: entrena normal', () async {
      final c = contenedor(
        premium: false,
        paywallEnabled: true,
        entitlement: AthleteEntitlement.free,
      );

      await c.read(wearSessionProvider.notifier).start(hoy);

      expect(c.read(wearSessionProvider), isA<WearSessionRunning>());
      expect(await sesionesCreadas(), 1);
    });
  });

  group('el rechazo del servidor deja de morir en un log', () {
    // La red de seguridad de todo lo de arriba. Si el gate no alcanzó —un
    // cliente viejo, un tope que cambió en el servidor y no en el reloj— el
    // atleta tiene que ENTERARSE, no entrenar una hora contra una sesión que
    // no existe y que no va a existir nunca.
    //
    // Sin red el `Future` de Firestore queda PENDIENTE y se reintenta solo:
    // ese caso no pasa por acá y no molesta a nadie. Lo que llega es un
    // rechazo, y ése no se arregla reintentando.
    test('un deny del servidor se muestra en pantalla', () async {
      final repoQueRechaza = _RepoQueElServidorRechaza(firestore: firestore);
      final c = contenedor(
        premium: false,
        paywallEnabled: false,
        repoOverride: repoQueRechaza,
      );

      await c.read(wearSessionProvider.notifier).startRoutine('sys-1');
      expect(c.read(wearSessionProvider), isA<WearSessionRunning>(),
          reason: 'con waitForServer:false la pantalla abre ANTES de que el '
              'servidor conteste — ése es el punto de partida real');

      repoQueRechaza.elServidorRechaza();

      expect(
        c.read(wearSessionProvider),
        isA<WearSessionFailed>().having(
          (f) => f.motivo,
          'motivo',
          WearStrings.sesionRechazada,
        ),
        reason: 'antes esto se iba a developer.log y la pantalla seguía '
            'mostrando el entreno como si nada — el atleta hacía una hora '
            'contra una sesión que el servidor nunca aceptó',
      );
    });
  });
}
