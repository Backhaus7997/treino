// Tests para RoutineActionsNotifier — mutación mínima de rutinas del Coach
// Hub web (Fase 5, WU-04). Sin widgets: aislado a nivel de ProviderContainer
// para verificar la llamada al repo + la invalidación del listado.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/core/analytics/analytics_service.dart';

import '../../../../../helpers/fake_analytics_service.dart';
import 'package:treino/features/coach_hub/presentation/sections/rutinas/routine_actions_provider.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_status.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/domain/routine_source.dart';

class _MockRoutineRepository extends Mock implements RoutineRepository {}

const _athleteId = 'athlete-1';
const _trainerId = 'trainer-1';
const _key = (trainerId: _trainerId, athleteId: _athleteId);

void main() {
  // `any(named: 'template')` sobre un parámetro tipado necesita un fallback
  // registrado: mocktail lo pasa de mano en mano sin tocarlo, pero necesita
  // ALGO del tipo correcto para armar el matcher.
  setUpAll(() => registerFallbackValue(_makeRoutine('fallback')));

  late _MockRoutineRepository mockRepo;
  late FakeAnalyticsService analytics;
  late int listCalls;
  late int grillaCalls;

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [
        routineRepositoryProvider.overrideWithValue(mockRepo),
        analyticsServiceProvider.overrideWithValue(analytics),
        assignedRoutinesByTrainerProvider(_key).overrideWith((ref) async {
          listCalls++;
          return const <Routine>[];
        }),
        // La grilla de la sección Rutinas lee de ACÁ desde que el eje pasó a
        // ser el autor. Contar sus fetch es lo que prueba que la card
        // desaparece sola en vez de quedarse hasta recargar.
        routinesAuthoredByProvider(_trainerId).overrideWith((ref) async {
          grillaCalls++;
          return const <Routine>[];
        }),
      ],
    );
  }

  setUp(() {
    mockRepo = _MockRoutineRepository();
    analytics = FakeAnalyticsService();
    listCalls = 0;
    grillaCalls = 0;
  });

  group('RoutineActionsNotifier.archive', () {
    test(
        'llama a repo.archive(routineId) e invalida assignedRoutinesByTrainerProvider',
        () async {
      when(() => mockRepo.archive(any())).thenAnswer((_) async {});
      final container = makeContainer();
      addTearDown(container.dispose);

      // Mantiene vivo el FutureProvider.autoDispose durante el test.
      final sub =
          container.listen(assignedRoutinesByTrainerProvider(_key), (_, __) {});
      addTearDown(sub.close);

      await container.read(assignedRoutinesByTrainerProvider(_key).future);
      expect(listCalls, 1);

      final ok = await container.read(routineActionsProvider.notifier).archive(
          routineId: 'r1', trainerId: _trainerId, athleteId: _athleteId);

      expect(ok, isTrue);
      verify(() => mockRepo.archive('r1')).called(1);

      // El invalidate dispara un nuevo fetch en la próxima lectura.
      await container.read(assignedRoutinesByTrainerProvider(_key).future);
      expect(listCalls, 2);
    });

    test(
        'invalida también routineByIdProvider — la caché single-doc se quedaba '
        'con el `status: active` previo al archivado', () async {
      when(() => mockRepo.archive(any())).thenAnswer((_) async {});

      // El stub imita lo que hace el repo DE VERDAD: `archive` sólo escribe
      // `status: archived`, el doc sigue existiendo y `_fromDoc` únicamente
      // devuelve null cuando `!snap.exists`. Un stub que devolviera null acá
      // haría pasar el test por un comportamiento que producción no tiene.
      var archived = false;
      var getByIdCalls = 0;
      when(() => mockRepo.getById('r1')).thenAnswer((_) async {
        getByIdCalls++;
        return _makeRoutine(
          'r1',
          status: archived ? RoutineStatus.archived : RoutineStatus.active,
        );
      });

      final container = makeContainer();
      addTearDown(container.dispose);

      final before = await container.read(routineByIdProvider('r1').future);
      expect(before!.status, RoutineStatus.active);
      expect(getByIdCalls, 1);

      archived = true;
      await container.read(routineActionsProvider.notifier).archive(
          routineId: 'r1', trainerId: _trainerId, athleteId: _athleteId);

      // Sin la invalidación esto seguiría dando `active`: el keepAlive de
      // `_cacheOnlyOnSuccess` sólo se suelta si el fetch TIRA, así que el doc
      // previo al archivado quedaba servido para toda la vida del proceso.
      final after = await container.read(routineByIdProvider('r1').future);
      expect(after!.status, RoutineStatus.archived);
      expect(getByIdCalls, 2,
          reason: 'la caché single-doc tiene que refetchear tras el archive');
    });

    test('devuelve false y no propaga la excepción cuando repo.archive falla',
        () async {
      when(() => mockRepo.archive(any())).thenThrow(Exception('boom'));
      final container = makeContainer();
      addTearDown(container.dispose);

      final ok = await container.read(routineActionsProvider.notifier).archive(
          routineId: 'r1', trainerId: _trainerId, athleteId: _athleteId);

      expect(ok, isFalse);
    });
  });

  group('RoutineActionsNotifier.unarchive', () {
    // EL test de este grupo. `archive` y `unarchive` comparten `_flipStatus`,
    // que recibe QUÉ escribir como callback: es una función de un renglón de
    // distancia entre «recuperar» y «archivar de nuevo». Mismo modo de falla
    // que el de publicar/despublicar, y por eso mismo el control es el mismo.
    //
    // Si «Recuperar» archivara, el PF no vería NADA raro: la rutina ya estaba
    // archivada y sigue archivada. El botón sería un no-op perfecto.
    test('llama a repo.unarchive, NO a repo.archive', () async {
      when(() => mockRepo.unarchive(any())).thenAnswer((_) async {});

      final container = makeContainer();
      addTearDown(container.dispose);

      final ok =
          await container.read(routineActionsProvider.notifier).unarchive(
                routineId: 'r1',
                trainerId: _trainerId,
                athleteId: _athleteId,
              );
      expect(ok, isTrue);
      verify(() => mockRepo.unarchive('r1')).called(1);
      verifyNever(() => mockRepo.archive(any()));
    });

    // El espejo del de arriba: el mismo callback mal cableado en la otra
    // dirección dejaría «Sacársela a X» devolviéndole la rutina al alumno.
    test('control: archive sigue llamando a repo.archive, NO a unarchive',
        () async {
      when(() => mockRepo.archive(any())).thenAnswer((_) async {});

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(routineActionsProvider.notifier).archive(
            routineId: 'r1',
            trainerId: _trainerId,
            athleteId: _athleteId,
          );
      verify(() => mockRepo.archive('r1')).called(1);
      verifyNever(() => mockRepo.unarchive(any()));
    });

    test('invalida los DOS listados', () async {
      when(() => mockRepo.unarchive(any())).thenAnswer((_) async {});

      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(assignedRoutinesByTrainerProvider(_key).future);
      await container.read(routinesAuthoredByProvider(_trainerId).future);
      listCalls = 0;
      grillaCalls = 0;

      await container.read(routineActionsProvider.notifier).unarchive(
            routineId: 'r1',
            trainerId: _trainerId,
            athleteId: _athleteId,
          );

      await container.read(assignedRoutinesByTrainerProvider(_key).future);
      await container.read(routinesAuthoredByProvider(_trainerId).future);

      // La grilla, para que la card deje de decir «Archivada». Y el par
      // trainer/alumno, que es de donde lee la ficha: sin eso la rutina
      // recuperada no vuelve a aparecerle al alumno hasta recargar.
      expect(grillaCalls, 1);
      expect(listCalls, 1);
    });

    test('invalida también la caché single-doc', () async {
      when(() => mockRepo.unarchive(any())).thenAnswer((_) async {});

      var activa = false;
      var getByIdCalls = 0;
      when(() => mockRepo.getById('r1')).thenAnswer((_) async {
        getByIdCalls++;
        return _makeRoutine(
          'r1',
          status: activa ? RoutineStatus.active : RoutineStatus.archived,
        );
      });

      final container = makeContainer();
      addTearDown(container.dispose);

      final antes = await container.read(routineByIdProvider('r1').future);
      expect(antes!.status, RoutineStatus.archived);

      activa = true;
      await container.read(routineActionsProvider.notifier).unarchive(
            routineId: 'r1',
            trainerId: _trainerId,
            athleteId: _athleteId,
          );

      final despues = await container.read(routineByIdProvider('r1').future);
      expect(despues!.status, RoutineStatus.active);
      expect(getByIdCalls, 2);
    });

    test('si el repo falla devuelve false y no propaga', () async {
      when(() => mockRepo.unarchive(any())).thenThrow(Exception('boom'));

      final container = makeContainer();
      addTearDown(container.dispose);

      final ok =
          await container.read(routineActionsProvider.notifier).unarchive(
                routineId: 'r1',
                trainerId: _trainerId,
                athleteId: _athleteId,
              );
      expect(ok, isFalse);
    });
  });

  group('RoutineActionsNotifier — la grilla de Rutinas se entera', () {
    // CANDADO. Sacar cualquiera de estas dos invalidaciones COMPILA y no rompe
    // nada visible: la rutina simplemente se queda en pantalla hasta recargar.
    // Es el mismo fallo silencioso que el comentario de `archive` ya describía
    // para la clave anterior — y volvió a pasar una mudanza de provider más
    // tarde, cuando la pantalla dejó de leer de
    // `assignedRoutinesByTrainerProvider`. Lo encontró un control negativo.

    test('archive invalida routinesAuthoredByProvider', () async {
      when(() => mockRepo.archive(any())).thenAnswer((_) async {});
      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(routinesAuthoredByProvider(_trainerId).future);
      expect(grillaCalls, 1);

      final ok = await container.read(routineActionsProvider.notifier).archive(
            routineId: 'r1',
            trainerId: _trainerId,
            athleteId: _athleteId,
          );
      expect(ok, isTrue);

      await container.read(routinesAuthoredByProvider(_trainerId).future);
      expect(grillaCalls, 2, reason: 'volvió a pedir: la card se va sola');
    });

    test('delete llama a repo.deleteRoutine e invalida la grilla', () async {
      when(() => mockRepo.deleteRoutine(any())).thenAnswer((_) async {});
      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(routinesAuthoredByProvider(_trainerId).future);
      expect(grillaCalls, 1);

      final ok = await container
          .read(routineActionsProvider.notifier)
          .delete(routineId: 'r1', trainerId: _trainerId);
      expect(ok, isTrue);
      verify(() => mockRepo.deleteRoutine('r1')).called(1);

      await container.read(routinesAuthoredByProvider(_trainerId).future);
      expect(grillaCalls, 2);
    });

    test('si el repo falla, delete devuelve false y no miente', () async {
      when(() => mockRepo.deleteRoutine(any())).thenThrow(Exception('boom'));
      final container = makeContainer();
      addTearDown(container.dispose);

      final ok = await container
          .read(routineActionsProvider.notifier)
          .delete(routineId: 'r1', trainerId: _trainerId);
      expect(ok, isFalse);
    });
  });

  group('RoutineActionsNotifier.assignTemplate', () {
    final plantilla = Routine(
      id: 'tpl-1',
      name: 'Fuerza 4x',
      level: ExperienceLevel.beginner,
      days: const [],
      source: RoutineSource.trainerTemplate,
      assignedBy: _trainerId,
      visibility: RoutineVisibility.private,
      status: RoutineStatus.active,
    );

    // COPIA, no mueve: `assignTemplateToAthlete` crea un doc nuevo y la
    // plantilla queda donde estaba. Si la consumiera, no se podría dar la
    // misma rutina a dos alumnos.
    test('copia la plantilla al alumno e invalida los DOS listados', () async {
      when(() => mockRepo.assignTemplateToAthlete(
            template: any(named: 'template'),
            athleteId: any(named: 'athleteId'),
          )).thenAnswer((_) async => plantilla);

      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(assignedRoutinesByTrainerProvider(_key).future);
      await container.read(routinesAuthoredByProvider(_trainerId).future);
      listCalls = 0;
      grillaCalls = 0;

      final ok =
          await container.read(routineActionsProvider.notifier).assignTemplate(
                template: plantilla,
                athleteId: _athleteId,
                trainerId: _trainerId,
              );
      expect(ok, isTrue);

      await container.read(assignedRoutinesByTrainerProvider(_key).future);
      await container.read(routinesAuthoredByProvider(_trainerId).future);

      // La grilla de la sección, por el doc nuevo. Y el par trainer/alumno,
      // que es de donde lee la ficha del alumno: sin eso la rutina recién
      // asignada no aparece ahí hasta recargar.
      expect(grillaCalls, 1);
      expect(listCalls, 1);
    });

    test('si el repo falla devuelve false y no rompe', () async {
      when(() => mockRepo.assignTemplateToAthlete(
            template: any(named: 'template'),
            athleteId: any(named: 'athleteId'),
          )).thenThrow(Exception('sin red'));

      final container = makeContainer();
      addTearDown(container.dispose);

      final ok =
          await container.read(routineActionsProvider.notifier).assignTemplate(
                template: plantilla,
                athleteId: _athleteId,
                trainerId: _trainerId,
              );
      expect(ok, isFalse);
    });
  });

  group('RoutineActionsNotifier.publicarComoPlantilla', () {
    const plan = Routine(
      id: 'plan-1',
      name: 'Plan de Sofía',
      level: ExperienceLevel.beginner,
      days: [],
      source: RoutineSource.trainerAssigned,
      assignedBy: _trainerId,
      assignedTo: _athleteId,
      visibility: RoutineVisibility.private,
      status: RoutineStatus.active,
    );

    void stubCreate() {
      when(() => mockRepo.createTemplate(any())).thenAnswer((i) async {
        final r = i.positionalArguments.first as Routine;
        return r.copyWith(id: 'tpl-nueva');
      });
    }

    // EL test. Las reglas denegarían publicar el documento del alumno (path 5
    // exige `trainer-template`), y aunque lo permitieran no habría que
    // hacerlo: esa copia lleva su nombre y su historial. Se publica una
    // plantilla NUEVA.
    test('crea una plantilla y publica ESA, sin tocar el plan del alumno',
        () async {
      stubCreate();
      when(() => mockRepo.publishTemplate(any())).thenAnswer((_) async {});

      final container = makeContainer();
      addTearDown(container.dispose);

      final res = await container
          .read(routineActionsProvider.notifier)
          .publicarComoPlantilla(
            plan: plan,
            nombre: 'Fuerza para principiantes',
            trainerId: _trainerId,
          );

      expect(res, ResultadoDePublicar.ok);
      verify(() => mockRepo.publishTemplate('tpl-nueva')).called(1);
      // Ni un update ni un publish sobre el documento del alumno.
      verifyNever(() => mockRepo.publishTemplate('plan-1'));
      verifyNever(() => mockRepo.updateAssigned(
            uid: any(named: 'uid'),
            draft: any(named: 'draft'),
          ));
    });

    // El nombre es el que el PF eligió, NO el del plan. Publicar expone el
    // nombre al catálogo público y un plan asignado suele llamarse por su
    // dueño: heredarlo en silencio filtraría el nombre de una clienta.
    test('la plantilla lleva el nombre elegido y nace sin alumno', () async {
      stubCreate();
      when(() => mockRepo.publishTemplate(any())).thenAnswer((_) async {});

      final container = makeContainer();
      addTearDown(container.dispose);

      await container
          .read(routineActionsProvider.notifier)
          .publicarComoPlantilla(
            plan: plan,
            nombre: 'Fuerza para principiantes',
            trainerId: _trainerId,
          );

      final creada = verify(() => mockRepo.createTemplate(captureAny()))
          .captured
          .single as Routine;
      expect(creada.name, 'Fuerza para principiantes');
      expect(creada.name, isNot(contains('Sofía')));
      expect(creada.id, isEmpty); // documento NUEVO
      expect(creada.source, RoutineSource.trainerTemplate);
      expect(creada.assignedTo, isNull);
      expect(creada.visibility, RoutineVisibility.private);
    });

    // El estado del medio, que es el que justifica que esto no devuelva bool:
    // la plantilla EXISTE. Un `false` haría que el PF reintente y termine con
    // dos.
    test('si el publish falla, dice que la plantilla igual se creó', () async {
      stubCreate();
      when(() => mockRepo.publishTemplate(any())).thenThrow(Exception('nope'));

      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(routinesAuthoredByProvider(_trainerId).future);
      grillaCalls = 0;

      final res = await container
          .read(routineActionsProvider.notifier)
          .publicarComoPlantilla(
            plan: plan,
            nombre: 'Fuerza',
            trainerId: _trainerId,
          );

      expect(res, ResultadoDePublicar.creadaPeroSinPublicar);
      verify(() => mockRepo.createTemplate(any())).called(1);

      // Y la grilla YA se enteró: la plantilla existe aunque no esté pública,
      // y si no apareciera el PF no tendría cómo publicarla a mano ni cómo
      // darse cuenta de que no hace falta repetir.
      await container.read(routinesAuthoredByProvider(_trainerId).future);
      expect(grillaCalls, 1);
    });

    // `routine_created` es el evento de TODA rutina nueva: su dartdoc dice que
    // las del PF se cuentan igual porque «omitirlas dejaría el evento ciego a
    // la mitad de las rutinas». Sin esto, las plantillas nacidas por acá
    // desaparecen de la medición de forma (días y semanas).
    test('cuenta la plantilla nueva como routine_created', () async {
      stubCreate();
      when(() => mockRepo.publishTemplate(any())).thenAnswer((_) async {});

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(routineActionsProvider.notifier).publicarComoPlantilla(
            plan: plan,
            nombre: 'Fuerza',
            trainerId: _trainerId,
          );

      final params = analytics.paramsOf('routine_created').single;
      // `trainer_template` y no `trainer_assigned`: el evento describe lo que
      // se escribió, no la pantalla desde la que se disparó. Misma trampa que
      // corrigió #1097 en el editor.
      expect(params['source'], 'trainer_template');
    });

    test('lo cuenta también si el publish falla: la plantilla existe',
        () async {
      stubCreate();
      when(() => mockRepo.publishTemplate(any())).thenThrow(Exception('nope'));

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(routineActionsProvider.notifier).publicarComoPlantilla(
            plan: plan,
            nombre: 'Fuerza',
            trainerId: _trainerId,
          );

      expect(analytics.paramsOf('routine_created'), hasLength(1));
    });

    test('si no se pudo crear, NO cuenta nada', () async {
      when(() => mockRepo.createTemplate(any())).thenThrow(Exception('boom'));

      final container = makeContainer();
      addTearDown(container.dispose);

      await container.read(routineActionsProvider.notifier).publicarComoPlantilla(
            plan: plan,
            nombre: 'Fuerza',
            trainerId: _trainerId,
          );

      expect(analytics.paramsOf('routine_created'), isEmpty);
    });

    test('si no se pudo crear, no publica nada', () async {
      when(() => mockRepo.createTemplate(any())).thenThrow(Exception('boom'));

      final container = makeContainer();
      addTearDown(container.dispose);

      final res = await container
          .read(routineActionsProvider.notifier)
          .publicarComoPlantilla(
            plan: plan,
            nombre: 'Fuerza',
            trainerId: _trainerId,
          );

      expect(res, ResultadoDePublicar.falloAlCrear);
      verifyNever(() => mockRepo.publishTemplate(any()));
    });
  });

  group('RoutineActionsNotifier.setPublicada', () {
    test('publicar llama a publishTemplate e invalida la grilla', () async {
      when(() => mockRepo.publishTemplate(any())).thenAnswer((_) async {});

      final container = makeContainer();
      addTearDown(container.dispose);
      await container.read(routinesAuthoredByProvider(_trainerId).future);
      grillaCalls = 0;

      final ok =
          await container.read(routineActionsProvider.notifier).setPublicada(
                routineId: 'tpl-1',
                publicada: true,
                trainerId: _trainerId,
              );
      expect(ok, isTrue);
      verify(() => mockRepo.publishTemplate('tpl-1')).called(1);
      verifyNever(() => mockRepo.unpublishTemplate(any()));

      await container.read(routinesAuthoredByProvider(_trainerId).future);
      expect(grillaCalls, 1);
    });

    // El flip es de UN campo en cada dirección. Si `publicada: false` llamara
    // igual a `publishTemplate`, el menú diría «Despublicar» y PUBLICARÍA —
    // el peor fallo posible acá, porque expone a la comunidad justo lo que el
    // PF quiso sacar.
    test('despublicar llama a unpublishTemplate, NO a publishTemplate',
        () async {
      when(() => mockRepo.unpublishTemplate(any())).thenAnswer((_) async {});

      final container = makeContainer();
      addTearDown(container.dispose);

      final ok =
          await container.read(routineActionsProvider.notifier).setPublicada(
                routineId: 'tpl-1',
                publicada: false,
                trainerId: _trainerId,
              );
      expect(ok, isTrue);
      verify(() => mockRepo.unpublishTemplate('tpl-1')).called(1);
      verifyNever(() => mockRepo.publishTemplate(any()));
    });

    test('si el repo falla devuelve false', () async {
      when(() => mockRepo.publishTemplate(any())).thenThrow(Exception('nope'));

      final container = makeContainer();
      addTearDown(container.dispose);

      final ok =
          await container.read(routineActionsProvider.notifier).setPublicada(
                routineId: 'tpl-1',
                publicada: true,
                trainerId: _trainerId,
              );
      expect(ok, isFalse);
    });
  });
}

Routine _makeRoutine(
  String id, {
  RoutineStatus status = RoutineStatus.active,
}) =>
    Routine(
      id: id,
      name: 'Plan',
      level: ExperienceLevel.intermediate,
      days: const [],
      status: status,
    );
