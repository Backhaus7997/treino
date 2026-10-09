// El catálogo de EXPLORAR leído con el modelo REAL, desde el mismo JSON que
// siembra `scripts/seed_templates.js`.
//
// Hasta octubre de 2026 las plantillas del sistema eran 7 y ninguna traía
// `sets`, `weeklySets`, `numWeeks`, `durationSeconds` ni `supersetGroup`: eran
// todas formato legacy. Las 43 nuevas son las primeras que llegan con el
// formato que escribe el editor. Este test es lo que dice que el modelo las
// lee enteras y no se queda con la mitad en silencio — un `fromJson` que
// ignora una clave no tira, devuelve el default.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/set_enums.dart';

void main() {
  late List<Map<String, dynamic>> plantillas;

  setUpAll(() {
    plantillas = (jsonDecode(
      File('docs/video-catalog-audit/improved-templates.json')
          .readAsStringSync(),
    ) as List<dynamic>)
        .cast<Map<String, dynamic>>();
  });

  // Mismo armado que `RoutineRepository._fromDoc`: el doc más su id.
  Routine parsear(Map<String, dynamic> t) =>
      Routine.fromJson({...t, 'id': t['id']});

  test('son 50 y los ids no se repiten', () {
    expect(plantillas, hasLength(50));
    expect(plantillas.map((t) => t['id']).toSet(), hasLength(50));
  });

  test('las 50 parsean con el modelo real sin tirar', () {
    for (final t in plantillas) {
      expect(() => parsear(t), returnsNormally, reason: '${t['id']}');
    }
  });

  test('numWeeks y weeklySets llegan enteros, semana por semana', () {
    final multiSemana = <String>[];
    for (final t in plantillas) {
      final rutina = parsear(t);
      final semanas = (t['numWeeks'] as int?) ?? 1;
      expect(rutina.numWeeks, semanas, reason: '${t['id']}');
      if (semanas > 1) multiSemana.add(rutina.id);

      final dias = t['days'] as List<dynamic>;
      for (var d = 0; d < dias.length; d++) {
        final slotsJson = (dias[d] as Map)['slots'] as List<dynamic>;
        for (var s = 0; s < slotsJson.length; s++) {
          final json = slotsJson[s] as Map<String, dynamic>;
          final slot = rutina.days[d].slots[s];
          final donde = '${t['id']} día ${d + 1} slot ${s + 1}';

          final weeklyJson = json['weeklySets'] as List<dynamic>?;
          if (weeklyJson != null) {
            expect(slot.weeklySets, hasLength(weeklyJson.length),
                reason: donde);
            if (semanas > 1) {
              expect(slot.weeklySets, hasLength(semanas),
                  reason: '$donde: una entrada de weeklySets por semana');
            }
            for (var w = 0; w < weeklyJson.length; w++) {
              final setsJson = (weeklyJson[w] as Map)['sets'] as List<dynamic>;
              expect(slot.weeklySets[w], hasLength(setsJson.length),
                  reason: '$donde semana ${w + 1}');
            }
          }
          final setsJson = json['sets'] as List<dynamic>?;
          if (setsJson != null) {
            expect(slot.sets, hasLength(setsJson.length), reason: donde);
          }
        }
      }
    }
    expect(
      multiSemana,
      unorderedEquals([
        'ondas-fuerza-3dias-principiante',
        'ondas-fuerza-5x10-intermedio',
        'ondas-fuerza-triunvirato-intermedio',
        'especializacion-sentadilla-avanzado',
      ]),
    );
  });

  test('superseries, modo duración y tipos de serie no caen al default', () {
    var superseries = 0, duracion = 0, alFallo = 0, calor = 0;
    for (final t in plantillas) {
      final rutina = parsear(t);
      final dias = t['days'] as List<dynamic>;
      for (var d = 0; d < dias.length; d++) {
        final slotsJson = (dias[d] as Map)['slots'] as List<dynamic>;
        for (var s = 0; s < slotsJson.length; s++) {
          final json = slotsJson[s] as Map<String, dynamic>;
          final slot = rutina.days[d].slots[s];
          final donde = '${t['id']} día ${d + 1} slot ${s + 1}';

          expect(slot.supersetGroup, json['supersetGroup'], reason: donde);
          if (slot.supersetGroup != null) superseries++;

          expect(slot.durationSeconds, json['durationSeconds'], reason: donde);
          if (json['exerciseMode'] == 'duration') {
            duracion++;
            expect(slot.exerciseMode, ExerciseMode.duration, reason: donde);
            expect(slot.effectiveExerciseMode, ExerciseMode.duration,
                reason: donde);
          }

          final tipos = [
            for (final set in (json['sets'] as List<dynamic>? ?? const []))
              (set as Map)['type'] as String? ?? 'normal',
          ];
          expect(slot.sets.map((x) => x.type.name).toList(), tipos,
              reason: donde);
          alFallo += slot.sets.where((x) => x.type == SetType.failure).length;
          calor += slot.sets.where((x) => x.type == SetType.warmup).length;
        }
      }
    }
    // Pisos y no conteos exactos: lo que se cuida es que el parseo no los
    // pierda, no cuántos decidió poner quien armó el catálogo.
    expect(superseries, greaterThan(0));
    expect(duracion, greaterThan(0));
    expect(alFallo, greaterThan(0));
    expect(calor, greaterThan(0));
  });

  test('las tres de muestra de la spec llegan como se diseñaron', () {
    Routine porId(String id) =>
        parsear(plantillas.firstWhere((t) => t['id'] == id));

    final ondas = porId('ondas-fuerza-5x10-intermedio');
    expect(ondas.numWeeks, 4);
    expect(
      ondas.days.expand((d) => d.slots).any((s) => s.weeklySets.length == 4),
      isTrue,
    );

    final gvt = porId('volumen-10x10-avanzado');
    final pareadas = gvt.days
        .expand((d) => d.slots)
        .where((s) => s.supersetGroup != null && s.effectiveSets.length == 10);
    expect(pareadas, isNotEmpty);

    final hit = porId('alta-intensidad-1-serie-avanzado');
    final tipos = hit.days
        .expand((d) => d.slots)
        .expand((s) => s.effectiveSets)
        .map((x) => x.type)
        .toSet();
    expect(tipos, containsAll([SetType.warmup, SetType.failure]));
  });
}
