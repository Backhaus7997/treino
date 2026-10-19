import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/availability_override.dart';
import 'package:treino/features/coach/domain/availability_rule.dart';
import 'package:treino/features/coach/domain/session_conflicts.dart';

// Jueves 15/10/2026 → lunes 19, martes 20, miércoles 21 (ISO weekday 1, 2, 3).
DateTime _at(int day, int hour, [int minute = 0]) =>
    DateTime.utc(2026, 10, day, hour, minute);

Appointment _appt(
  String id,
  DateTime startsAt, {
  int durationMin = 60,
  AppointmentStatus status = AppointmentStatus.confirmed,
  String name = 'Sofía Ramírez',
}) =>
    Appointment(
      id: id,
      trainerId: 't1',
      athleteId: 'a-$id',
      athleteDisplayName: name,
      startsAt: startsAt,
      durationMin: durationMin,
      status: status,
    );

AvailabilityRule _rule(int day, int startH, int endH) => AvailabilityRule(
      id: 'r-$day-$startH',
      trainerId: 't1',
      dayOfWeek: day,
      startHour: startH,
      startMinute: 0,
      endHour: endH,
      endMinute: 0,
      slotDurationMin: 60,
    );

SessionConflicts _detect(
  DateTime startsAt, {
  int durationMin = 60,
  List<Appointment> existing = const [],
  List<AvailabilityRule> rules = const [],
  List<AvailabilityOverride> overrides = const [],
}) =>
    detectSessionConflicts(
      startsAt: startsAt,
      durationMin: durationMin,
      existing: existing,
      rules: rules,
      overrides: overrides,
    );

void main() {
  group('superposición', () {
    test('el caso del QA: Martín 17–18 encima de Sofía 17–18', () {
      final sofia = _appt('sofia', _at(19, 17));
      final c = _detect(_at(19, 17), existing: [sofia]);
      expect(c.overlapping.map((a) => a.id), ['sofia']);
      expect(c.isEmpty, isFalse);
    });

    test('pisa por la mitad, por arriba y por abajo', () {
      final base = _appt('base', _at(19, 17));
      expect(
          _detect(_at(19, 17, 30), existing: [base]).overlapping, hasLength(1));
      expect(
          _detect(_at(19, 16, 30), existing: [base]).overlapping, hasLength(1));
    });

    test('una sesión larga que contiene a otra', () {
      final corta = _appt('corta', _at(19, 17, 30), durationMin: 30);
      final c = _detect(_at(19, 17), durationMin: 120, existing: [corta]);
      expect(c.overlapping, hasLength(1));
    });

    test('pegadas NO se superponen: 17–18 y 18–19', () {
      final base = _appt('base', _at(19, 17));
      expect(_detect(_at(19, 18), existing: [base]).overlapping, isEmpty);
      expect(_detect(_at(19, 16), existing: [base]).overlapping, isEmpty);
    });

    test('otra fecha no choca', () {
      final base = _appt('base', _at(19, 17));
      expect(_detect(_at(20, 17), existing: [base]).overlapping, isEmpty);
    });

    test('una sesión cancelada no ocupa el horario', () {
      final cancelada = _appt(
        'x',
        _at(19, 17),
        status: AppointmentStatus.cancelled,
      );
      expect(_detect(_at(19, 17), existing: [cancelada]).overlapping, isEmpty);
    });

    test(
        'cruce de medianoche: 23:30 + 60 min pisa a las 00:00 del día siguiente',
        () {
      final madrugada = _appt('m', _at(20, 0), durationMin: 30);
      final c = _detect(_at(19, 23, 30), existing: [madrugada]);
      expect(c.overlapping, hasLength(1));
    });

    test('devuelve todas las que pisa, ordenadas por hora', () {
      final tarde = _appt('tarde', _at(19, 18));
      final temprano = _appt('temprano', _at(19, 17));
      final c = _detect(
        _at(19, 17),
        durationMin: 120,
        existing: [tarde, temprano],
      );
      expect(c.overlapping.map((a) => a.id), ['temprano', 'tarde']);
    });
  });

  group('disponibilidad publicada', () {
    // Lautaro: Lun/Mié/Vie 9–13.
    final lautaro = [
      _rule(DateTime.monday, 9, 13),
      _rule(DateTime.wednesday, 9, 13),
      _rule(DateTime.friday, 9, 13),
    ];

    test('dentro de la ventana no avisa', () {
      final c = _detect(_at(19, 10), rules: lautaro);
      expect(c.outsideAvailability, isFalse);
    });

    test('el caso del QA: lunes 17:00 está fuera de Lun 9–13', () {
      final c = _detect(_at(19, 17), rules: lautaro);
      expect(c.outsideAvailability, isTrue);
    });

    test('un día sin reglas (martes) está fuera aunque haya otras cargadas',
        () {
      final c = _detect(_at(20, 10), rules: lautaro);
      expect(c.outsideAvailability, isTrue);
    });

    test('tiene que entrar ENTERA: 12:30 + 60 min se pasa del 13:00', () {
      final c = _detect(_at(19, 12, 30), rules: lautaro);
      expect(c.outsideAvailability, isTrue);
    });

    test('justo hasta el borde entra: 12:00 + 60 min termina a las 13:00', () {
      final c = _detect(_at(19, 12), rules: lautaro);
      expect(c.outsideAvailability, isFalse);
    });

    test('ventanas pegadas valen como una: 10–12 entra en 9–11 + 11–13', () {
      final c = _detect(
        _at(19, 10),
        durationMin: 120,
        rules: [_rule(DateTime.monday, 9, 11), _rule(DateTime.monday, 11, 13)],
      );
      expect(c.outsideAvailability, isFalse);
    });

    test('con un hueco entre ventanas, la sesión que lo cruza queda afuera',
        () {
      final c = _detect(
        _at(19, 10),
        durationMin: 120,
        rules: [_rule(DateTime.monday, 9, 11), _rule(DateTime.monday, 12, 14)],
      );
      expect(c.outsideAvailability, isTrue);
    });

    test('una ventana extra de esa fecha cuenta como disponibilidad', () {
      final extra = AvailabilityOverride.extra(
        id: 'e1',
        trainerId: 't1',
        date: DateTime.utc(2026, 10, 19),
        startHour: 17,
        startMinute: 0,
        endHour: 19,
        endMinute: 0,
        slotDurationMin: 60,
      );
      final c = _detect(_at(19, 17), rules: lautaro, overrides: [extra]);
      expect(c.outsideAvailability, isFalse);
    });

    test('una ventana extra de OTRA fecha no ayuda', () {
      final extra = AvailabilityOverride.extra(
        id: 'e1',
        trainerId: 't1',
        date: DateTime.utc(2026, 10, 26),
        startHour: 17,
        startMinute: 0,
        endHour: 19,
        endMinute: 0,
        slotDurationMin: 60,
      );
      final c = _detect(_at(19, 17), rules: lautaro, overrides: [extra]);
      expect(c.outsideAvailability, isTrue);
    });

    test('sin disponibilidad publicada NO avisa (nada contra qué medir)', () {
      final c = _detect(_at(19, 17));
      expect(c.outsideAvailability, isFalse);
    });

    test('sin reglas pero con una extra ese día, fuera de la extra avisa', () {
      final extra = AvailabilityOverride.extra(
        id: 'e1',
        trainerId: 't1',
        date: DateTime.utc(2026, 10, 19),
        startHour: 9,
        startMinute: 0,
        endHour: 11,
        endMinute: 0,
        slotDurationMin: 60,
      );
      final c = _detect(_at(19, 17), overrides: [extra]);
      expect(c.outsideAvailability, isTrue);
    });

    test('día bloqueado: no se duplica el aviso (lo cubre "Día bloqueado")',
        () {
      final block = AvailabilityOverride.block(
        id: 'b1',
        trainerId: 't1',
        date: DateTime.utc(2026, 10, 19),
      );
      final c = _detect(_at(19, 17), rules: lautaro, overrides: [block]);
      expect(c.outsideAvailability, isFalse);
    });

    test('una sesión que cruza la medianoche nunca entra', () {
      final c = _detect(
        _at(19, 23),
        durationMin: 120,
        rules: [_rule(DateTime.monday, 9, 24)],
      );
      expect(c.outsideAvailability, isTrue);
    });
  });

  test('sin nada que avisar, isEmpty', () {
    final c = _detect(
      _at(19, 10),
      rules: [_rule(DateTime.monday, 9, 13)],
      existing: [_appt('otra', _at(19, 15))],
    );
    expect(c.isEmpty, isTrue);
  });

  group('serie', () {
    test('cuenta en cuántas fechas hay cada tipo de conflicto', () {
      // 19/10 y 26/10 son lunes.
      final c = detectSeriesConflicts(
        startsAts: [
          _at(19, 17), // lunes: pisa a Sofía, fuera de 9–13
          _at(26, 11), // lunes: libre y dentro
        ],
        durationMin: 60,
        existing: [_appt('sofia', _at(19, 17))],
        rules: [_rule(DateTime.monday, 9, 13)],
        overrides: const [],
      );
      expect(c.overlapCount, 1);
      expect(c.outsideCount, 1);
      expect(c.isEmpty, isFalse);
    });

    test('una serie limpia está vacía', () {
      final c = detectSeriesConflicts(
        startsAts: [_at(19, 10), _at(26, 10)],
        durationMin: 60,
        existing: const [],
        rules: [_rule(DateTime.monday, 9, 13)],
        overrides: const [],
      );
      expect(c.isEmpty, isTrue);
    });
  });
}
