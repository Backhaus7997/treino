import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_periodo_provider.dart';
import 'package:treino/features/payments/domain/payment.dart';

final _ahora = DateTime.utc(2026, 9, 9, 12);

Payment _pago(String id, {required int diasAtras, bool conVencimiento = true}) {
  final fecha = _ahora.subtract(Duration(days: diasAtras));
  return Payment(
    id: id,
    trainerId: 't1',
    athleteId: 'a1',
    amountArs: 1000,
    concept: id,
    status: PaymentStatus.pending,
    // `createdAt` deliberadamente MUY viejo cuando hay `dueAt`: así un test
    // que pase mirando `createdAt` en vez de `dueAt` falla en vez de pasar
    // por casualidad.
    createdAt: conVencimiento ? DateTime.utc(2020) : fecha,
    dueAt: conVencimiento ? fecha : null,
  );
}

void main() {
  group('filtrarPorPeriodo', () {
    final pagos = [
      _pago('hoy', diasAtras: 0),
      _pago('hace10', diasAtras: 10),
      _pago('hace60', diasAtras: 60),
      _pago('hace200', diasAtras: 200),
      _pago('hace500', diasAtras: 500),
    ];

    test('«todo» no filtra nada', () {
      expect(
        filtrarPorPeriodo(pagos, PagosPeriodo.todo, now: _ahora).length,
        pagos.length,
      );
    });

    test('30 días deja los dos más nuevos', () {
      final r = filtrarPorPeriodo(pagos, PagosPeriodo.treintaDias, now: _ahora);
      expect(r.map((p) => p.id), ['hoy', 'hace10']);
    });

    test('3 meses suma el de 60 días', () {
      final r = filtrarPorPeriodo(pagos, PagosPeriodo.tresMeses, now: _ahora);
      expect(r.map((p) => p.id), ['hoy', 'hace10', 'hace60']);
    });

    test('12 meses suma el de 200 y deja afuera el de 500', () {
      final r = filtrarPorPeriodo(pagos, PagosPeriodo.doceMeses, now: _ahora);
      expect(r.map((p) => p.id), ['hoy', 'hace10', 'hace60', 'hace200']);
    });

    test('manda dueAt, no createdAt', () {
      // Los pagos de arriba tienen `createdAt` en 2020. Si el filtro mirara
      // esa fecha, ninguno entraría en 30 días y el test de arriba habría
      // pasado devolviendo vacío… si no fuera porque afirma los ids.
      // Este lo dice explícito.
      final soloCreated = [
        _pago('sinVenc', diasAtras: 5, conVencimiento: false)
      ];
      expect(
        filtrarPorPeriodo(soloCreated, PagosPeriodo.treintaDias, now: _ahora)
            .length,
        1,
        reason: 'sin dueAt cae en su fecha de alta',
      );
    });

    test('el borde exacto ENTRA', () {
      // Un pago que vence justo en el corte es del período. Excluirlo hace que
      // una fila desaparezca de la lista el día en que más se la mira.
      final borde = [_pago('borde', diasAtras: 30)];
      expect(
        filtrarPorPeriodo(borde, PagosPeriodo.treintaDias, now: _ahora).length,
        1,
      );
    });

    test('lista vacía no explota', () {
      expect(
        filtrarPorPeriodo(const [], PagosPeriodo.treintaDias, now: _ahora),
        isEmpty,
      );
    });
  });

  group('PagosPeriodo — la ventana por default', () {
    test('todas las opciones tienen etiqueta', () {
      for (final p in PagosPeriodo.values) {
        expect(p.label, isNotEmpty);
      }
    });

    test('sólo «todo» no tiene días', () {
      expect(PagosPeriodo.todo.dias, isNull);
      for (final p
          in PagosPeriodo.values.where((p) => p != PagosPeriodo.todo)) {
        expect(p.dias, isNotNull);
        expect(p.dias, greaterThan(0));
      }
    });
  });
}
