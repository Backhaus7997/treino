// Contrato de `routineMetaSegments` — la línea de metadata que comparten las
// DOS tarjetas de rutina (#648).
//
// Existe como test propio, y no adentro del de una tarjeta, por el mismo motivo
// por el que el helper existe: cuando la lógica estaba duplicada las dos
// tarjetas divergieron y nadie se enteró, porque ningún test cubría la línea
// vieja. El contrato se fija una vez, acá.
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/presentation/widgets/routine_meta.dart';
import 'package:treino/l10n/app_l10n_es.dart';

final _l10n = AppL10nEsAr();

RoutineSlot _slot(int i) => RoutineSlot(
      exerciseId: 'ex-$i',
      exerciseName: 'Exercise $i',
      muscleGroup: 'Chest',
      targetSets: 3,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: 60,
    );

RoutineDay _day(int n, {int slots = 4, int? estimatedMinutes}) => RoutineDay(
      dayNumber: n,
      name: 'Day $n',
      slots: List.generate(slots, _slot),
      estimatedMinutes: estimatedMinutes,
    );

Routine _routine({
  String? split = 'Bro Split',
  ExperienceLevel level = ExperienceLevel.beginner,
  List<RoutineDay> days = const [],
}) =>
    Routine(
      id: 'r1',
      name: 'Rutina',
      split: split,
      level: level,
      days: days,
    );

void main() {
  group('routineMetaSegments', () {
    test('NUNCA incluye el split, ni siquiera cuando la rutina lo tiene', () {
      // El corazón de #648: una persona que nunca pisó un gimnasio no sabe qué
      // es un "Bro Split" — no le cuesta, no le significa nada — y era la
      // etiqueta más prominente de la pantalla que usa para elegir.
      final segments = routineMetaSegments(
        _routine(split: 'Bro Split', days: [_day(1), _day(2), _day(3)]),
        _l10n,
      );

      expect(segments.join(' · '), isNot(contains('Bro Split')));
      expect(segments.join(' · ').toUpperCase(), isNot(contains('BRO SPLIT')));
    });

    test('el nivel va PRIMERO — es el "¿es para mí?"', () {
      final segments = routineMetaSegments(_routine(), _l10n);
      expect(segments.first, ExperienceLevel.beginner.displayNameEs);
    });

    test('con días, el orden es nivel → días/semana → minutos', () {
      final segments = routineMetaSegments(
        _routine(days: [
          _day(1, estimatedMinutes: 60),
          _day(2, estimatedMinutes: 60),
          _day(3, estimatedMinutes: 60),
        ]),
        _l10n,
      );

      expect(segments.length, 3);
      expect(segments[0], ExperienceLevel.beginner.displayNameEs);
      expect(segments[1], contains('3'));
      expect(segments[2], contains('60'));
    });

    test('una rutina sin días no dice "0 días/sem" — el segmento se cae', () {
      // Documento válido pero degenerado (spec SCENARIO-052). Un "0" ahí es
      // ruido, no información.
      final segments = routineMetaSegments(_routine(days: const []), _l10n);
      expect(segments, [ExperienceLevel.beginner.displayNameEs]);
    });

    test('sin duración medible se omite el segmento entero, no un guion', () {
      // Las rutinas publicadas por PFs y por la comunidad no traen duración
      // garantizada: un placeholder sería ruido en la parte del catálogo que
      // más crece.
      final segments = routineMetaSegments(
        _routine(days: [_day(1, slots: 0)]),
        _l10n,
      );
      expect(segments.any((s) => s.contains('-')), isFalse);
    });
  });
}
