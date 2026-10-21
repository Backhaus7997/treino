import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/application/assigned_routines_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/unified_routines_providers.dart';
import 'package:treino/features/workout/application/user_routines_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/profile/domain/experience_level.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _myUid = 'athlete-uid-123';

Routine _assigned({required String id}) => Routine(
      id: id,
      name: 'Plan $id',
      split: 'Full Body',
      level: ExperienceLevel.beginner,
      days: const [],
      source: RoutineSource.trainerAssigned,
      assignedBy: 'trainer-uid',
      assignedTo: _myUid,
      visibility: RoutineVisibility.private,
    );

Routine _own({required String id}) => Routine(
      id: id,
      name: 'Propia $id',
      split: 'Full Body',
      level: ExperienceLevel.beginner,
      days: const [],
      source: RoutineSource.userCreated,
      createdBy: _myUid,
      visibility: RoutineVisibility.private,
    );

// `activeRoutineId` ya seteado: la adopción perezosa de
// [unifiedRoutinesProvider] no escribe, así el test no necesita repositorio.
UserProfile _profile() => UserProfile(
      uid: _myUid,
      email: 'a@treino.app',
      displayName: 'Atleta',
      role: UserRole.athlete,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      activeRoutineId: 'cualquiera',
    );

ProviderContainer _container({
  List<Routine> assigned = const [],
  List<Routine> own = const [],
}) {
  final c = ProviderContainer(
    overrides: [
      assignedRoutinesProvider(_myUid).overrideWith((_) async => assigned),
      userCreatedRoutinesProvider(_myUid)
          .overrideWith((_) => Stream.value(own)),
      userProfileProvider.overrideWith((_) => Stream.value(_profile())),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

// Escucha la lista además del contador: mantiene vivo el autoDispose mientras
// se espera el future, sin depender de cómo el contador la consuma.
Future<int> _resolvedCount(ProviderContainer c) async {
  c.listen(unifiedRoutinesProvider(_myUid), (_, __) {});
  c.listen<int>(activeRoutinesCountProvider(_myUid), (_, __) {});
  await c.read(unifiedRoutinesProvider(_myUid).future);
  return c.read(activeRoutinesCountProvider(_myUid));
}

// ---------------------------------------------------------------------------
// Tests — el subtítulo «N activas» de Perfil → Cuenta → Mis rutinas
// ---------------------------------------------------------------------------

void main() {
  group('activeRoutinesCountProvider', () {
    // Bug QA 01: atleta sin PF con una rutina propia veía «0 activas» en el
    // perfil y la rutina con el chip ACTIVA al entrar a Mis rutinas.
    test('cuenta la rutina propia de un atleta sin PF', () async {
      final c = _container(own: [_own(id: 'o1')]);
      expect(await _resolvedCount(c), 1);
    });

    test('cuenta la rutina asignada por el coach', () async {
      final c = _container(assigned: [_assigned(id: 'a1')]);
      expect(await _resolvedCount(c), 1);
    });

    test('suma asignadas y propias: es la misma lista que Mis rutinas',
        () async {
      final c = _container(
        assigned: [_assigned(id: 'a1')],
        own: [_own(id: 'o1'), _own(id: 'o2')],
      );
      final count = await _resolvedCount(c);
      final entries = await c.read(unifiedRoutinesProvider(_myUid).future);
      expect(count, 3);
      expect(count, entries.length);
    });

    test('devuelve 0 mientras carga', () {
      final c = ProviderContainer(
        overrides: [
          assignedRoutinesProvider(_myUid).overrideWith(
            (_) => Future<List<Routine>>.delayed(
              const Duration(seconds: 60),
              () => const [],
            ),
          ),
          userCreatedRoutinesProvider(_myUid)
              .overrideWith((_) => Stream.value(const [])),
          userProfileProvider.overrideWith((_) => Stream.value(_profile())),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(activeRoutinesCountProvider(_myUid)), 0);
    });

    test('devuelve 0 si la lista falla', () async {
      final c = ProviderContainer(
        overrides: [
          assignedRoutinesProvider(_myUid).overrideWith(
            (_) => Future<List<Routine>>.error(Exception('sin red')),
          ),
          userCreatedRoutinesProvider(_myUid)
              .overrideWith((_) => Stream.value(const [])),
          userProfileProvider.overrideWith((_) => Stream.value(_profile())),
        ],
      );
      addTearDown(c.dispose);
      c.listen(unifiedRoutinesProvider(_myUid), (_, __) {});
      c.listen<int>(activeRoutinesCountProvider(_myUid), (_, __) {});
      await expectLater(
        c.read(unifiedRoutinesProvider(_myUid).future),
        throwsA(isA<Exception>()),
      );
      expect(c.read(activeRoutinesCountProvider(_myUid)), 0);
    });
  });
}
