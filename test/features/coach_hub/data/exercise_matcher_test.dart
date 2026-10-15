import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/data/excel_parser.dart';
import 'package:treino/features/coach_hub/data/exercise_matcher.dart';

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

List<RawParsedDay> _dayWith(List<String> names) => [
      RawParsedDay(
        dayNumber: 1,
        items: names
            .map((n) => RawParsedItem(
                  rowName: n,
                  sets: 4,
                  repsMin: 8,
                  repsMax: 10,
                ))
            .toList(),
      ),
    ];

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
  });
}
