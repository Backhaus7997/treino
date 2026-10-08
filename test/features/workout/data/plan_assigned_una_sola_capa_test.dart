import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';

/// Registra cada `plan_assigned` en vez de mandarlo a Firebase.
class _AnalyticsEspia extends NoopAnalyticsService {
  const _AnalyticsEspia(this.emitidos);

  final List<({String routineId, String assignedBy, String assignedTo})>
      emitidos;

  @override
  Future<void> logPlanAssigned({
    required String routineId,
    required String assignedBy,
    required String assignedTo,
  }) async {
    emitidos.add((
      routineId: routineId,
      assignedBy: assignedBy,
      assignedTo: assignedTo,
    ));
  }
}

Routine _plan({
  String id = '',
  RoutineSource source = RoutineSource.trainerAssigned,
  String? assignedBy = 'pf-1',
  String? assignedTo = 'alumno-1',
}) =>
    Routine(
      id: id,
      name: 'Full body',
      level: ExperienceLevel.beginner,
      days: const [],
      source: source,
      assignedBy: assignedBy,
      assignedTo: assignedTo,
      visibility: RoutineVisibility.private,
    );

void main() {
  group('createAssigned emite plan_assigned', () {
    late FakeFirebaseFirestore firestore;
    late List<({String routineId, String assignedBy, String assignedTo})>
        emitidos;
    late RoutineRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      emitidos = [];
      repo = RoutineRepository(
        firestore: firestore,
        analytics: _AnalyticsEspia(emitidos),
      );
    });

    test('una asignación directa emite UNA vez, con el id que quedó escrito',
        () async {
      final creada = await repo.createAssigned(_plan());

      expect(emitidos, hasLength(1));
      expect(emitidos.single.routineId, equals(creada.id));
      expect(emitidos.single.routineId, isNotEmpty);
      expect(emitidos.single.assignedBy, equals('pf-1'));
      expect(emitidos.single.assignedTo, equals('alumno-1'));
    });

    test('asignar una PLANTILLA también emite — pasa por el mismo embudo',
        () async {
      // Es el camino de la card del Coach Hub y del `trainer_workout_view`:
      // `assignTemplateToAthlete` → `createAssigned`. Ninguno de los dos emitía
      // el evento antes de este cambio.
      await repo.assignTemplateToAthlete(
        template: _plan(
          id: 'tpl-1',
          source: RoutineSource.trainerTemplate,
          assignedTo: null,
        ),
        athleteId: 'alumno-2',
      );

      expect(emitidos, hasLength(1));
      expect(emitidos.single.assignedTo, equals('alumno-2'));
      expect(emitidos.single.assignedBy, equals('pf-1'));
    });

    test('una escritura que NO es asignación no emite nada', () async {
      // `createTemplate` es una plantilla sin alumno: no es una asignación.
      await repo.createTemplate(_plan(
        source: RoutineSource.trainerTemplate,
        assignedTo: null,
      ));

      expect(emitidos, isEmpty);
    });

    test('si las guardas rechazan la rutina, no se emite', () async {
      await expectLater(
        repo.createAssigned(_plan(assignedTo: '')),
        throwsArgumentError,
      );
      expect(emitidos, isEmpty,
          reason:
              'se emitió un plan_assigned por una escritura que ni ocurrió');
    });
  });

  // ─── Los dos scanners que impiden que el agujero vuelva ────────────────────

  group('plan_assigned vive en UNA sola capa', () {
    /// El path con barras normales, venga de donde venga.
    ///
    /// ⚠️ Sin esto el guard MIENTE en Windows, y miente del lado caro: reporta
    /// como culpables a los dos archivos que debería excluir. `File.path` trae
    /// `\` acá, así que un `endsWith('core/analytics/…')` no matchea nunca, el
    /// `where` no filtra nada, y el `continue` del bucle no corta.
    ///
    /// Resultado: rojo en el Windows local y verde en el CI de Linux — que es
    /// el que tiene razón. Los otros nueve guards del repo ya normalizan así
    /// (`no_material_button_scan_test.dart`, `no_raw_clock_scan_test.dart`,
    /// `superficie_de_cobro_alumno_test.dart`…); a éste se le pasó.
    String ruta(File f) => f.path.replaceAll(r'\', '/');

    /// Todos los `.dart` de `lib/`, salvo la definición del propio evento.
    List<File> fuentesDeApp() => Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => ruta(f).endsWith('.dart'))
        .where(
            (f) => !ruta(f).endsWith('core/analytics/analytics_service.dart'))
        .toList();

    test('sólo el repositorio llama a logPlanAssigned', () {
      final culpables = <String>[];
      for (final archivo in fuentesDeApp()) {
        if (!archivo.readAsStringSync().contains('logPlanAssigned(')) continue;
        if (ruta(archivo).endsWith('workout/data/routine_repository.dart')) {
          continue;
        }
        culpables.add(ruta(archivo));
      }

      expect(
        culpables,
        isEmpty,
        reason: 'plan_assigned se emite fuera del repositorio en:\n'
            '${culpables.join('\n')}\n\n'
            'Sumarlo en una pantalla lo cuenta DOS veces desde ahí y una sola '
            'desde los otros cuatro caminos. Si falta un caso, el arreglo va '
            'en RoutineRepository.createAssigned.',
      );
    });

    test('producción construye el repo CON analytics', () {
      final sinAnalytics = <String>[];
      for (final archivo in fuentesDeApp()) {
        final texto = archivo.readAsStringSync();
        if (!texto.contains('RoutineRepository(')) continue;
        // La declaración del constructor no es una construcción.
        if (ruta(archivo).endsWith('workout/data/routine_repository.dart')) {
          continue;
        }
        if (!texto.contains('analytics:')) sinAnalytics.add(ruta(archivo));
      }

      expect(
        sinAnalytics,
        isEmpty,
        reason: 'se construye RoutineRepository sin `analytics:` en:\n'
            '${sinAnalytics.join('\n')}\n\n'
            'El default es NoopAnalyticsService, así que el evento se perdería '
            'en silencio — el mismo modo de falla que este cambio vino a tapar.',
      );
    });
  });
}
