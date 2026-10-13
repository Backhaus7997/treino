// Búsqueda por texto de EXPLORAR (#1412) contra el catálogo REAL de 50
// plantillas, el mismo JSON que siembra `scripts/seed_templates.js`.
//
// Con fixtures a mano se prueba la regla; acá importa otra pregunta: con lo
// que de verdad se siembra, ¿"pecho" encuentra plantillas que lo trabajan
// aunque el nombre no lo diga?

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/template_search.dart';

bool _trains(Routine r, Set<String> groups) => r.days.any(
      (d) => d.slots.any((s) => groups.contains(s.muscleGroup)),
    );

RoutineSlot _slot(String name, String group) => RoutineSlot(
      exerciseId: name,
      exerciseName: name,
      muscleGroup: group,
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: 60,
    );

Routine _routine(
  String name, {
  ExperienceLevel level = ExperienceLevel.beginner,
  List<RoutineDay> days = const [],
}) =>
    Routine(id: name, name: name, level: level, days: days);

void main() {
  late List<Routine> catalogo;

  setUpAll(() {
    catalogo = (jsonDecode(
      File('docs/video-catalog-audit/improved-templates.json')
          .readAsStringSync(),
    ) as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .map(Routine.fromJson)
        .toList();
  });

  List<Routine> buscar(String q) =>
      TemplateSearch.filter(catalogo, q, (r) => r);

  group('catálogo real', () {
    test('el catálogo tiene las 50 plantillas', () {
      expect(catalogo, hasLength(50));
    });

    test('"pecho" devuelve plantillas que lo trabajan aunque no lo digan', () {
      final res = buscar('pecho');
      final sinEnNombre = res.where(
        (r) => !TemplateSearch.normalize(r.name).contains('pecho'),
      );
      expect(sinEnNombre, isNotEmpty);
      for (final r in sinEnNombre) {
        expect(_trains(r, {'chest'}), isTrue, reason: r.name);
      }
    });

    test('"pecho" no trae plantillas que no entrenan pecho', () {
      final res = buscar('pecho').toSet();
      final fuera = catalogo.where((r) => !res.contains(r));
      expect(fuera, isNotEmpty);
      for (final r in fuera) {
        expect(_trains(r, {'chest'}), isFalse, reason: r.name);
      }
    });

    for (final caso in {
      'piernas': {'quads', 'hamstrings', 'glutes', 'calves'},
      'glúteos': {'glutes'},
      'espalda': {'back'},
      'hombros': {'shoulders'},
      'brazos': {'biceps', 'triceps'},
      'abdomen': {'core'},
    }.entries) {
      test('"${caso.key}" encuentra todo lo que entrena esos grupos', () {
        final res = buscar(caso.key).toSet();
        expect(res, isNotEmpty);
        for (final r in catalogo) {
          if (_trains(r, caso.value)) {
            expect(res, contains(r), reason: '${r.name} debería aparecer');
          }
        }
      });
    }

    test('ignora mayúsculas y acentos: GLUTEOS = glúteos = Glúteos', () {
      final a = buscar('GLUTEOS');
      expect(a, isNotEmpty);
      expect(buscar('glúteos'), a);
      expect(buscar('Glúteos'), a);
      expect(buscar('gluteos'), a);
    });

    test('tolera plural: "pierna" = "piernas", "glúteo" = "glúteos"', () {
      expect(buscar('pierna'), buscar('piernas'));
      expect(buscar('gluteo'), buscar('gluteos'));
    });

    test('encuentra por nombre de ejercicio', () {
      final res = buscar('sentadilla');
      expect(res, isNotEmpty);
      for (final r in res) {
        final nombres = r.days
            .expand((d) => d.slots)
            .map((s) => TemplateSearch.normalize(s.exerciseName));
        expect(
          nombres.any((n) => n.contains('sentadilla')) ||
              TemplateSearch.normalize(r.name).contains('sentadilla'),
          isTrue,
          reason: r.name,
        );
      }
    });

    test('encuentra por nombre de plantilla y por nivel', () {
      expect(buscar('powerlifting'), isNotEmpty);
      final principiantes = buscar('principiante');
      expect(principiantes, isNotEmpty);
      expect(
        principiantes.every((r) => r.level == ExperienceLevel.beginner),
        isTrue,
      );
    });

    test('varias palabras se combinan con AND, en cualquier orden', () {
      final ambas = buscar('pecho espalda').toSet();
      expect(ambas, isNotEmpty);
      expect(ambas, buscar('espalda pecho').toSet());
      expect(ambas.length, lessThanOrEqualTo(buscar('pecho').length));
      for (final r in ambas) {
        expect(_trains(r, {'chest'}), isTrue, reason: r.name);
        expect(_trains(r, {'back'}), isTrue, reason: r.name);
      }
    });

    test('sin resultados: texto que no existe', () {
      expect(buscar('zzzxqw'), isEmpty);
    });

    test('consulta en blanco o sólo relleno devuelve todo, en orden', () {
      expect(buscar(''), catalogo);
      expect(buscar('   '), catalogo);
      expect(buscar('de la y'), catalogo);
    });

    test('conserva el orden de entrada entre los resultados', () {
      final invertido = catalogo.reversed.toList();
      final res = TemplateSearch.filter(invertido, 'pecho', (r) => r);
      final posiciones = res.map(invertido.indexOf).toList();
      expect(posiciones, [...posiciones]..sort());
    });
  });

  group('reglas', () {
    final ppl = _routine(
      'Push Pull Legs',
      days: [
        RoutineDay(
          dayNumber: 1,
          name: 'Push',
          slots: [_slot('Press de banca', 'chest')],
        ),
        RoutineDay(
          dayNumber: 2,
          name: 'Legs',
          slots: [_slot('Sentadilla', 'quads')],
        ),
      ],
    );

    test('músculo vía sinónimo cuando el nombre no lo dice', () {
      expect(TemplateSearch.matches(ppl, 'pecho'), isTrue);
      expect(TemplateSearch.matches(ppl, 'piernas'), isTrue);
      expect(TemplateSearch.matches(ppl, 'espalda'), isFalse);
    });

    test('prefijo mientras se tipea', () {
      expect(TemplateSearch.matches(ppl, 'sentad'), isTrue);
      expect(TemplateSearch.matches(ppl, 'pec'), isTrue);
    });

    test('nombre de día', () {
      expect(TemplateSearch.matches(ppl, 'legs'), isTrue);
    });

    test('stem', () {
      expect(TemplateSearch.stem('piernas'), 'pierna');
      expect(TemplateSearch.stem('flexiones'), 'flexion');
      expect(TemplateSearch.stem('pesas'), 'pesa');
      expect(TemplateSearch.stem('abs'), 'abs');
    });
  });
}
