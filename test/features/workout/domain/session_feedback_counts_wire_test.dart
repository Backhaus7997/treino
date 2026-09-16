// `feedbackCounts` se LEE del wire, no se escribe.
//
// ── Por qué existe este archivo ──────────────────────────────────────────────
//
// La regla de Firestore rechaza `feedbackCounts` en el `create` de una sesión:
// el campo es del backend y un cliente parcheado no puede traerlo puesto. Hay
// un test de reglas que lo cubre — y pasaba en verde mientras la app estaba
// ROTA en producción.
//
// El agujero: ese test arma el payload A MANO. La app manda
// `ref.set(session.toJson())`, y el `toJson` generado emitía la clave siempre,
// con el mapa vacío del `@Default`. O sea que la regla rechazaba cada sesión
// nueva y el atleta veía "No pudimos iniciar la sesión" al intentar entrenar.
//
// Un test que construye su propio payload verifica la REGLA. Éste verifica lo
// que el CLIENTE MANDA, que es la mitad que faltaba. Los dos hacen falta:
// entre "la regla rechaza X" y "la app no manda X" hay un producto roto.

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/exercise_feedback.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';

Session _session({Map<ExerciseFeedbackKind, int> counts = const {}}) => Session(
      id: 's1',
      uid: 'u1',
      routineId: 'r1',
      routineName: 'Piernas',
      startedAt: DateTime.utc(2026, 5, 19, 13),
      status: SessionStatus.active,
      feedbackCounts: counts,
    );

void main() {
  test('toJson NO emite feedbackCounts — la regla del create lo rechaza', () {
    expect(
      _session().toJson().containsKey('feedbackCounts'),
      isFalse,
      reason: 'con la clave presente, `create` devuelve permission-denied y no '
          'se puede empezar a entrenar',
    );
  });

  test('tampoco lo emite con el mapa LLENO — el campo es del backend', () {
    // Aunque el objeto en memoria traiga contadores (porque se leyó de
    // Firestore), serializarlo no puede reenviarlos: el cliente no es quien
    // los escribe, y un `set` con el mapa adentro volvería a chocar la regla.
    final json = _session(
      counts: const {ExerciseFeedbackKind.discomfort: 2},
    ).toJson();

    expect(json.containsKey('feedbackCounts'), isFalse);
  });

  test('CONTROL — el resto de los campos SÍ se serializan', () {
    // Sin esto, un `toJson` que devolviera `{}` pasaría los dos tests de
    // arriba y rompería todo lo demás.
    final json = _session().toJson();

    expect(json['uid'], 'u1');
    expect(json['routineName'], 'Piernas');
    expect(json['status'], 'active');
    expect(json.containsKey('startedAt'), isTrue);
  });

  test('fromJson SÍ lo lee — es de lectura, no invisible', () {
    final s = Session.fromJson({
      'id': 's1',
      'uid': 'u1',
      'routineId': 'r1',
      'routineName': 'Piernas',
      'startedAt': Timestamp.fromDate(DateTime.utc(2026, 5, 19, 13)),
      'status': 'active',
      'feedbackCounts': {'discomfort': 2, 'comment': 1},
    });

    expect(s.feedbackCounts, {
      ExerciseFeedbackKind.discomfort: 2,
      ExerciseFeedbackKind.comment: 1,
    });
  });

  test('sin el campo en el wire, queda el mapa vacío', () {
    final s = Session.fromJson({
      'id': 's1',
      'uid': 'u1',
      'routineId': 'r1',
      'routineName': 'Piernas',
      'startedAt': Timestamp.fromDate(DateTime.utc(2026, 5, 19, 13)),
      'status': 'active',
    });

    expect(s.feedbackCounts, isEmpty);
  });
}
