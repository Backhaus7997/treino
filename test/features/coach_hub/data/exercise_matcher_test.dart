import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/data/exercise_matcher.dart';

import 'match_names_helper.dart';

final _exercises = [
  MatcherExercise(
      id: 'sentadilla-barra',
      name: 'Sentadilla con barra',
      muscleGroup: 'Piernas'),
  MatcherExercise(id: 'press-banca', name: 'Press banca', muscleGroup: 'Pecho'),
  MatcherExercise(
      id: 'peso-muerto', name: 'Peso muerto', muscleGroup: 'Espalda'),
];

final _exercisesWithAliases = [
  MatcherExercise(
    id: 'back-squat',
    name: 'Back Squat',
    muscleGroup: 'Piernas',
    aliases: const ['Sentadilla', 'Sentadilla con barra', 'Squat trasero'],
  ),
  MatcherExercise(
    id: 'bench-press',
    name: 'Bench Press',
    muscleGroup: 'Pecho',
    aliases: const ['Press banca', 'Press plano'],
  ),
];

List<String> _dayWith(List<String> names) => namesOf(names);

void main() {
  group('normalize', () {
    test('quita acentos y baja a minúsculas', () {
      expect(normalize('Sentadilla con Barra'), 'sentadilla con barra');
      expect(normalize('Día 1: Tracción'), 'dia 1 traccion');
    });
  });

  group('matchExercises', () {
    test('match exacto por nombre', () {
      final result =
          matchExercises(_dayWith(['Sentadilla con barra']), _exercises);
      expect(result.unmatched, isEmpty);
      expect(result.days.first.items.first.exerciseId, 'sentadilla-barra');
      expect(result.days.first.items.first.muscleGroup, 'Piernas');
    });

    test('match insensible a mayúsculas y acentos', () {
      final result =
          matchExercises(_dayWith(['SENTADILLA CON BARRA']), _exercises);
      expect(result.days.first.items.first.exerciseId, 'sentadilla-barra');
    });

    test('no matchea ejercicio totalmente distinto', () {
      final result = matchExercises(_dayWith(['Curl bíceps']), _exercises);
      expect(result.unmatched, hasLength(1));
      expect(result.unmatched.first.rowName, 'Curl bíceps');
      expect(result.days.first.items.first.exerciseId, isNull);
      expect(result.days.first.items.first.exerciseName, 'Curl bíceps');
    });

    test('mantiene cantidad de items por día', () {
      final result = matchExercises(
        _dayWith(['Sentadilla con barra', 'Press banca', 'Algo raro xyz']),
        _exercises,
      );
      expect(result.days.first.items, hasLength(3));
      expect(result.unmatched, hasLength(1));
    });

    test('match por alias en español contra catálogo en inglés', () {
      final result =
          matchExercises(_dayWith(['Sentadilla']), _exercisesWithAliases);
      expect(result.unmatched, isEmpty);
      expect(result.days.first.items.first.exerciseId, 'back-squat');
      expect(result.days.first.items.first.exerciseName, 'Back Squat');
    });

    test('match alias insensible a mayúsculas y acentos', () {
      final result = matchExercises(
        _dayWith(['SENTADILLA CON BARRA', 'Press plano']),
        _exercisesWithAliases,
      );
      expect(result.unmatched, isEmpty);
      expect(result.days.first.items[0].exerciseId, 'back-squat');
      expect(result.days.first.items[1].exerciseId, 'bench-press');
    });

    test('fuzzy queda pendiente como sugerencia y nunca se autoasigna', () {
      final result = matchExercises(
        _dayWith(['Press banca pesado']),
        _exercises,
      );
      final item = result.days.single.items.single;

      expect(item.exerciseId, isNull);
      expect(item.exerciseName, 'Press banca pesado');
      expect(item.suggestedExerciseId, 'press-banca');
      expect(item.suggestedExerciseName, 'Press banca');
      expect(result.unmatched, hasLength(1));
    });

    test('stopwords no suman coincidencias', () {
      final result = matchExercises(
        _dayWith(['Remo con']),
        [MatcherExercise(id: 'sentadilla', name: 'Sentadilla con')],
      );

      expect(result.days.single.items.single.suggestedExerciseId, isNull);
    });

    test('no sugiere el falso positivo medido de remo con mancuerna', () {
      final result = matchExercises(
        _dayWith(['Remo con mancuerna']),
        [
          MatcherExercise(
            id: 'sentadilla-goblet',
            name: 'Sentadilla goblet con mancuerna',
          ),
        ],
      );

      expect(result.days.single.items.single.suggestedExerciseId, isNull);
    });

    test('equipo distinto o ausente impide sugerir', () {
      final result = matchExercises(
        _dayWith([
          'Sentadilla con banda',
          'Sentadilla con pesa rusa',
          'Remo con mancuerna',
        ]),
        [
          MatcherExercise(
            id: 'sentadilla-barra',
            name: 'Sentadilla con barra',
          ),
          MatcherExercise(id: 'remo', name: 'Remo'),
        ],
      );

      for (final item in result.days.single.items) {
        expect(item.exerciseId, isNull);
        expect(item.suggestedExerciseId, isNull, reason: item.rowName);
      }
    });

    test('sinónimos del mismo equipo sí son compatibles', () {
      final result = matchExercises(
        _dayWith(['Swing con pesa rusa pesado']),
        [
          MatcherExercise(id: 'swing', name: 'Swing con kettlebell'),
        ],
      );

      expect(result.days.single.items.single.exerciseId, isNull);
      expect(result.days.single.items.single.suggestedExerciseId, 'swing');
    });

    test('calificador de variante presente de un solo lado impide sugerir', () {
      final result = matchExercises(
        _dayWith([
          'Sentadilla búlgara',
          'Press de banca inclinado',
          'Peso muerto convencional',
        ]),
        [
          MatcherExercise(
            id: 'sentadilla-barra',
            name: 'Sentadilla con barra',
          ),
          MatcherExercise(
            id: 'press-barra',
            name: 'Press de banca con barra',
          ),
          MatcherExercise(
            id: 'peso-rumano',
            name: 'Peso muerto rumano',
          ),
        ],
      );

      for (final item in result.days.single.items) {
        expect(item.exerciseId, isNull);
        expect(item.suggestedExerciseId, isNull, reason: item.rowName);
      }
    });

    test('empate de score no elige candidato arbitrariamente', () {
      final result = matchExercises(
        _dayWith(['Press de pecho']),
        [
          MatcherExercise(id: 'press-1', name: 'Press pecho máquina'),
          MatcherExercise(id: 'press-2', name: 'Press pecho polea'),
        ],
      );

      expect(result.days.single.items.single.exerciseId, isNull);
      expect(result.days.single.items.single.suggestedExerciseId, isNull);
    });

    test('catálogo medido: ningún caso conocido cae en la variante equivocada',
        () {
      final catalog = [
        MatcherExercise(id: 'sq-barra', name: 'Sentadilla con barra'),
        MatcherExercise(id: 'pb-barra', name: 'Press de banca con barra'),
        MatcherExercise(id: 'pm-rumano', name: 'Peso muerto rumano'),
        MatcherExercise(
          id: 'sq-goblet',
          name: 'Sentadilla goblet con mancuerna',
        ),
      ];
      final result = matchExercises(
        _dayWith([
          'Sentadilla con banda',
          'Sentadilla con pesa rusa',
          'Sentadilla búlgara',
          'Press de banca inclinado',
          'Peso muerto convencional',
          'Remo con mancuerna',
        ]),
        catalog,
      );
      for (final item in result.days.single.items) {
        expect(item.exerciseId, isNull, reason: item.rowName);
        expect(item.suggestedExerciseId, isNull, reason: item.rowName);
      }
      expect(result.unmatched, hasLength(6));
    });

    test('la compatibilidad se evalúa por etiqueta, no por la unión', () {
      final result = matchExercises(
        _dayWith(['Sentadilla pesada']),
        [
          MatcherExercise(
            id: 'sq',
            name: 'Sentadilla',
            aliases: const ['Sentadilla goblet'],
          ),
        ],
      );
      // El alias goblet no contamina el nombre base: "Sentadilla" sí es
      // compatible con una consulta sin calificador.
      expect(result.days.single.items.single.suggestedExerciseId, 'sq');
    });

    test('alias exacto ("Back squat") se autoasigna', () {
      final result = matchExercises(
        _dayWith(['Squat trasero']),
        _exercisesWithAliases,
      );
      expect(result.unmatched, isEmpty);
      expect(result.days.single.items.single.exerciseId, 'back-squat');
    });
  });

  group('veto público y candidatos externos', () {
    final catalog = [
      MatcherExercise(
        id: 'banca-barra',
        name: 'Press banca con barra',
        aliases: const ['Bench press'],
      ),
      MatcherExercise(id: 'banca-manc', name: 'Press banca con mancuernas'),
      MatcherExercise(id: 'rumano', name: 'Peso muerto rumano'),
    ];

    test('isCompatibleLabel normaliza y veta equipo y variante', () {
      expect(isCompatibleLabel('PRESS BANCA c/ barra', 'Press banca'), isFalse);
      expect(
          isCompatibleLabel('Press banca barbell', 'Press con barra'), isTrue);
      expect(isCompatibleLabel('Peso muerto', 'Peso muerto rumano'), isFalse);
    });

    test('candidato compatible: se devuelve como sugerencia', () {
      final m = ExerciseNameMatcher(catalog);
      expect(
        m
            .suggestFromCandidate('banca-barra', 'Press banca plano con barra')
            ?.id,
        isNull, // "plano" es variante y la etiqueta no la declara
      );
      expect(m.suggestFromCandidate('banca-barra', 'Banca con barra')?.id,
          'banca-barra');
    });

    test('alcanza con que UNA etiqueta pase el veto', () {
      final m = ExerciseNameMatcher(catalog);
      // "Bench press" no declara equipo, pero el query tampoco.
      expect(m.suggestFromCandidate('banca-barra', 'Bench press')?.id,
          'banca-barra');
    });

    test('equipo distinto: vetado', () {
      final m = ExerciseNameMatcher(catalog);
      expect(m.suggestFromCandidate('banca-manc', 'Press banca con barra'),
          isNull);
    });

    test('id que no existe en el catálogo: null', () {
      final m = ExerciseNameMatcher(catalog);
      expect(m.suggestFromCandidate('inventado', 'Press banca'), isNull);
    });
  });
}
