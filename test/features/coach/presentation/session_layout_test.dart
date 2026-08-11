// PR-A — `computeSessionLayout` se extrajo verbatim de day_timeline.dart para
// poder testear el packing de superposiciones con `test()` plano, sin
// WidgetTester ni viewport forzado. Ahí es donde viven los bugs reales:
// off-by-one en el conteo de carriles, cadenas transitivas y cruzadores de
// medianoche.
//
// ADR-7: `startsAt` es wall-clock UTC. El algoritmo lee `hour * 60 + minute`
// en crudo y es day-blind: el llamador particiona por día ANTES de llamar.

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/presentation/session_layout.dart';

// Lunes 2026-06-01.
Appointment _appt(
  String id, {
  required int hour,
  required int minute,
  required int durationMin,
}) =>
    Appointment(
      id: id,
      trainerId: 'tA',
      athleteId: 'a-$id',
      athleteDisplayName: 'Alumno $id',
      startsAt: DateTime.utc(2026, 6, 1, hour, minute),
      durationMin: durationMin,
      status: AppointmentStatus.confirmed,
    );

/// Busca el layout de un appointment por id (el resultado viene ORDENADO,
/// no en el orden de entrada).
SessionLayout _byId(List<SessionLayout> layouts, String id) =>
    layouts.firstWhere((l) => l.appointment.id == id);

void main() {
  group('computeSessionLayout', () {
    test('empty input returns an empty list', () {
      expect(computeSessionLayout(const []), isEmpty);
    });

    test('three non-overlapping sessions all get columnCount 1', () {
      final layouts = computeSessionLayout([
        _appt('a', hour: 9, minute: 0, durationMin: 60),
        _appt('b', hour: 10, minute: 0, durationMin: 60),
        _appt('c', hour: 11, minute: 0, durationMin: 60),
      ]);

      expect(layouts, hasLength(3));
      for (final l in layouts) {
        expect(l.columnCount, 1, reason: '${l.appointment.id} should be alone');
        expect(l.columnIndex, 0);
      }
    });

    test('back-to-back sessions do NOT overlap (end == start is exclusive)',
        () {
      // 09:00+60 ends exactly when 10:00 starts — must stay in separate
      // clusters, otherwise every full agenda collapses into one wide cluster.
      final layouts = computeSessionLayout([
        _appt('a', hour: 9, minute: 0, durationMin: 60),
        _appt('b', hour: 10, minute: 0, durationMin: 60),
      ]);

      expect(_byId(layouts, 'a').columnCount, 1);
      expect(_byId(layouts, 'b').columnCount, 1);
    });

    test('two sessions at the same start get indices 0 and 1, BOTH count 2',
        () {
      // Cluster-wide uniform width (day_timeline.dart:558-562): every session
      // of the cluster shares the SAME columnCount, so blocks line up.
      final layouts = computeSessionLayout([
        _appt('a', hour: 9, minute: 0, durationMin: 60),
        _appt('b', hour: 9, minute: 0, durationMin: 60),
      ]);

      expect(layouts, hasLength(2));
      expect(layouts.map((l) => l.columnIndex).toList(), [0, 1]);
      expect(layouts.map((l) => l.columnCount).toList(), [2, 2]);
    });

    test('transitive chain forms ONE cluster and reuses a freed column', () {
      // A 09:00+60 (→10:00), B 09:30+60 (→10:30), C 10:15+45 (→11:00).
      // A∩B and B∩C overlap, A∩C do NOT — transitivity keeps them together.
      // C starts after A ends, so it reuses column 0.
      final layouts = computeSessionLayout([
        _appt('a', hour: 9, minute: 0, durationMin: 60),
        _appt('b', hour: 9, minute: 30, durationMin: 60),
        _appt('c', hour: 10, minute: 15, durationMin: 45),
      ]);

      expect(layouts, hasLength(3));
      // One cluster ⇒ one shared columnCount for all three.
      expect(layouts.map((l) => l.columnCount).toSet(), {2});
      expect(_byId(layouts, 'a').columnIndex, 0);
      expect(_byId(layouts, 'b').columnIndex, 1);
      expect(_byId(layouts, 'c').columnIndex, 0);
    });

    test('tie-break at the same start puts the longer session first', () {
      // day_timeline.dart:510 — ties broken by longer duration first, so the
      // 90-min block takes the leftmost lane.
      final layouts = computeSessionLayout([
        _appt('short', hour: 9, minute: 0, durationMin: 30),
        _appt('long', hour: 9, minute: 0, durationMin: 90),
      ]);

      expect(layouts.first.appointment.id, 'long');
      expect(_byId(layouts, 'long').columnIndex, 0);
      expect(_byId(layouts, 'short').columnIndex, 1);
    });

    test('a 23:30+60 midnight crosser does not throw', () {
      // endMin = 1470 > 1440. The algorithm works in minutes-of-day and never
      // wraps, so this must simply lay out as a normal single-lane session.
      late List<SessionLayout> layouts;
      expect(
        () => layouts = computeSessionLayout([
          _appt('crosser', hour: 23, minute: 30, durationMin: 60),
        ]),
        returnsNormally,
      );
      expect(layouts, hasLength(1));
      expect(layouts.single.columnIndex, 0);
      expect(layouts.single.columnCount, 1);
    });

    test('a midnight crosser still clusters with a later same-day session', () {
      final layouts = computeSessionLayout([
        _appt('crosser', hour: 23, minute: 30, durationMin: 60),
        _appt('late', hour: 23, minute: 45, durationMin: 30),
      ]);

      expect(layouts.map((l) => l.columnCount).toSet(), {2});
      expect(_byId(layouts, 'crosser').columnIndex, 0);
      expect(_byId(layouts, 'late').columnIndex, 1);
    });

    test('three mutually overlapping sessions produce columnCount 3', () {
      // This is the narrow-lane worst case the week grid has to survive.
      final layouts = computeSessionLayout([
        _appt('a', hour: 9, minute: 0, durationMin: 30),
        _appt('b', hour: 9, minute: 0, durationMin: 30),
        _appt('c', hour: 9, minute: 0, durationMin: 30),
      ]);

      expect(layouts.map((l) => l.columnCount).toSet(), {3});
      expect(layouts.map((l) => l.columnIndex).toList(), [0, 1, 2]);
    });
  });
}
