import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_priority.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';

TrainerLink _link(String id, TrainerLinkStatus status, int dia) => TrainerLink(
      id: id,
      trainerId: 'pf',
      athleteId: 'alumno',
      status: status,
      requestedAt: DateTime.utc(2026, 1, dia),
    );

void main() {
  group('vinculoPrioritario', () {
    test('sin vínculos → null', () {
      expect(vinculoPrioritario(const []), isNull);
    });

    test('un solo vínculo → ese vínculo', () {
      final l = _link('a', TrainerLinkStatus.pending, 1);
      expect(vinculoPrioritario([l]), l);
    });

    test('active > paused > pending, sin importar el orden de la lista', () {
      final activo = _link('activo', TrainerLinkStatus.active, 1);
      final pausado = _link('pausado', TrainerLinkStatus.paused, 2);
      final pendiente = _link('pendiente', TrainerLinkStatus.pending, 3);

      for (final orden in [
        [activo, pausado, pendiente],
        [pendiente, pausado, activo],
        [pausado, pendiente, activo],
        [pendiente, activo, pausado],
      ]) {
        expect(vinculoPrioritario(orden), activo, reason: '$orden');
      }
      expect(vinculoPrioritario([pendiente, pausado]), pausado);
    });

    test('un terminated pierde contra cualquier otro estado', () {
      final terminado = _link('t', TrainerLinkStatus.terminated, 9);
      final pendiente = _link('p', TrainerLinkStatus.pending, 1);
      expect(vinculoPrioritario([terminado, pendiente]), pendiente);
      expect(vinculoPrioritario([terminado]), terminado);
    });

    test('a igual estado gana el más reciente', () {
      final vieja = _link('vieja', TrainerLinkStatus.pending, 1);
      final nueva = _link('nueva', TrainerLinkStatus.pending, 2);
      expect(vinculoPrioritario([vieja, nueva]), nueva);
      expect(vinculoPrioritario([nueva, vieja]), nueva);
    });

    test('el caso de #1735: active VIEJA + pending NUEVA → la activa', () {
      // Es la lista que entrega el stream (requestedAt DESC): la pending, que
      // es la más nueva, viene primero, y `.first` la elegía.
      final nueva = _link('nueva', TrainerLinkStatus.pending, 2);
      final vieja = _link('vieja', TrainerLinkStatus.active, 1);
      expect(vinculoPrioritario([nueva, vieja]), vieja);
    });
  });
}
