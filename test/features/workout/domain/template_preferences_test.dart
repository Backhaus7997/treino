import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/muscle_group.dart';
import 'package:treino/features/workout/domain/routine_goal.dart';
import 'package:treino/features/workout/domain/template_preferences.dart';

void main() {
  group('TemplatePreferences — decoding', () {
    test('reads a full document written by this build', () {
      final prefs = TemplatePreferences.fromJson(const {
        'daysPerWeek': 3,
        'minutesPerSession': 45,
        'goals': ['health', 'sport'],
        'goal': 'health',
        'priorityMuscleGroups': ['back', 'core'],
      });

      expect(prefs.daysPerWeek, 3);
      expect(prefs.minutesPerSession, 45);
      expect(prefs.goals, [RoutineGoal.health, RoutineGoal.sport]);
      expect(
        prefs.priorityGroups,
        [MuscleGroup.espalda, MuscleGroup.abdominales],
      );
    });

    test('an absent field stays null rather than defaulted', () {
      final prefs = TemplatePreferences.fromJson(const {});

      expect(prefs.daysPerWeek, isNull);
      expect(prefs.minutesPerSession, isNull);
      expect(prefs.goals, isEmpty);
      expect(prefs.priorityMuscleGroups, isEmpty);
      expect(prefs.isEmpty, isTrue);
    });

    test('a goal this build does not know reads as NO preference', () {
      // The failure this guards: `$enumDecodeNullable` throws on an unknown
      // key by default, and this model is decoded as part of `UserProfile`.
      // One goal value added by a newer build would take down the whole
      // profile stream on every older client and route them to
      // `/profile-unavailable` (#544) — over a field that is optional by
      // design.
      final prefs = TemplatePreferences.fromJson(const {
        'daysPerWeek': 4,
        'goal': 'powerlifting_meet',
      });

      expect(prefs.goals, isEmpty, reason: 'unknown ⇒ neutral, never a crash');
      expect(prefs.daysPerWeek, 4, reason: 'the rest of the answers survive');
    });

    test('a legacy doc written by the 1.0 (only `goal`) reads as [goal]', () {
      final prefs = TemplatePreferences.fromJson(const {'goal': 'health'});
      expect(prefs.goals, [RoutineGoal.health]);
      expect(prefs.isEmpty, isFalse);
    });

    test('an empty `goals` falls back to the legacy `goal`', () {
      final prefs = TemplatePreferences.fromJson(const {
        'goals': <String>[],
        'goal': 'sport',
      });
      expect(prefs.goals, [RoutineGoal.sport]);
    });

    test('unknown values inside `goals` are dropped, the rest survive', () {
      final prefs = TemplatePreferences.fromJson(const {
        'goals': ['powerlifting_meet', 'aesthetics', 42],
        'goal': 'powerlifting_meet',
      });
      expect(prefs.goals, [RoutineGoal.aesthetics]);
    });

    group('reconciliación con una edición de la 1.0 (merge profundo)', () {
      test('goal == goals.first ⇒ vale goals', () {
        final prefs = TemplatePreferences.fromJson(const {
          'goals': ['health', 'aesthetics'],
          'goal': 'health',
        });
        expect(prefs.goals, [RoutineGoal.health, RoutineGoal.aesthetics]);
      });

      test('goal distinto del primero ⇒ la 1.0 editó después, gana goal', () {
        final prefs = TemplatePreferences.fromJson(const {
          'goals': ['health', 'aesthetics'],
          'goal': 'sport',
        });
        expect(prefs.goals, [RoutineGoal.sport]);
      });

      test('goal null con goals viejo ⇒ la 1.0 limpió, queda vacío', () {
        final prefs = TemplatePreferences.fromJson(const {
          'goals': ['health'],
          'goal': null,
        });
        expect(prefs.goals, isEmpty);
      });

      test('goal desconocido con goals viejo ⇒ vacío, no resucita lo viejo',
          () {
        final prefs = TemplatePreferences.fromJson(const {
          'goals': ['health', 'aesthetics'],
          'goal': 'powerlifting_meet',
        });
        expect(prefs.goals, isEmpty);
      });

      test('sin clave goal, goals vale tal cual', () {
        final prefs = TemplatePreferences.fromJson(const {
          'goals': ['health', 'aesthetics'],
        });
        expect(prefs.goals, [RoutineGoal.health, RoutineGoal.aesthetics]);
      });
    });

    test('a malformed `goals` degrades to no preference, never a crash', () {
      final prefs = TemplatePreferences.fromJson(const {'goals': 'health'});
      expect(prefs.goals, isEmpty);
    });

    test('an unknown muscle group is dropped, not surfaced', () {
      final prefs = TemplatePreferences.fromJson(const {
        'priorityMuscleGroups': ['back', 'gills'],
      });

      expect(prefs.priorityGroups, [MuscleGroup.espalda]);
      expect(
        prefs.priorityMuscleGroups,
        ['back', 'gills'],
        reason: 'the raw list is preserved so a newer build still reads it',
      );
    });
  });

  group('TemplatePreferences — encoding (compat con la 1.0)', () {
    test('writes `goals` AND mirrors the first one into `goal`', () {
      final json = const TemplatePreferences(
        daysPerWeek: 4,
        goals: [RoutineGoal.aesthetics, RoutineGoal.health],
      ).toJson();

      expect(json['goals'], ['aesthetics', 'health']);
      expect(json['goal'], 'aesthetics',
          reason: 'la 1.0 sólo lee `goal`: tiene que seguir viendo algo');
      expect(json['daysPerWeek'], 4);
    });

    test('no goals ⇒ `goal` is null, not a stale value', () {
      final json = const TemplatePreferences(daysPerWeek: 3).toJson();
      expect(json['goals'], isEmpty);
      expect(json.containsKey('goal'), isTrue);
      expect(json['goal'], isNull);
    });

    test('round-trips through toJson / fromJson', () {
      const prefs = TemplatePreferences(
        minutesPerSession: 60,
        goals: [RoutineGoal.wellbeing, RoutineGoal.injuryPrevention],
        priorityMuscleGroups: ['glutes'],
      );
      expect(TemplatePreferences.fromJson(prefs.toJson()), prefs);
    });
  });
}
