import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_goal.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/template_affinity.dart';
import 'package:treino/features/workout/domain/template_preferences.dart';

RoutineSlot _slot(String muscleGroup) => RoutineSlot(
      exerciseId: 'e',
      exerciseName: 'e',
      muscleGroup: muscleGroup,
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: 90,
    );

Routine _routine({
  int days = 3,
  int? minutes,
  List<RoutineGoal> goals = const [],
  List<String> zones = const ['chest'],
}) =>
    Routine(
      id: 'r',
      name: 'R',
      level: ExperienceLevel.beginner,
      estimatedMinutesPerDay: minutes,
      goals: goals,
      days: [
        for (var i = 0; i < days; i++)
          RoutineDay(
            dayNumber: i + 1,
            name: 'D${i + 1}',
            slots: [for (final z in zones) _slot(z)],
          ),
      ],
    );

void main() {
  group('nunca excluye: el puntaje siempre existe y está acotado', () {
    test('toda combinación cae en [0, 1]', () {
      const prefs = TemplatePreferences(
        daysPerWeek: 2,
        minutesPerSession: 30,
        goal: RoutineGoal.sport,
        priorityMuscleGroups: ['back'],
      );
      // La combinación que el issue cita como "cero matches" en un filtro duro.
      final score = TemplateAffinity.score(
        _routine(days: 3, minutes: 45, goals: const [RoutineGoal.health]),
        prefs,
      );
      expect(score, inInclusiveRange(0, 1));
      expect(score, greaterThan(0),
          reason: 'ni la peor plantilla puede quedar en cero absoluto: '
              'el ranking la baja, no la borra');
    });

    test('sin preferencias todas empatan y el orden queda intacto', () {
      const prefs = TemplatePreferences();
      expect(TemplateAffinity.score(_routine(), prefs),
          TemplateAffinity.neutral);
      expect(
        TemplateAffinity.score(_routine(days: 6, minutes: 120), prefs),
        TemplateAffinity.neutral,
      );
    });
  });

  group('sin dato es NEUTRO, entre el match y el desajuste', () {
    // El orden de estos tres es la decisión de diseño central del scoring.
    const wantsAesthetics = TemplatePreferences(goal: RoutineGoal.aesthetics);

    test('match > sin declarar > desajuste', () {
      final match = TemplateAffinity.score(
        _routine(goals: const [RoutineGoal.aesthetics]),
        wantsAesthetics,
      );
      final sinDeclarar = TemplateAffinity.score(_routine(), wantsAesthetics);
      final desajuste = TemplateAffinity.score(
        _routine(goals: const [RoutineGoal.sport]),
        wantsAesthetics,
      );

      expect(match, greaterThan(sinDeclarar));
      expect(sinDeclarar, greaterThan(desajuste),
          reason: 'una plantilla de la comunidad publicada antes de #635 no '
              'puede hundirse debajo de una que declara algo que al atleta '
              'no le sirve');
    });

    test('minutos ausentes no penalizan: el campo es nullable en el modelo',
        () {
      const prefs = TemplatePreferences(minutesPerSession: 45);
      final sinMinutos = TemplateAffinity.score(_routine(), prefs);
      final conflicto = TemplateAffinity.score(_routine(minutes: 120), prefs);
      expect(sinMinutos, greaterThan(conflicto));
    });
  });

  group('días por semana', () {
    const prefs = TemplatePreferences(daysPerWeek: 3);

    test('exacto gana, y decae con la distancia en vez de ser binario', () {
      final exacto = TemplateAffinity.score(_routine(days: 3), prefs);
      final unoMas = TemplateAffinity.score(_routine(days: 4), prefs);
      final tresMas = TemplateAffinity.score(_routine(days: 6), prefs);

      expect(exacto, greaterThan(unoMas));
      expect(unoMas, greaterThan(tresMas),
          reason: 'para quien pide 3 días, una de 4 es mejor candidata que '
              'una de 6 — un booleano las empataría');
    });
  });

  group('minutos por sesión: pasarse penaliza más que sobrar', () {
    const prefs = TemplatePreferences(minutesPerSession: 45);

    test('15 minutos de más pesan más que 15 de menos', () {
      final corta = TemplateAffinity.score(_routine(minutes: 30), prefs);
      final larga = TemplateAffinity.score(_routine(minutes: 60), prefs);

      expect(corta, greaterThan(larga),
          reason: 'quien dice tener 45 minutos TIENE 45: una sesión de 60 no '
              'le entra, mientras que una de 30 simplemente termina antes');
    });
  });

  group('zonas priorizadas', () {
    const prefs = TemplatePreferences(priorityMuscleGroups: ['glutes']);

    test('cubrir la zona pedida vale, aunque la plantilla toque otras seis',
        () {
      final amplia = TemplateAffinity.score(
        _routine(zones: const [
          'glutes',
          'chest',
          'back',
          'quads',
          'core',
          'biceps',
        ]),
        prefs,
      );
      final exacta = TemplateAffinity.score(
        _routine(zones: const ['glutes']),
        prefs,
      );
      expect(amplia, exacta,
          reason: 'castigar la amplitud hundiría a las Full Body, que son '
              'justo las que más gente necesita');
    });

    test('cuerpo completo cubre cualquier zona pedida', () {
      expect(
        TemplateAffinity.score(_routine(zones: const ['fullbody']), prefs),
        TemplateAffinity.score(_routine(zones: const ['glutes']), prefs),
      );
    });

    test('no cubrirla puntúa peor que no tener zonas derivables', () {
      final noCubre =
          TemplateAffinity.score(_routine(zones: const ['chest']), prefs);
      final sinSlots = TemplateAffinity.score(
        const Routine(
          id: 'r',
          name: 'R',
          level: ExperienceLevel.beginner,
          days: [],
        ),
        prefs,
      );
      expect(sinSlots, greaterThan(noCubre));
    });
  });
}
