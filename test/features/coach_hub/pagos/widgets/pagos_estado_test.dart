import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/argentina_time.dart';
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

  // #1824 — `dueAt` es un instante real (el fin del día ART que eligió el PF) y
  // los callers pasan `argentinaNow()`: wall-clock ART. Comparar los dos en
  // marcos distintos corría las etiquetas un día.
  //
  // Los `now` se arman como lo hace la app, con `toArgentina(<instante real>)`.
  group('pagoEstadoOf — dueAt contra un now ya en ART (#1824)', () {
    // `4 nov 23:59:59 ART` = `5 nov 02:59:59 UTC`, como lo guardan los diálogos
    // de cobro.
    final finDelDia4 = DateTime.utc(2026, 11, 5, 2, 59, 59);

    Payment pendienteConVencimiento([DateTime? dueAt]) => _payment(
          status: PaymentStatus.pending,
          createdAt: DateTime.utc(2026, 10, 1),
          dueAt: dueAt ?? finDelDia4,
        );

    ({PagoEstado estado, String label}) a(DateTime instanteReal,
            [DateTime? dueAt]) =>
        pagoEstadoOf(
          pendienteConVencimiento(dueAt),
          toArgentina(instanteReal),
        );

    test('el día del vencimiento a las 10:00 ART dice «Hoy», no «Mañana»', () {
      // 4 nov 10:00 ART = 13:00 UTC: el caso del issue.
      final info = a(DateTime.utc(2026, 11, 4, 13));

      expect(info.estado, PagoEstado.porVencer);
      expect(info.label, 'Hoy');
    });

    test('a las 23:59:00 ART del día del vencimiento todavía es «Hoy»', () {
      final info = a(DateTime.utc(2026, 11, 5, 2, 59)); // 4 nov 23:59 ART

      expect(info.estado, PagoEstado.porVencer);
      expect(info.label, 'Hoy');
    });

    test('un día antes: «Mañana»; cinco antes: «En 5 días»', () {
      expect(a(DateTime.utc(2026, 11, 3, 13)).label, 'Mañana');
      expect(a(DateTime.utc(2026, 10, 30, 13)).label, 'En 5 días');
    });

    test(
        'pasada la medianoche ART ya está vencido, «Vencido 1d»: antes seguía '
        '«por vencer» hasta las 03:00', () {
      // 5 nov 00:30 ART = 03:30 UTC.
      final info = a(DateTime.utc(2026, 11, 5, 3, 30));

      expect(info.estado, PagoEstado.vencido);
      expect(info.label, 'Vencido 1d');
    });

    test('«Vencido Nd» cuenta días de calendario ART', () {
      // 7 nov 10:00 ART: vencía el 4.
      expect(a(DateTime.utc(2026, 11, 7, 13)).label, 'Vencido 3d');
    });

    test('un vencimiento a las 00:00 UTC (21:00 ART del día anterior)', () {
      // El borde donde el día UTC y el día ART difieren por la noche: el 5 nov
      // 00:00 UTC es el 4 nov a las 21:00 ART. Mirado a las 22:00 ART del 4
      // —ya pasó— es «Vencido 1d» (mínimo 1); y a las 10:00 ART, «Hoy».
      final due = DateTime.utc(2026, 11, 5);

      expect(a(DateTime.utc(2026, 11, 5, 1), due).label, 'Vencido 1d');
      expect(a(DateTime.utc(2026, 11, 4, 13), due).label, 'Hoy');
    });

    test('«Pagado» no depende del marco', () {
      final p = _payment(
        status: PaymentStatus.paid,
        createdAt: DateTime.utc(2026, 11, 1),
        dueAt: finDelDia4,
      );

      expect(
        pagoEstadoOf(p, toArgentina(DateTime.utc(2026, 11, 5, 3, 30))).estado,
        PagoEstado.pagado,
      );
    });
  });
}
