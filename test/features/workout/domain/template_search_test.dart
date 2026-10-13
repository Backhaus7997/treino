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

double _share(Routine r, Set<String> groups) {
  final slots = r.days.expand((d) => d.slots).toList();
  if (slots.isEmpty) return 0;
  return slots.where((s) => groups.contains(s.muscleGroup)).length /
      slots.length;
}

bool _nameHas(Routine r, String word) {
  final texts = [r.name, r.split ?? '', ...r.days.map((d) => d.name)];
  return texts.any((t) => TemplateSearch.normalize(t).contains(word));
}

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

    test('"pecho" no trae plantillas que no lo entrenan ni lo nombran', () {
      final res = buscar('pecho').toSet();
      final fuera = catalogo.where((r) => !res.contains(r));
      expect(fuera, isNotEmpty);
      for (final r in catalogo) {
        if (res.contains(r)) {
          expect(_trains(r, {'chest'}) || _nameHas(r, 'pecho'), isTrue);
        }
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
      test('"${caso.key}" trae las que lo entrenan >=10% y ninguna que no', () {
        final res = buscar(caso.key).toSet();
        expect(res, isNotEmpty);
        for (final r in catalogo) {
          if (_share(r, caso.value) >= 0.10) {
            expect(res, contains(r), reason: '${r.name} debería aparecer');
          }
          if (!_trains(r, caso.value) && !_nameHas(r, 'brazo')) {
            expect(res, isNot(contains(r)), reason: r.name);
          }
        }
      });
    }

    test('"pecho": las que lo dicen en nombre/días van antes que el resto', () {
      final res = buscar('pecho');
      final enNombre = res.where((r) => _nameHas(r, 'pecho')).toList();
      expect(enNombre, isNotEmpty);
      final nombres = res.take(enNombre.length).toSet();
      expect(nombres, enNombre.toSet());
      // Y se nombran las de la auditoría.
      final top = res.take(enNombre.length).map((r) => r.name).join('|');
      expect(top, contains('Bro Split'));
      expect(top, contains('Split Clásico 6 Días'));
    });

    test('"pecho": las que sólo lo entrenan van por participación desc', () {
      final res = buscar('pecho');
      // Puntaje < 500 = sólo por músculo (debajo de nombre y ejercicio).
      final soloMusculo =
          res.where((r) => TemplateSearch.score(r, 'pecho')! < 500).toList();
      expect(soloMusculo.length, greaterThan(3));
      final shares = soloMusculo.map((r) => _share(r, {'chest'})).toList();
      expect(shares, [...shares]..sort((a, b) => b.compareTo(a)));
    });

    test('"pecho" descarta Glúteos Foco (1 de 27 slots) y ruido <10%', () {
      final res = buscar('pecho');
      expect(
          res.map((r) => r.name), isNot(contains(startsWith('Glúteos Foco'))));
      for (final r in res) {
        expect(
          _share(r, {'chest'}) >= 0.10 || _nameHas(r, 'pecho'),
          isTrue,
          reason: r.name,
        );
      }
      expect(res.length, lessThan(46));
    });

    test('"gluteos": Glúteos Foco y Glúteos y Piernas encabezan', () {
      final res = buscar('gluteos');
      expect(
        res.take(2).map((r) => r.name.split(' — ').first).toSet(),
        {'Glúteos Foco', 'Glúteos y Piernas'},
      );
    });

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

    test('consulta en blanco no reordena', () {
      final invertido = catalogo.reversed.toList();
      expect(TemplateSearch.filter(invertido, '', (r) => r), invertido);
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

    test('empate de puntaje: gana el orden de entrada (afinidad)', () {
      final a = _routine('Alfa', days: [
        RoutineDay(dayNumber: 1, name: 'D', slots: [_slot('X', 'chest')]),
      ]);
      final b = _routine('Beta', days: [
        RoutineDay(dayNumber: 1, name: 'D', slots: [_slot('Y', 'chest')]),
      ]);
      expect(TemplateSearch.filter([a, b], 'pecho', (r) => r), [a, b]);
      expect(TemplateSearch.filter([b, a], 'pecho', (r) => r), [b, a]);
    });

    test('tiers: nombre > ejercicio > músculo > nivel', () {
      final nombre = _routine('Pecho total', days: [
        RoutineDay(dayNumber: 1, name: 'D', slots: [_slot('X', 'back')]),
      ]);
      final ejercicio = _routine('E', days: [
        RoutineDay(
            dayNumber: 1, name: 'D', slots: [_slot('Press de pecho', 'chest')]),
      ]);
      final musculo = _routine('M', days: [
        RoutineDay(dayNumber: 1, name: 'D', slots: [_slot('Z', 'chest')]),
      ]);
      final lista = [musculo, ejercicio, nombre];
      expect(
        TemplateSearch.filter(lista, 'pecho', (r) => r),
        [nombre, ejercicio, musculo],
      );
    });

    test('corte: músculo con <10% de los slots no matchea; por nombre sí', () {
      final slots = [
        _slot('A', 'chest'),
        for (var i = 0; i < 19; i++) _slot('B$i', 'quads'),
      ];
      final debil = _routine('Piernas', days: [
        RoutineDay(dayNumber: 1, name: 'D', slots: slots),
      ]);
      expect(TemplateSearch.matches(debil, 'pecho'), isFalse);
      final porNombre = _routine('Pecho', days: debil.days);
      expect(TemplateSearch.matches(porNombre, 'pecho'), isTrue);
    });

    test('stem', () {
      expect(TemplateSearch.stem('piernas'), 'pierna');
      expect(TemplateSearch.stem('flexiones'), 'flexion');
      expect(TemplateSearch.stem('pesas'), 'pesa');
      expect(TemplateSearch.stem('abs'), 'abs');
    });
  });
}
