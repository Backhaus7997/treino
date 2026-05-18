// Tests para SessionInit — igualdad, hashCode, pattern matching exhaustivo.
// RED: el archivo de producción no existe todavía.

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/application/session_init.dart';

void main() {
  group('SessionInit', () {
    // ── Igualdad FreshSession ─────────────────────────────────────────────────
    test('dos FreshSession con mismos valores son ==', () {
      const a = FreshSession(routineId: 'r1', dayNumber: 1);
      const b = FreshSession(routineId: 'r1', dayNumber: 1);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('FreshSession con distinto routineId no son ==', () {
      const a = FreshSession(routineId: 'r1', dayNumber: 1);
      const b = FreshSession(routineId: 'r2', dayNumber: 1);
      expect(a, isNot(equals(b)));
    });

    // ── Igualdad ResumeSession ────────────────────────────────────────────────
    test('dos ResumeSession con el mismo sessionId son ==', () {
      const a = ResumeSession(sessionId: 's1');
      const b = ResumeSession(sessionId: 's1');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    // ── Distintos subtipos no son == ─────────────────────────────────────────
    test('FreshSession y ResumeSession no son == aunque tengan ids similares', () {
      const fresh = FreshSession(routineId: 's1', dayNumber: 1);
      const resume = ResumeSession(sessionId: 's1');
      expect(fresh, isNot(equals(resume)));
    });

    // ── Pattern matching exhaustivo (compile-time check) ─────────────────────
    test('switch sobre SessionInit cubre todos los casos sin default', () {
      // Si se agrega una subclase sin actualizar este switch, falla la compilación.
      SessionInit init = const FreshSession(routineId: 'r1', dayNumber: 1);
      final result = switch (init) {
        FreshSession(routineId: final rid) => 'fresh:$rid',
        ResumeSession(sessionId: final sid) => 'resume:$sid',
      };
      expect(result, equals('fresh:r1'));

      init = const ResumeSession(sessionId: 's42');
      final result2 = switch (init) {
        FreshSession() => 'fresh',
        ResumeSession(sessionId: final sid) => 'resume:$sid',
      };
      expect(result2, equals('resume:s42'));
    });
  });
}
