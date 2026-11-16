import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/presentation/widgets/best_set_label.dart';
import 'package:treino/l10n/app_l10n.dart';

/// La regla de la mejor serie que comparten el resumen post-entreno y el
/// HISTORIAL del detalle de ejercicio (#1716). El orden importa: peso, tiempo,
/// metros, reps de peso corporal, nada.
void main() {
  final l10n = lookupAppL10n(const Locale('es', 'AR'));

  String? label({
    double weightKg = 0,
    int reps = 0,
    int? durationSeconds,
    double? distanceMeters,
    String bodyweightSuffix = '',
  }) =>
      bestSetLabel(
        l10n: l10n,
        weightKg: weightKg,
        reps: reps,
        durationSeconds: durationSeconds,
        distanceMeters: distanceMeters,
        bodyweightSuffix: bodyweightSuffix,
      );

  test('una serie con carga es «kg × reps», con el separador del locale', () {
    expect(label(weightKg: 80, reps: 5), '80 kg × 5');
    expect(label(weightKg: 87.5, reps: 3), '87,5 kg × 3');
  });

  test('por tiempo muestra el tiempo, no «0 reps»', () {
    expect(label(durationSeconds: 60), '01:00');
    expect(label(durationSeconds: 45), '00:45');
  });

  test('por distancia muestra los metros, no «0 reps»', () {
    expect(label(distanceMeters: 40), '40 m');
    expect(label(distanceMeters: 100.5), '100,5 m');
  });

  test('el peso gana sobre la métrica y el tiempo sobre la distancia', () {
    expect(label(weightKg: 20, reps: 10, durationSeconds: 30), '20 kg × 10');
    expect(label(durationSeconds: 30, distanceMeters: 40), '00:30');
  });

  test('peso corporal: «N reps», con el sufijo sólo si quien llama lo pide',
      () {
    expect(label(reps: 12), '12 reps');
    expect(
      label(reps: 12, bodyweightSuffix: ' · peso corporal'),
      '12 reps · peso corporal',
    );
  });

  test('el sufijo no se pega a las series con carga ni a las de métrica', () {
    expect(
      label(weightKg: 80, reps: 5, bodyweightSuffix: ' · peso corporal'),
      '80 kg × 5',
    );
    expect(
      label(durationSeconds: 60, bodyweightSuffix: ' · peso corporal'),
      '01:00',
    );
  });

  test('serie vieja sin métrica ni reps: no hay mejor serie (null)', () {
    expect(label(), isNull);
    expect(label(bodyweightSuffix: ' · peso corporal'), isNull);
  });
}
