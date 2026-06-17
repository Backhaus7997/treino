// Tests puros de ResumenMetrics (W2 PR4) — sin Flutter ni providers.
// `now` se inyecta para que adherencia/volumen/peso/heatmap sean deterministas.

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/sections/alumnos/resumen_metrics.dart';
import 'package:treino/features/measurements/domain/measurement.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';

final _now = DateTime.utc(2026, 6, 17); // miércoles

Session _sess({
  required DateTime finishedAt,
  double volume = 1000,
  bool completed = true,
  SessionStatus status = SessionStatus.finished,
}) =>
    Session(
      id: 's${finishedAt.microsecondsSinceEpoch}',
      uid: 'a1',
      routineId: 'r1',
      routineName: 'X',
      startedAt: finishedAt,
      finishedAt: finishedAt,
      status: status,
      wasFullyCompleted: completed,
      durationMin: 60,
      totalVolumeKg: volume,
    );

Measurement _meas({required DateTime at, double? weight}) => Measurement(
      id: 'm${at.microsecondsSinceEpoch}',
      athleteId: 'a1',
      recordedBy: 't1',
      recordedAt: at,
      weightKg: weight,
    );

ResumenMetrics _compute({
  List<Session> sessions = const [],
  List<Measurement> measurements = const [],
  int weeklyTarget = 0,
}) =>
    ResumenMetrics.compute(
      sessions: sessions,
      measurements: measurements,
      weeklyTarget: weeklyTarget,
      now: _now,
    );

void main() {
  group('isCompletedSession', () {
    test('finished + wasFullyCompleted → true', () {
      expect(
          isCompletedSession(_sess(finishedAt: _now, completed: true)), isTrue);
    });

    test('finished pero abandonada (wasFullyCompleted=false) → false', () {
      expect(isCompletedSession(_sess(finishedAt: _now, completed: false)),
          isFalse);
    });

    test('en curso (status=active) → false', () {
      expect(
          isCompletedSession(
              _sess(finishedAt: _now, status: SessionStatus.active)),
          isFalse);
    });
  });

  group('adherencia 30d', () {
    test('weeklyTarget=7 con 15 sesiones en 30d → 50% (delta +50 vs previos)',
        () {
      final sessions = [
        for (var i = 1; i <= 15; i++)
          _sess(finishedAt: _now.subtract(Duration(days: i))),
      ];
      final m = _compute(sessions: sessions, weeklyTarget: 7);
      expect(m.adherencia30dPct, closeTo(50, 0.001));
      expect(m.adherenciaDeltaPts, closeTo(50, 0.001));
    });

    test('sin plan (weeklyTarget=0) → adherencia y delta null', () {
      final m = _compute(
        sessions: [_sess(finishedAt: _now.subtract(const Duration(days: 1)))],
        weeklyTarget: 0,
      );
      expect(m.adherencia30dPct, isNull);
      expect(m.adherenciaDeltaPts, isNull);
    });

    test('sesiones abandonadas no cuentan para adherencia', () {
      final m = _compute(
        sessions: [
          for (var i = 1; i <= 15; i++)
            _sess(
                finishedAt: _now.subtract(Duration(days: i)), completed: false),
        ],
        weeklyTarget: 7,
      );
      expect(m.adherencia30dPct, closeTo(0, 0.001));
    });

    test('uncapped: puede superar 100% si sobre-entrena', () {
      // weeklyTarget=2 → planned≈8.57 en 30d; 15 sesiones → ≈175%.
      final m = _compute(
        sessions: [
          for (var i = 1; i <= 15; i++)
            _sess(finishedAt: _now.subtract(Duration(days: i))),
        ],
        weeklyTarget: 2,
      );
      expect(m.adherencia30dPct, closeTo(175, 1));
      expect(m.adherencia30dPct, greaterThan(100));
    });

    test('delta negativo cuando el período actual es peor que el previo', () {
      final m = _compute(
        sessions: [
          for (var i = 1; i <= 3; i++)
            _sess(finishedAt: _now.subtract(Duration(days: i))), // 3 actuales
          for (var i = 31; i <= 40; i++)
            _sess(finishedAt: _now.subtract(Duration(days: i))), // 10 previas
        ],
        weeklyTarget: 7,
      );
      expect(m.adherenciaDeltaPts, closeTo(-23.333, 0.01)); // 10% - 33.33%
      expect(m.adherenciaDeltaPts, lessThan(0));
    });
  });

  group('sesiones por semana', () {
    test('8 sesiones en las últimas 4 semanas → 2.0', () {
      final sessions = [
        for (var i = 1; i <= 8; i++)
          _sess(finishedAt: _now.subtract(Duration(days: i))),
      ];
      final m = _compute(sessions: sessions);
      expect(m.sesionesPorSemana, closeTo(2.0, 0.001));
    });

    test('sin sesiones → 0', () {
      expect(_compute().sesionesPorSemana, closeTo(0, 0.001));
    });

    test('sesiones fuera de la ventana de 4 semanas no cuentan', () {
      final m = _compute(sessions: [
        for (var i = 1; i <= 8; i++)
          _sess(finishedAt: _now.subtract(Duration(days: i))), // en ventana
        _sess(finishedAt: _now.subtract(const Duration(days: 40))), // fuera
      ]);
      expect(
          m.sesionesPorSemana, closeTo(2.0, 0.001)); // 8/4, la de 40d excluida
    });
  });

  group('volumen semana actual vs previa', () {
    test('800 esta semana vs 1000 la previa → -20%', () {
      final m = _compute(sessions: [
        _sess(finishedAt: _now.subtract(const Duration(days: 1)), volume: 800),
        _sess(
            finishedAt: _now.subtract(const Duration(days: 10)), volume: 1000),
      ]);
      expect(m.volumenSemanaActualKg, closeTo(800, 0.001));
      expect(m.volumenDeltaPct, closeTo(-20, 0.001));
    });

    test('semana previa en 0 → delta null', () {
      final m = _compute(sessions: [
        _sess(finishedAt: _now.subtract(const Duration(days: 1)), volume: 500),
      ]);
      expect(m.volumenSemanaActualKg, closeTo(500, 0.001));
      expect(m.volumenDeltaPct, isNull);
    });

    test('1200 esta semana vs 1000 la previa → +20%', () {
      final m = _compute(sessions: [
        _sess(finishedAt: _now.subtract(const Duration(days: 1)), volume: 1200),
        _sess(
            finishedAt: _now.subtract(const Duration(days: 10)), volume: 1000),
      ]);
      expect(m.volumenSemanaActualKg, closeTo(1200, 0.001));
      expect(m.volumenDeltaPct, closeTo(20, 0.001));
    });
  });

  group('peso corporal', () {
    test('toma el peso más reciente y el delta ~30d', () {
      final m = _compute(measurements: [
        _meas(at: _now.subtract(const Duration(days: 60)), weight: 65),
        _meas(at: _now.subtract(const Duration(days: 15)), weight: 62),
        _meas(at: _now.subtract(const Duration(days: 2)), weight: 60),
      ]);
      expect(m.pesoActualKg, closeTo(60, 0.001));
      expect(m.pesoDelta30dKg, closeTo(-5, 0.001)); // 60 - 65 (ref ≤ 30d atrás)
    });

    test('una sola medición → sin delta', () {
      final m = _compute(measurements: [_meas(at: _now, weight: 70)]);
      expect(m.pesoActualKg, closeTo(70, 0.001));
      expect(m.pesoDelta30dKg, isNull);
    });

    test('sin mediciones → peso null', () {
      expect(_compute().pesoActualKg, isNull);
    });

    test('todas las mediciones dentro de 30d → compara contra la más vieja',
        () {
      final m = _compute(measurements: [
        _meas(at: _now.subtract(const Duration(days: 10)), weight: 70),
        _meas(at: _now.subtract(const Duration(days: 2)), weight: 68),
      ]);
      expect(m.pesoActualKg, closeTo(68, 0.001));
      expect(
          m.pesoDelta30dKg, closeTo(-2, 0.001)); // 68 - 70 (fallback a la 1ª)
    });

    test('todas las mediciones > 30d (la última es la referencia) → delta null',
        () {
      final m = _compute(measurements: [
        _meas(at: _now.subtract(const Duration(days: 40)), weight: 72),
        _meas(at: _now.subtract(const Duration(days: 35)), weight: 70),
      ]);
      expect(m.pesoActualKg, closeTo(70, 0.001));
      expect(m.pesoDelta30dKg, isNull); // ref == latest → sin delta
    });
  });

  group('heatmap 12×7', () {
    test('dimensiones siempre 12 semanas × 7 días', () {
      final h = _compute().heatmap;
      expect(h.length, 12);
      expect(h.every((w) => w.length == 7), isTrue);
    });

    test('una sesión hoy → celda de la semana actual en nivel máximo (4)', () {
      final m = _compute(sessions: [_sess(finishedAt: _now, volume: 1000)]);
      final dow = _now.weekday - 1; // 0 = lunes
      expect(m.heatmap[11][dow], 4);
      // El resto queda en 0.
      var nonZero = 0;
      for (final week in m.heatmap) {
        for (final v in week) {
          if (v > 0) nonZero++;
        }
      }
      expect(nonZero, 1);
    });

    test('sesión más vieja que 12 semanas queda fuera de la grilla', () {
      final m = _compute(sessions: [
        _sess(finishedAt: _now.subtract(const Duration(days: 100))),
      ]);
      final allZero = m.heatmap.every((w) => w.every((v) => v == 0));
      expect(allZero, isTrue);
    });

    test('sesiones abandonadas no pintan el heatmap', () {
      final m = _compute(sessions: [_sess(finishedAt: _now, completed: false)]);
      final allZero = m.heatmap.every((w) => w.every((v) => v == 0));
      expect(allZero, isTrue);
    });

    test('niveles intermedios según la cantidad de sesiones del día', () {
      // Conteos por día: 4, 2, 1 → max 4 → ceil(4/4*4)=4, ceil(2/4*4)=2,
      // ceil(1/4*4)=1. El volumen es irrelevante para la adherencia.
      final m = _compute(sessions: [
        for (var i = 0; i < 4; i++)
          _sess(finishedAt: _now.subtract(const Duration(days: 1)), volume: 0),
        for (var i = 0; i < 2; i++)
          _sess(finishedAt: _now.subtract(const Duration(days: 2)), volume: 0),
        _sess(finishedAt: _now.subtract(const Duration(days: 3)), volume: 0),
      ]);
      final nonZero = [
        for (final w in m.heatmap)
          for (final v in w)
            if (v > 0) v
      ]..sort();
      expect(nonZero, [1, 2, 4]);
    });

    test('una sesión sin carga (0 kg) igual pinta el día (presencia)', () {
      // Regresión: el heatmap es adherencia, no volumen — 0 kg debe contar.
      final m = _compute(sessions: [_sess(finishedAt: _now, volume: 0)]);
      final dow = _now.weekday - 1;
      expect(m.heatmap[11][dow], 4);
    });

    test('cuenta varias sesiones del mismo día (+=, no =)', () {
      // Día con 2 sesiones vs día con 1 → conteos 2 y 1 → max 2 →
      // ceil(2/2*4)=4 y ceil(1/2*4)=2. Si fuera `=` ambos contarían 1 → [4,4].
      final m = _compute(sessions: [
        _sess(finishedAt: _now.subtract(const Duration(days: 1))),
        _sess(finishedAt: _now.subtract(const Duration(days: 1))),
        _sess(finishedAt: _now.subtract(const Duration(days: 2))),
      ]);
      final nonZero = [
        for (final w in m.heatmap)
          for (final v in w)
            if (v > 0) v
      ]..sort();
      expect(nonZero, [2, 4]);
    });

    test('heatmap invariante al huso de `now` (local vs UTC, mismo instante)',
        () {
      final nowUtc = DateTime.utc(2026, 6, 17, 12);
      final s = _sess(finishedAt: nowUtc);
      final hUtc = ResumenMetrics.compute(
        sessions: [s],
        measurements: const [],
        weeklyTarget: 0,
        now: nowUtc,
      ).heatmap;
      final hLocal = ResumenMetrics.compute(
        sessions: [s],
        measurements: const [],
        weeklyTarget: 0,
        now: nowUtc.toLocal(),
      ).heatmap;
      expect(hLocal, hUtc);
    });
  });
}
