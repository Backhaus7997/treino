import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_estado.dart';
import 'package:treino/features/payments/domain/payment.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

// Fecha de referencia fija (evita flakiness de reloj real).
final _now = DateTime.utc(2026, 7, 21, 12, 0, 0);
final _periodStart = DateTime.utc(_now.year, _now.month, 1);

Payment _payment({
  required PaymentStatus status,
  required DateTime createdAt,
  DateTime? dueAt,
}) =>
    Payment(
      id: 'p1',
      trainerId: 'trainer-1',
      athleteId: 'athlete-1',
      amountArs: 1000,
      concept: 'Test',
      status: status,
      createdAt: createdAt,
      dueAt: dueAt,
      paidAt: status == PaymentStatus.paid ? createdAt : null,
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('pagoEstadoOf', () {
    test('paid → (pagado, "Pagado")', () {
      final p = _payment(status: PaymentStatus.paid, createdAt: _now);

      final info = pagoEstadoOf(p, _now);

      expect(info.estado, PagoEstado.pagado);
      expect(info.label, 'Pagado');
    });

    test('pending con dueAt vencido hace 3 días → (vencido, "Vencido 3d")', () {
      final p = _payment(
        status: PaymentStatus.pending,
        createdAt: _now.subtract(const Duration(days: 10)),
        dueAt: _now.subtract(const Duration(days: 3)),
      );

      final info = pagoEstadoOf(p, _now);

      expect(info.estado, PagoEstado.vencido);
      expect(info.label, 'Vencido 3d');
    });

    test(
        'pending con dueAt vencido hace pocas horas en el mismo día de '
        'calendario → mínimo 1 día ("Vencido 1d")', () {
      final p = _payment(
        status: PaymentStatus.pending,
        createdAt: _now.subtract(const Duration(days: 10)),
        dueAt: _now.subtract(const Duration(hours: 2)),
      );

      final info = pagoEstadoOf(p, _now);

      expect(info.estado, PagoEstado.vencido);
      expect(info.label, 'Vencido 1d');
    });

    test('pending con dueAt hoy (mismo día) → (porVencer, "Hoy")', () {
      final p = _payment(
        status: PaymentStatus.pending,
        createdAt: _now.subtract(const Duration(days: 1)),
        dueAt: _now.add(const Duration(hours: 3)),
      );

      final info = pagoEstadoOf(p, _now);

      expect(info.estado, PagoEstado.porVencer);
      expect(info.label, 'Hoy');
    });

    test('pending con dueAt mañana → (porVencer, "Mañana")', () {
      final p = _payment(
        status: PaymentStatus.pending,
        createdAt: _now.subtract(const Duration(days: 1)),
        dueAt: _now.add(const Duration(days: 1)),
      );

      final info = pagoEstadoOf(p, _now);

      expect(info.estado, PagoEstado.porVencer);
      expect(info.label, 'Mañana');
    });

    test('pending con dueAt en 5 días → (porVencer, "En 5 días")', () {
      final p = _payment(
        status: PaymentStatus.pending,
        createdAt: _now.subtract(const Duration(days: 1)),
        dueAt: _now.add(const Duration(days: 5)),
      );

      final info = pagoEstadoOf(p, _now);

      expect(info.estado, PagoEstado.porVencer);
      expect(info.label, 'En 5 días');
    });

    test(
        'legacy (dueAt null) con createdAt anterior al inicio del mes → '
        '(vencido, "Vencido")', () {
      final p = _payment(
        status: PaymentStatus.pending,
        createdAt: _periodStart.subtract(const Duration(days: 1)),
      );

      final info = pagoEstadoOf(p, _now);

      expect(info.estado, PagoEstado.vencido);
      expect(info.label, 'Vencido');
    });

    test(
        'legacy (dueAt null) con createdAt del período actual → '
        '(porVencer, "Pendiente")', () {
      final p = _payment(
        status: PaymentStatus.pending,
        createdAt: _periodStart,
      );

      final info = pagoEstadoOf(p, _now);

      expect(info.estado, PagoEstado.porVencer);
      expect(info.label, 'Pendiente');
    });
  });
}
