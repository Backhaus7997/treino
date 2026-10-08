import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/core/utils/argentina_time.dart';
import 'package:treino/features/payments/domain/payment.dart';

/// Ventana de tiempo del listado de Pagos.
///
/// Pedido del PF junto al paginado: «con esto agregar filtros de tiempo».
/// Es la otra mitad de la misma idea — el paginado corta CUÁNTAS filas se ven
/// de una, esto corta CUÁLES entran en la lista.
enum PagosPeriodo { treintaDias, tresMeses, doceMeses, todo }

extension PagosPeriodoX on PagosPeriodo {
  String get label => switch (this) {
        PagosPeriodo.treintaDias => 'Últimos 30 días', // i18n
        PagosPeriodo.tresMeses => 'Últimos 3 meses', // i18n
        PagosPeriodo.doceMeses => 'Últimos 12 meses', // i18n
        PagosPeriodo.todo => 'Todo el historial', // i18n
      };

  /// Días hacia atrás, o `null` para «todo».
  int? get dias => switch (this) {
        PagosPeriodo.treintaDias => 30,
        PagosPeriodo.tresMeses => 90,
        PagosPeriodo.doceMeses => 365,
        PagosPeriodo.todo => null,
      };
}

/// Arranca en [PagosPeriodo.todo] a propósito.
///
/// Una ventana por default esconde pagos sin avisar, y el primero que se
/// esconde es siempre el más viejo — que en una lista de deudas es justamente
/// el que más importa. Que el PF elija achicar; nadie le achica la vista sin
/// que la haya pedido.
final pagosPeriodoProvider =
    StateProvider.autoDispose<PagosPeriodo>((_) => PagosPeriodo.todo);

/// Filtra [payments] a la ventana [periodo], contra [now].
///
/// La fecha que manda es `dueAt ?? createdAt` — la MISMA con la que ordena la
/// columna VENCIMIENTO y con la que los buckets deciden vencido/por-vencer.
/// Un pago sin vencimiento cae en su fecha de alta, que es lo único que se
/// sabe de él.
///
/// Filtrar por `paidAt` sería otra cosa —«qué cobré este mes»— y dejaría a
/// todos los pendientes afuera de cualquier ventana, que es exactamente el
/// caso que el PF quiere ver.
List<Payment> filtrarPorPeriodo(
  List<Payment> payments,
  PagosPeriodo periodo, {
  DateTime? now,
}) {
  final dias = periodo.dias;
  if (dias == null) return payments;
  final corte = (now ?? argentinaNow()).subtract(Duration(days: dias));
  return [
    for (final p in payments)
      if (!(p.dueAt ?? p.createdAt).isBefore(corte)) p,
  ];
}
