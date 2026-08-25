import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/exercise_feedback.dart';

void main() {
  group('ExerciseFeedback', () {
    final createdAt = DateTime.utc(2026, 8, 24, 18, 30, 0);

    ExerciseFeedback build({
      int? setNumber = 3,
      ExerciseFeedbackKind kind = ExerciseFeedbackKind.comment,
      String? text = 'La barra se me va para la derecha',
      String? photoUrl,
      String? photoPath,
    }) {
      return ExerciseFeedback(
        id: 'fb-1',
        exerciseId: 'bench-press',
        exerciseName: 'Press de banca',
        setNumber: setNumber,
        kind: kind,
        text: text,
        photoUrl: photoUrl,
        photoPath: photoPath,
        createdAt: createdAt,
      );
    }

    test('round-trip JSON con foto ausente', () {
      final decoded = ExerciseFeedback.fromJson(build().toJson());
      expect(decoded, equals(build()));
      expect(decoded.createdAt, equals(createdAt));
      expect(decoded.setNumber, equals(3));
      expect(decoded.photoUrl, isNull);
    });

    test('round-trip JSON de una molestia con foto y sin texto', () {
      final original = build(
        kind: ExerciseFeedbackKind.discomfort,
        text: null,
        photoUrl:
            'https://firebasestorage.googleapis.com/v0/b/x/o/y?alt=media&token=z',
        photoPath: 'sessionFeedback/uid-1/session-1/fb-1.jpg',
      );
      final decoded = ExerciseFeedback.fromJson(original.toJson());
      expect(decoded, equals(original));
      expect(decoded.isDiscomfort, isTrue);
      expect(decoded.photoPath,
          equals('sessionFeedback/uid-1/session-1/fb-1.jpg'));
    });

    test('el wire value del kind es el que pinea firestore.rules', () {
      // El enum de las reglas es ['comment', 'discomfort'] literal. Si esto
      // cambiara sin tocar la regla, todo write se cae con permission-denied.
      expect(build().toJson()['kind'], equals('comment'));
      expect(
        build(kind: ExerciseFeedbackKind.discomfort).toJson()['kind'],
        equals('discomfort'),
      );
    });

    test('setNumber null sobrevive el round-trip — comentario sin serie', () {
      final decoded =
          ExerciseFeedback.fromJson(build(setNumber: null).toJson());
      expect(decoded.setNumber, isNull);
    });

    test('un kind desconocido cae a comment en vez de perder el reporte', () {
      // Dirección de falla deliberada: perder el badge es recuperable, perder
      // el reporte de una molestia no.
      final json = build().toJson()..['kind'] = 'algo-que-no-existe-todavia';
      expect(
        ExerciseFeedback.fromJson(json).kind,
        equals(ExerciseFeedbackKind.comment),
      );
    });

    group('hasContent — "nada de reportes vacíos"', () {
      test('texto solo alcanza', () {
        expect(build().hasContent, isTrue);
      });

      test('foto sola alcanza', () {
        expect(build(text: null, photoUrl: 'https://x/y').hasContent, isTrue);
      });

      test('ninguno de los dos no alcanza', () {
        expect(build(text: null).hasContent, isFalse);
      });

      test('el whitespace no cuenta como texto', () {
        // Espejo del `.size() > 0` de firestore.rules sobre el texto, con una
        // vuelta más: acá también se descarta "   ", que del lado del servidor
        // pasaría. El cliente es más estricto a propósito.
        expect(build(text: '   ').hasContent, isFalse);
        expect(build(text: '').hasContent, isFalse);
      });
    });
  });
}
