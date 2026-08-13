// Tests del modelo de check-in (#643 slice 1).
//
// El foco NO es "freezed serializa" — eso lo garantiza el generador. Es el
// contrato que sí puede romperse en silencio: la clave de fecha LOCAL que hace
// de id del documento, y que las zonas de dolor viajen en el vocabulario
// canónico de MuscleGroup y no en nombres de símbolos Dart.

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/checkins/domain/check_in.dart';
import 'package:treino/features/workout/domain/muscle_group.dart';

void main() {
  // ── checkInDateKey ────────────────────────────────────────────────────────

  group('checkInDateKey', () {
    test('formatea YYYY-MM-DD con padding de mes y día', () {
      expect(checkInDateKey(DateTime(2026, 1, 5)), '2026-01-05');
      expect(checkInDateKey(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('usa los componentes LOCALES, no los de UTC', () {
      // 2026-05-18 22:30 local. En UTC-3 esto es el 19 en UTC; el usuario que
      // entrenó de noche espera que su registro cuente para HOY.
      final local = DateTime(2026, 5, 18, 22, 30);
      expect(checkInDateKey(local), '2026-05-18');
      expect(checkInDateKey(local), isNot(contains('19')));
    });

    test('la hora no cambia la clave: todo el día cae en el mismo documento',
        () {
      expect(
        checkInDateKey(DateTime(2026, 5, 18, 0, 0)),
        checkInDateKey(DateTime(2026, 5, 18, 23, 59)),
      );
    });
  });

  // ── Serialización ─────────────────────────────────────────────────────────

  group('CheckIn serialización', () {
    final recordedAt = DateTime.utc(2026, 5, 18, 23, 30);

    CheckIn build({
      bool hasPain = false,
      List<MuscleGroup> painAreas = const [],
      String? note,
      String? sessionId,
      CheckInFeeling feeling = CheckInFeeling.bien,
    }) =>
        CheckIn(
          date: '2026-05-18',
          feeling: feeling,
          hasPain: hasPain,
          painAreas: painAreas,
          note: note,
          recordedAt: recordedAt,
          sessionId: sessionId,
        );

    test('la sensación se persiste con su valor de wire, no con el nombre Dart',
        () {
      expect(build(feeling: CheckInFeeling.muyMal).toJson()['feeling'],
          'very_bad');
      expect(
          build(feeling: CheckInFeeling.muyBien).toJson()['feeling'], 'great');
      // Si esto rompe es porque alguien renombró el enum y arrastró los datos.
      expect(
        CheckInFeeling.values.map((f) => f.wire),
        ['very_bad', 'bad', 'neutral', 'good', 'great'],
      );
    });

    test('las zonas se persisten como CLAVES canónicas de MuscleGroup', () {
      final json = build(
        hasPain: true,
        painAreas: [MuscleGroup.cuadriceps, MuscleGroup.espalda],
      ).toJson();

      expect(json['painAreas'], ['quads', 'back']);
      // El default de json_serializable habría escrito los nombres Dart: eso
      // rompería el vocabulario único que comparten catálogo, picker e
      // Insights.
      expect(json['painAreas'], isNot(contains('cuadriceps')));
    });

    test('round-trip completo conserva todos los campos', () {
      final original = build(
        hasPain: true,
        painAreas: [MuscleGroup.gluteos],
        note: 'Rodilla molestando en las sentadillas',
        sessionId: 's1',
      );

      final decoded = CheckIn.fromJson(original.toJson());

      expect(decoded, original);
    });

    test('lee etiquetas en español legacy y las canonicaliza', () {
      final decoded = CheckIn.fromJson({
        'date': '2026-05-18',
        'feeling': 'bad',
        'hasPain': true,
        'painAreas': ['Gemelos', 'Espalda alta'],
        'recordedAt': Timestamp.fromDate(recordedAt),
      });

      expect(decoded.painAreas, [MuscleGroup.pantorrilla, MuscleGroup.espalda]);
    });

    test('una zona desconocida se descarta sin romper el documento entero', () {
      final decoded = CheckIn.fromJson({
        'date': '2026-05-18',
        'feeling': 'neutral',
        'hasPain': true,
        'painAreas': ['quads', 'Otro', 'zona_inventada', 42],
        'recordedAt': Timestamp.fromDate(recordedAt),
      });

      expect(decoded.painAreas, [MuscleGroup.cuadriceps]);
      expect(decoded.feeling, CheckInFeeling.normal);
    });

    test('los campos opcionales tienen defaults sanos cuando el doc es mínimo',
        () {
      final decoded = CheckIn.fromJson({
        'date': '2026-05-18',
        'feeling': 'good',
        'recordedAt': Timestamp.fromDate(recordedAt),
      });

      expect(decoded.hasPain, isFalse);
      expect(decoded.painAreas, isEmpty);
      expect(decoded.note, isNull);
      expect(decoded.sessionId, isNull);
    });
  });

  // ── Escala y taxonomía ────────────────────────────────────────────────────

  group('CheckInFeeling', () {
    test('son 5 niveles ordenados de peor a mejor', () {
      expect(CheckInFeeling.displayOrder, hasLength(5));
      expect(CheckInFeeling.displayOrder.first, CheckInFeeling.muyMal);
      expect(CheckInFeeling.displayOrder.last, CheckInFeeling.muyBien);
    });

    test('fromWire resuelve lo persistido y devuelve null ante basura', () {
      expect(CheckInFeeling.fromWire('neutral'), CheckInFeeling.normal);
      expect(CheckInFeeling.fromWire('7'), isNull);
      expect(CheckInFeeling.fromWire(null), isNull);
    });

    test('cada nivel tiene su emoji, sin repetidos', () {
      final emojis = CheckInFeeling.values.map((f) => f.emoji).toSet();
      expect(emojis, hasLength(5));
    });
  });

  group('kCheckInPainAreas', () {
    test('es la taxonomía de MuscleGroup sin cardio', () {
      expect(kCheckInPainAreas, isNot(contains(MuscleGroup.cardio)));
      expect(kCheckInPainAreas, hasLength(MuscleGroup.values.length - 1));
      // No se inventa nada nuevo: todo lo ofrecido sale del vocabulario único.
      for (final group in kCheckInPainAreas) {
        expect(MuscleGroup.values, contains(group));
      }
    });

    test('conserva el orden canónico del resto de la app', () {
      expect(
        kCheckInPainAreas,
        MuscleGroup.displayOrder.where((g) => g != MuscleGroup.cardio),
      );
    });
  });
}
