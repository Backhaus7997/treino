// "Seguir sin copiar": `todaysRoutineProvider` resolviendo una plantilla del
// CATÁLOGO como la rutina de hoy.
//
// Hasta ahora, para entrenar un programa del catálogo había que copiarlo:
// `resolveActiveRoutineId` trataba un id de plantilla como marcador obsoleto y
// lo descartaba. Eso consumía cupo de rutinas propias y —con el paywall— la
// copia heredaba los días de la plantilla, así que un tope de 2 días rebotaba
// las 7 (todas tienen 3 o más).
//
// El otro eje de estos tests es el COSTO: el catálogo se lee sólo cuando hace
// falta. Watchearlo siempre le cobraría a toda la Home una lectura que la
// mayoría no necesita.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/home/application/todays_routine_provider.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show userProfileProvider;
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart'
    show routinesProvider;
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider, sessionsByUidProvider;
import 'package:treino/features/workout/application/user_routines_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/domain/session.dart';

const _uid = 'athlete-1';

const _day = RoutineDay(
  dayNumber: 1,
  name: 'Empuje',
  slots: [
    RoutineSlot(
      exerciseId: 'bench-press',
      exerciseName: 'Press de Banca',
      muscleGroup: 'chest',
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: 90,
    ),
  ],
);

Routine _rutina({
  required String id,
  required RoutineSource source,
  List<RoutineDay> days = const [_day],
  String? createdBy,
  String? assignedTo,
}) =>
    Routine(
      id: id,
      name: id,
      level: ExperienceLevel.beginner,
      days: days,
      source: source,
      visibility: source == RoutineSource.system
          ? RoutineVisibility.public
          : RoutineVisibility.private,
      createdBy: createdBy,
      assignedTo: assignedTo,
    );

UserProfile _perfil({String? activeRoutineId}) => UserProfile(
      uid: _uid,
      email: 'a@treino.app',
      displayName: 'Ana',
      role: UserRole.athlete,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      activeRoutineId: activeRoutineId,
    );

/// Cuenta cuántas veces se resolvió el catálogo — el eje de costo.
class _ContadorCatalogo {
  int lecturas = 0;
}

ProviderContainer _container({
  String? activeRoutineId,
  List<Routine> assigned = const [],
  List<Routine> selfCreated = const [],
  List<Routine> catalogo = const [],
  _ContadorCatalogo? contador,
}) {
  final container = ProviderContainer(
    overrides: [
      currentUidProvider.overrideWithValue(_uid),
      userProfileProvider.overrideWith(
        (ref) => Stream.value(_perfil(activeRoutineId: activeRoutineId)),
      ),
      assignedRoutinesProvider(_uid).overrideWith((ref) async => assigned),
      userCreatedRoutinesProvider(_uid)
          .overrideWith((ref) => Stream.value(selfCreated)),
      sessionsByUidProvider(_uid)
          .overrideWith((ref) async => const <Session>[]),
      routinesProvider.overrideWith((ref) async {
        contador?.lecturas++;
        return catalogo;
      }),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Resuelve el provider manteniéndolo VIVO.
///
/// `todaysRoutineProvider` es `autoDispose`: un `read(...future)` pelado lo
/// descarta en el gap async y el future completa con
/// "disposed during loading state". El `listen` lo sostiene mientras se espera.
Future<TodaysRoutine?> _hoy(ProviderContainer c) {
  c.listen(todaysRoutineProvider, (_, __) {});
  return c.read(todaysRoutineProvider.future);
}

void main() {
  group('seguir una plantilla del catálogo sin copiarla', () {
    test('el marcador apuntando a una plantilla del sistema resuelve',
        () async {
      final ppl = _rutina(id: 'ppl-beginner', source: RoutineSource.system);
      final c = _container(activeRoutineId: 'ppl-beginner', catalogo: [ppl]);

      final hoy = await _hoy(c);

      expect(hoy, isNotNull);
      expect(hoy!.routine.id, 'ppl-beginner');
      expect(hoy.routine.source, RoutineSource.system);
      expect(hoy.dayNumber, 1, reason: 'sin sesiones previas arranca en el 1');
    });

    test('gana sobre un plan del PF, igual que cualquier marcador', () async {
      // Tier 0 manda sobre tier 1. Si el atleta eligió seguir una plantilla,
      // esa manda aunque tenga un plan asignado.
      final ppl = _rutina(id: 'ppl-beginner', source: RoutineSource.system);
      final delPf = _rutina(
        id: 'del-pf',
        source: RoutineSource.trainerAssigned,
        assignedTo: _uid,
      );
      final c = _container(
        activeRoutineId: 'ppl-beginner',
        assigned: [delPf],
        catalogo: [ppl],
      );

      final hoy = await _hoy(c);
      expect(hoy!.routine.id, 'ppl-beginner');
    });

    test('una plantilla NO se auto-activa sin marcador', () async {
      // El catálogo no tiene tier propio: elegir una del montón por el atleta
      // sería decidir entre siete opciones que no pidió.
      final ppl = _rutina(id: 'ppl-beginner', source: RoutineSource.system);
      final c = _container(catalogo: [ppl]);

      expect(await _hoy(c), isNull);
    });

    test('un marcador que no existe en ningún lado cae a la cadena', () async {
      // Plantilla retirada del catálogo: no devuelve null teniendo un plan
      // del PF perfectamente válido.
      final delPf = _rutina(
        id: 'del-pf',
        source: RoutineSource.trainerAssigned,
        assignedTo: _uid,
      );
      final c = _container(
        activeRoutineId: 'plantilla-retirada',
        assigned: [delPf],
        catalogo: [_rutina(id: 'otra', source: RoutineSource.system)],
      );

      final hoy = await _hoy(c);
      expect(hoy!.routine.id, 'del-pf');
    });

    test('una plantilla sin días no rompe: devuelve null', () async {
      final vacia = _rutina(
        id: 'vacia',
        source: RoutineSource.system,
        days: const [],
      );
      final c = _container(activeRoutineId: 'vacia', catalogo: [vacia]);

      expect(await _hoy(c), isNull);
    });
  });

  group('el catálogo se lee SÓLO cuando hace falta', () {
    test('sin marcador no se lee', () async {
      // La Home de quien no eligió nada no paga esa lectura.
      final contador = _ContadorCatalogo();
      final c = _container(contador: contador);

      await _hoy(c);
      expect(contador.lecturas, 0);
    });

    test('con un marcador que ya resuelve contra un plan, tampoco', () async {
      // El caso mayoritario: quien tiene plan del PF o rutina propia resolvió
      // antes de llegar al catálogo.
      final contador = _ContadorCatalogo();
      final mia = _rutina(
        id: 'mia-1',
        source: RoutineSource.userCreated,
        createdBy: _uid,
      );
      final c = _container(
        activeRoutineId: 'mia-1',
        selfCreated: [mia],
        contador: contador,
      );

      final hoy = await _hoy(c);
      expect(hoy!.routine.id, 'mia-1');
      expect(contador.lecturas, 0,
          reason: 'el marcador matcheó contra las propias; el catálogo sobra');
    });

    test('sólo se lee cuando el marcador no matcheó contra los planes',
        () async {
      final contador = _ContadorCatalogo();
      final ppl = _rutina(id: 'ppl-beginner', source: RoutineSource.system);
      final c = _container(
        activeRoutineId: 'ppl-beginner',
        catalogo: [ppl],
        contador: contador,
      );

      await _hoy(c);
      expect(contador.lecturas, 1);
    });
  });
}
