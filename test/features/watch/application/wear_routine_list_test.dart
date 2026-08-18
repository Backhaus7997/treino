import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/watch/application/wear_routine_list_providers.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/application/user_routines_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show userRepositoryProvider;
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:mocktail/mocktail.dart';

class _RepoQueNoConfirma extends Mock implements UserRepository {}

const uid = 'atleta-1';

Routine _r(String id, RoutineSource source, {int dias = 3, int semanas = 1}) =>
    Routine(
      id: id,
      name: id,
      level: ExperienceLevel.beginner,
      source: source,
      numWeeks: semanas,
      days: [
        for (var d = 1; d <= dias; d++)
          RoutineDay(dayNumber: d, name: 'Día $d', slots: const []),
      ],
    );

void main() {
  setUpAll(() => registerFallbackValue(<String, Object?>{}));

  group('la chapita sale del origen', () {
    test('la tabla completa, igual que watchOS', () {
      // Misma tabla que `RoutineOrigin.badge` de RoutineCatalog.swift: si acá
      // divergiera, el atleta leería cosas distintas en cada reloj.
      expect(wearRoutineBadge(RoutineSource.trainerAssigned), 'COACH');
      expect(wearRoutineBadge(RoutineSource.userCreated), 'MÍA');
      expect(wearRoutineBadge(RoutineSource.trainerTemplate), 'PF');
      // El catálogo de TREINO no lleva: es el fondo de la lista, no el titular.
      expect(wearRoutineBadge(RoutineSource.system), isNull);
    });

    test('el resumen trae lo que la fila dibuja', () {
      final s = wearRoutineSummaryFrom(
        _r('r1', RoutineSource.trainerAssigned, dias: 4, semanas: 3),
      );

      expect(s.id, 'r1');
      expect(s.dayCount, 4);
      expect(s.numWeeks, 3);
      expect(s.badge, 'COACH');
      expect(s.subtitle, '4 días · 3 sem');
    });
  });

  group('MIS PLANES', () {
    ProviderContainer conPlanes({
      required AsyncValue<List<Routine>> asignadas,
      required AsyncValue<List<Routine>> propias,
    }) {
      final c = ProviderContainer(
        overrides: [
          currentUidProvider.overrideWithValue(uid),
          assignedRoutinesProvider(uid)
              .overrideWith((ref) => switch (asignadas) {
                    AsyncData(:final value) => Future.value(value),
                    AsyncError(:final error) =>
                      Future<List<Routine>>.error(error),
                    // Nunca completa: simula "todavia cargando".
                    _ => Completer<List<Routine>>().future,
                  }),
          userCreatedRoutinesProvider(uid)
              .overrideWith((ref) => switch (propias) {
                    AsyncData(:final value) => Stream.value(value),
                    AsyncError(:final error) =>
                      Stream<List<Routine>>.error(error),
                    _ => const Stream<List<Routine>>.empty(),
                  }),
        ],
      );
      addTearDown(c.dispose);
      // autoDispose: sin alguien escuchando, cada `read` recrea el grafo
      // entero y vuelve a «cargando».
      c.listen(wearPlansProvider, (_, __) {});
      return c;
    }

    test('los del PF van primero, después las propias', () async {
      final c = conPlanes(
        asignadas:
            AsyncValue.data([_r('delPF', RoutineSource.trainerAssigned)]),
        propias: AsyncValue.data([_r('mia', RoutineSource.userCreated)]),
      );
      await pumpEventQueue();

      final lista = c.read(wearPlansProvider);
      expect([for (final r in lista.routines) r.id], ['delPF', 'mia']);
      expect([for (final r in lista.routines) r.badge], ['COACH', 'MÍA']);
      expect(lista.isLoading, isFalse);
      expect(lista.failed, isFalse);
    });

    test('si una fuente falló pero la otra trajo datos, se muestran', () async {
      // Media lista es mejor que un cartel: el atleta puede entrenar con lo que
      // hay. Es la política que WearRoutineSection ya documentaba.
      final c = conPlanes(
        asignadas: AsyncValue.error(Exception('sin red'), StackTrace.empty),
        propias: AsyncValue.data([_r('mia', RoutineSource.userCreated)]),
      );
      await pumpEventQueue();

      final lista = c.read(wearPlansProvider);
      expect([for (final r in lista.routines) r.id], ['mia']);
      expect(lista.failed, isFalse, reason: 'hay algo que mostrar');
    });

    test('sin uid todavía es CARGANDO, no vacío', () {
      // El error que ya se pagó en HOY: colapsar "cargando" con "vacío" deja al
      // atleta mirando "No tenés planes" mientras el uid se resuelve.
      final c = ProviderContainer(
        overrides: [currentUidProvider.overrideWithValue(null)],
      );
      addTearDown(c.dispose);

      final lista = c.read(wearPlansProvider);
      expect(lista.isLoading, isTrue);
      expect(lista.routines, isEmpty);
    });
  });

  test('activar VUELVE aunque el servidor no confirme', () async {
    // El bug que vio el dueño: tocaba Activar y quedaba en «cargando» para
    // siempre, con la rutina IGUAL activada — el caché local la aplicó al
    // instante y la promesa esperaba un ack que no llegaba. Y como la bandera
    // del detalle no se apagaba, desde ahí ninguna otra rutina volvía a mostrar
    // sus botones.
    final nuncaConfirma = _RepoQueNoConfirma();
    when(() => nuncaConfirma.update(any(), any()))
        .thenAnswer((_) => Completer<void>().future);

    final c = ProviderContainer(
      overrides: [
        currentUidProvider.overrideWithValue(uid),
        userRepositoryProvider.overrideWithValue(nuncaConfirma),
      ],
    );
    addTearDown(c.dispose);

    // Si esto esperara el ack, el test colgaría acá.
    await c.read(wearActivateRoutineProvider)('r1').timeout(
          const Duration(seconds: 2),
          onTimeout: () => fail('activar esperó la confirmación del servidor'),
        );

    // Y la escritura igual se disparó: se aplica al caché local sola.
    verify(() => nuncaConfirma.update(uid, {'activeRoutineId': 'r1'}))
        .called(1);
  });

  test('PLANTILLAS: la comunidad va primero y el catálogo después', () async {
    final c = ProviderContainer(
      overrides: [
        currentUidProvider.overrideWithValue(uid),
        publishedTemplatesProvider.overrideWith(
          (ref) async => [_r('deUnPF', RoutineSource.trainerTemplate)],
        ),
        routinesProvider.overrideWith(
          (ref) async => [_r('deTREINO', RoutineSource.system)],
        ),
      ],
    );
    addTearDown(c.dispose);
    c.listen(wearTemplatesProvider, (_, __) {});
    await pumpEventQueue();

    final lista = c.read(wearTemplatesProvider);
    expect([for (final r in lista.routines) r.id], ['deUnPF', 'deTREINO']);
    expect([for (final r in lista.routines) r.badge], ['PF', null]);
  });
}
