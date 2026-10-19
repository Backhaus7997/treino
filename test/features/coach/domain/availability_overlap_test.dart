import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/availability_overlap.dart';
import 'package:treino/features/coach/domain/availability_rule.dart';

AvailabilityRule _rule(
  String id,
  int day,
  int startH,
  int endH, {
  int startM = 0,
  int endM = 0,
  int slot = 60,
}) =>
    AvailabilityRule(
      id: id,
      trainerId: 't1',
      dayOfWeek: day,
      startHour: startH,
      startMinute: startM,
      endHour: endH,
      endMinute: endM,
      slotDurationMin: slot,
    );

void main() {
  group('minuteRangesOverlap', () {
    test('rangos semiabiertos: pegados NO se superponen', () {
      expect(minuteRangesOverlap(540, 660, 660, 780), isFalse);
      expect(minuteRangesOverlap(660, 780, 540, 660), isFalse);
    });

    test('un minuto en común sí', () {
      expect(minuteRangesOverlap(540, 661, 660, 780), isTrue);
    });

    test('uno adentro del otro, en cualquier orden', () {
      expect(minuteRangesOverlap(540, 780, 600, 660), isTrue);
      expect(minuteRangesOverlap(600, 660, 540, 780), isTrue);
    });

    test('disjuntos', () {
      expect(minuteRangesOverlap(540, 600, 720, 780), isFalse);
    });
  });

  group('findOverlappingRule', () {
    final lunes9a13 = _rule('lun', DateTime.monday, 9, 13);

    test('el caso del QA: lunes 09–11 adentro de lunes 09–13', () {
      final hit = findOverlappingRule(
        rules: [lunes9a13],
        dayOfWeek: DateTime.monday,
        startMinutes: 9 * 60,
        endMinutes: 11 * 60,
      );
      expect(hit?.id, 'lun');
    });

    test('otro día de la semana no choca', () {
      expect(
        findOverlappingRule(
          rules: [lunes9a13],
          dayOfWeek: DateTime.tuesday,
          startMinutes: 9 * 60,
          endMinutes: 11 * 60,
        ),
        isNull,
      );
    });

    test('lunes 13–15 pegado a lunes 09–13 no choca', () {
      expect(
        findOverlappingRule(
          rules: [lunes9a13],
          dayOfWeek: DateTime.monday,
          startMinutes: 13 * 60,
          endMinutes: 15 * 60,
        ),
        isNull,
      );
    });

    test('contempla los minutos: 12:30–14:00 pisa a 09–13', () {
      expect(
        findOverlappingRule(
          rules: [lunes9a13],
          dayOfWeek: DateTime.monday,
          startMinutes: 12 * 60 + 30,
          endMinutes: 14 * 60,
        )?.id,
        'lun',
      );
    });

    test('al editar, la regla no choca consigo misma', () {
      expect(
        findOverlappingRule(
          rules: [lunes9a13],
          dayOfWeek: DateTime.monday,
          startMinutes: 9 * 60,
          endMinutes: 12 * 60,
          ignoreRuleId: 'lun',
        ),
        isNull,
      );
    });

    test('al editar sigue chocando con las OTRAS reglas', () {
      final otra = _rule('otra', DateTime.monday, 15, 18);
      expect(
        findOverlappingRule(
          rules: [lunes9a13, otra],
          dayOfWeek: DateTime.monday,
          startMinutes: 16 * 60,
          endMinutes: 19 * 60,
          ignoreRuleId: 'lun',
        )?.id,
        'otra',
      );
    });

    test('sin reglas no hay choque', () {
      expect(
        findOverlappingRule(
          rules: const [],
          dayOfWeek: DateTime.monday,
          startMinutes: 540,
          endMinutes: 660,
        ),
        isNull,
      );
    });
  });

  group('suggestFreeRuleWindow', () {
    test('sin reglas: el default de siempre, lunes 09–11', () {
      final w = suggestFreeRuleWindow(const []);
      expect(
        w,
        (dayOfWeek: DateTime.monday, startMinutes: 540, endMinutes: 660),
      );
    });

    test('el caso del QA: con lunes 09–13 cargado NO propone lunes 09–11', () {
      final w = suggestFreeRuleWindow([_rule('lun', DateTime.monday, 9, 13)]);
      expect(w.dayOfWeek, DateTime.monday);
      expect(w.startMinutes, 13 * 60);
      expect(w.endMinutes, 15 * 60);
    });

    test('salta al día siguiente cuando el día está lleno', () {
      final w = suggestFreeRuleWindow([_rule('lun', DateTime.monday, 9, 22)]);
      expect(w.dayOfWeek, DateTime.tuesday);
      expect(w.startMinutes, 9 * 60);
    });

    test('lo que propone nunca pisa una regla existente', () {
      final rules = [
        _rule('a', DateTime.monday, 9, 13),
        _rule('b', DateTime.monday, 14, 16, startM: 30),
        _rule('c', DateTime.tuesday, 8, 12),
      ];
      final w = suggestFreeRuleWindow(rules);
      expect(
        findOverlappingRule(
          rules: rules,
          dayOfWeek: w.dayOfWeek,
          startMinutes: w.startMinutes,
          endMinutes: w.endMinutes,
        ),
        isNull,
      );
    });

    test('semana completa: vuelve al viejo default (el guardado avisa)', () {
      final rules = [
        for (var d = DateTime.monday; d <= DateTime.sunday; d++)
          _rule('d$d', d, 0, 23, endM: 59),
      ];
      final w = suggestFreeRuleWindow(rules);
      expect(
        w,
        (dayOfWeek: DateTime.monday, startMinutes: 540, endMinutes: 660),
      );
    });
  });
}
