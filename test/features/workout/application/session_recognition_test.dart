// Tests de deriveSessionRecognition — reglas de celebración del resumen
// post-entreno. Cada regla con su caso, prioridades y bordes ART.

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/application/session_recognition.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';

Session _session({
  String id = 's-hoy',
  DateTime? startedAt,
  double totalVolumeKg = 1000,
  bool wasFullyCompleted = true,
  SessionStatus status = SessionStatus.finished,
}) =>
    Session(
      id: id,
      uid: 'u1',
      routineId: 'r1',
      routineName: 'Push',
      // Lunes 2026-05-18 07:00 ART (10:00 UTC) por default.
      startedAt: startedAt ?? DateTime.utc(2026, 5, 18, 10),
      status: status,
      wasFullyCompleted: wasFullyCompleted,
      totalVolumeKg: totalVolumeKg,
    );

void main() {
  group('deriveSessionRecognition', () {
    test('sesión que no cuenta (#372) → none, aunque haya récords', () {
      final result = deriveSessionRecognition(
        session: _session(wasFullyCompleted: false),
        sessionsDesc: const [],
        recordCount: 3,
      );

      expect(result.kind, SessionRecognitionKind.none);
    });

    test('récords ganan a todo: recordCount > 0 → records con el count', () {
      final session = _session();
      final result = deriveSessionRecognition(
        session: session,
        // Prior de menor volumen el mismo mes: sin récords hubiera sido
        // bestMonthVolume — los récords tienen prioridad.
        sessionsDesc: [
          session,
          _session(id: 'p1', startedAt: DateTime.utc(2026, 5, 11, 10)),
        ],
        recordCount: 2,
      );

      expect(result.kind, SessionRecognitionKind.records);
      expect(result.count, 2);
    });

    test('sin ninguna sesión previa que cuente → firstWorkout', () {
      final session = _session();
      final result = deriveSessionRecognition(
        session: session,
        sessionsDesc: [
          session,
          // Abandonada previa: NO cuenta como historia.
          _session(
            id: 'p1',
            startedAt: DateTime.utc(2026, 5, 11, 10),
            wasFullyCompleted: false,
          ),
        ],
        recordCount: 0,
      );

      expect(result.kind, SessionRecognitionKind.firstWorkout);
    });

    test('sesiones POSTERIORES no cuentan como historia (resumen viejo)', () {
      final session = _session();
      final result = deriveSessionRecognition(
        session: session,
        sessionsDesc: [
          _session(id: 'futura', startedAt: DateTime.utc(2026, 5, 25, 10)),
          session,
        ],
        recordCount: 0,
      );

      expect(result.kind, SessionRecognitionKind.firstWorkout);
    });

    test('mayor volumen que toda sesión previa del mes ART → bestMonthVolume',
        () {
      final session = _session(totalVolumeKg: 2000);
      final result = deriveSessionRecognition(
        session: session,
        sessionsDesc: [
          session,
          _session(
            id: 'p1',
            startedAt: DateTime.utc(2026, 5, 4, 10),
            totalVolumeKg: 1500,
          ),
          _session(
            id: 'p2',
            startedAt: DateTime.utc(2026, 5, 11, 10),
            totalVolumeKg: 1900,
          ),
        ],
        recordCount: 0,
      );

      expect(result.kind, SessionRecognitionKind.bestMonthVolume);
    });

    test('empatar el mejor volumen del mes NO es batirlo', () {
      final session = _session(totalVolumeKg: 1500);
      final result = deriveSessionRecognition(
        session: session,
        sessionsDesc: [
          session,
          _session(
            id: 'p1',
            // Mes anterior en el mismo lunes-semana no existe: usar una
            // previa del mismo mes, semana distinta, mismo volumen.
            startedAt: DateTime.utc(2026, 5, 4, 10),
            totalVolumeKg: 1500,
          ),
        ],
        recordCount: 0,
      );

      expect(result.kind, SessionRecognitionKind.none);
    });

    test('sin sesión previa en el mes, la regla de mes no aplica', () {
      final session = _session(totalVolumeKg: 2000);
      final result = deriveSessionRecognition(
        session: session,
        sessionsDesc: [
          session,
          // Abril: otro mes ART, volumen menor — no habilita bestMonthVolume.
          _session(
            id: 'p1',
            startedAt: DateTime.utc(2026, 4, 20, 10),
            totalVolumeKg: 100,
          ),
        ],
        recordCount: 0,
      );

      expect(result.kind, SessionRecognitionKind.none);
    });

    test('sesión sin volumen (0 kg) nunca es bestMonthVolume', () {
      final session = _session(totalVolumeKg: 0);
      final result = deriveSessionRecognition(
        session: session,
        sessionsDesc: [
          session,
          _session(
            id: 'p1',
            startedAt: DateTime.utc(2026, 5, 4, 10),
            totalVolumeKg: 0,
          ),
        ],
        recordCount: 0,
      );

      expect(result.kind, SessionRecognitionKind.none);
    });

    test('2ª+ sesión de la semana ART (lunes-domingo) → nthSessionOfWeek', () {
      // Jueves 2026-05-21.
      final session = _session(startedAt: DateTime.utc(2026, 5, 21, 10));
      final result = deriveSessionRecognition(
        session: session,
        sessionsDesc: [
          session,
          // Lunes y martes de la misma semana — mismo volumen para no
          // disparar bestMonthVolume.
          _session(id: 'p1', startedAt: DateTime.utc(2026, 5, 18, 10)),
          _session(id: 'p2', startedAt: DateTime.utc(2026, 5, 19, 10)),
        ],
        recordCount: 0,
      );

      expect(result.kind, SessionRecognitionKind.nthSessionOfWeek);
      expect(result.count, 3);
    });

    test('borde ART: domingo 23:00 ART cae en la semana anterior', () {
      // Sesión: lunes 2026-05-18 01:00 ART (04:00 UTC).
      final session = _session(startedAt: DateTime.utc(2026, 5, 18, 4));
      final result = deriveSessionRecognition(
        session: session,
        sessionsDesc: [
          session,
          // Previa: 02:00 UTC del lunes = domingo 23:00 ART → semana ANTERIOR.
          _session(id: 'p1', startedAt: DateTime.utc(2026, 5, 18, 2)),
        ],
        recordCount: 0,
      );

      // La única previa quedó fuera de la semana → n=1 → sin banner. Tampoco
      // es bestMonthVolume porque la previa del mes tiene el mismo volumen.
      expect(result.kind, SessionRecognitionKind.none);
    });

    test('bestMonthVolume tiene prioridad sobre nthSessionOfWeek', () {
      // Jueves 2026-05-21, con una previa del martes de la MISMA semana y
      // mismo mes con volumen menor → ambas reglas aplican.
      final session = _session(
        startedAt: DateTime.utc(2026, 5, 21, 10),
        totalVolumeKg: 2000,
      );
      final result = deriveSessionRecognition(
        session: session,
        sessionsDesc: [
          session,
          _session(
            id: 'p1',
            startedAt: DateTime.utc(2026, 5, 19, 10),
            totalVolumeKg: 1000,
          ),
        ],
        recordCount: 0,
      );

      expect(result.kind, SessionRecognitionKind.bestMonthVolume);
    });
  });
}
