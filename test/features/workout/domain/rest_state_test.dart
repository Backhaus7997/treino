import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/rest_rules.dart';
import 'package:treino/features/workout/domain/rest_state.dart';

void main() {
  group('RestState.startedAt', () {
    // Los dos lados del redondeo de `RestRules.endsAt`: con microsegundos
    // < 500 redondeaba para abajo y con ≥ 500 para ARRIBA, que es el que daba
    // 91 s en un descanso de 90 (y «1:31» en la barra del teléfono).
    for (final micros in [0, 1, 499, 500, 501, 999]) {
      test('un descanso de 90 s marcado con $micros µs muestra 90, no 91', () {
        final inicio = DateTime.utc(2026, 10, 22, 15, 30, 14, 858, micros);
        final descanso = RestState.startedAt(
          exerciseId: 'e1',
          setNumber: 1,
          totalSeconds: 90,
          start: inicio,
          owner: RestOwner.telefono,
        );

        expect(RestRules.remaining(endsAt: descanso.endsAt, now: inicio), 90);
        expect(descanso.endsAt.isAfter(inicio.add(const Duration(seconds: 90))),
            isFalse,
            reason: 'el fin nunca puede quedar después de inicio + total');
      });
    }
  });
}
