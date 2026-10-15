import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/watch/presentation/wear/wear_set_format.dart';
import 'package:treino/features/workout/domain/set_spec.dart';

void main() {
  group('series por distancia en el reloj', () {
    test('muestra metros enteros en lugar de un guion', () {
      expect(describeSetSpec(const SetSpec(distanceMeters: 6)), '6 m');
    });

    test('conserva una distancia fraccionaria', () {
      expect(describeSetSpec(const SetSpec(distanceMeters: 8.5)), '8.5 m');
    });

    test('documentos viejos sin distancia siguen usando reps', () {
      expect(describeSetSpec(const SetSpec(reps: 10)), '10');
    });
  });
}
