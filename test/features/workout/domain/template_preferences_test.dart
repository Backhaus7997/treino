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
        'goal': 'health',
        'priorityMuscleGroups': ['back', 'core'],
      });

      expect(prefs.daysPerWeek, 3);
      expect(prefs.minutesPerSession, 45);
      expect(prefs.goal, RoutineGoal.health);
      expect(
        prefs.priorityGroups,
        [MuscleGroup.espalda, MuscleGroup.abdominales],
      );
    });

    test('an absent field stays null rather than defaulted', () {
      final prefs = TemplatePreferences.fromJson(const {});

      expect(prefs.daysPerWeek, isNull);
      expect(prefs.minutesPerSession, isNull);
      expect(prefs.goal, isNull);
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

      expect(prefs.goal, isNull, reason: 'unknown ⇒ neutral, never a crash');
      expect(prefs.daysPerWeek, 4, reason: 'the rest of the answers survive');
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
}
