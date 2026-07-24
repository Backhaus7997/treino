/// Proveedor de pagos agrupados en 4 buckets para la pantalla Pagos del Coach
/// Hub web.
///
/// Nuevo en PR2a — web-only, autoDispose. Compone [trainerPaymentsProvider]
/// particionando en Vencidos / Por vencer / Pagados / Todos.
///
/// Sección: coach_hub/pagos — contrato: sin Scaffold, sin HEX, es-AR + // i18n.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/features/payments/application/payment_providers.dart'
    show trainerPaymentsProvider;
import 'package:treino/features/payments/domain/payment.dart';

// ── Result type ───────────────────────────────────────────────────────────────

/// Cuatro buckets mutuamente excluyentes derivados del stream de pagos.
///
/// Boundary (ADR-PGW-002, updated REQ-VENC-11):
///   Vencido = pending && (
///     dueAt != null  → dueAt.toUtc().isBefore(now)
///     dueAt == null  → createdAt.toUtc().isBefore(periodStart) [legacy fallback]
///   )
/// Por vencer = pending && NOT vencido.
/// Cada bucket está ordenado DESC por createdAt.
class PagosBuckets {
  const PagosBuckets({
    required this.vencidos,
    required this.porVencer,
    required this.pagados,
    required this.todos,
  });

  /// Pagos pendientes cuyo dueAt (si presente) ya pasó, o cuyo createdAt es
  /// anterior al inicio del mes actual cuando dueAt es null (legado).
  final List<Payment> vencidos;

  /// Pagos pendientes del período actual (no vencidos).
  final List<Payment> porVencer;

  /// Pagos con status == paid.
  final List<Payment> pagados;

  /// Todos los pagos (sin filtro).
  final List<Payment> todos;
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// Pure computation — particiona [payments] en los 4 buckets.
PagosBuckets _computeBuckets(List<Payment> payments) {
  final now = DateTime.now().toUtc();
  final periodStart = DateTime.utc(now.year, now.month, 1);

  List<Payment> desc(List<Payment> list) =>
      list..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  // Partition pending into vencidos vs porVencer (mutually exclusive).
  final vencidos = <Payment>[];
  final porVencer = <Payment>[];
  final pagados = <Payment>[];

  for (final p in payments) {
    if (p.status == PaymentStatus.pending) {
      // REQ-VENC-11: dueAt-based vencido check with legacy null-dueAt fallback.
      final isVencido = p.dueAt != null
          ? p.dueAt!.toUtc().isBefore(now)
          : p.createdAt.toUtc().isBefore(periodStart);
      if (isVencido) {
        vencidos.add(p);
      } else {
        porVencer.add(p);
      }
    } else {
      // PaymentStatus.paid
      pagados.add(p);
    }
  }

  return PagosBuckets(
    vencidos: desc(vencidos),
    porVencer: desc(porVencer),
    pagados: desc(pagados),
    todos: desc(List.of(payments)),
  );
}

/// Agrupa todos los pagos del trainer en [PagosBuckets].
///
/// `autoDispose` — el listener Firestore se libera cuando la pantalla sale del
/// árbol.
///
/// hasValue-first (pulido-post-revision, mismo defecto que Chat, commit
/// cdd41949): [trainerPaymentsProvider] es un `StreamProvider` en vivo —
/// Riverpod 2.5+ preserva el valor previo dentro de un `AsyncError`
/// subsiguiente (`copyWithPrevious`/"seamless"), así que
/// `paymentsAsync.hasValue == true` Y `hasError == true` pueden darse a la
/// vez tras un error transitorio del stream. La composición anterior usaba
/// `.whenData()`, que internamente es `.map()` y despacha por el SUBTIPO
/// RUNTIME del AsyncValue (ignora `hasValue`): en ese estado compuesto caía
/// en la rama `error:`, que devuelve `hasValue: false` explícito — TIRABA los
/// buckets ya calculados aunque el stream de pagos siguiera teniendo el valor
/// cacheado. Se chequea `hasValue` explícitamente ANTES de mirar el error
/// para que un error transitorio nunca tape los buckets ya cargados.
final pagosBucketsProvider =
    Provider.autoDispose<AsyncValue<PagosBuckets>>((ref) {
  final paymentsAsync = ref.watch(trainerPaymentsProvider);

  if (paymentsAsync.hasValue) {
    return AsyncValue.data(_computeBuckets(paymentsAsync.requireValue));
  }
  if (paymentsAsync.hasError) {
    return AsyncValue<PagosBuckets>.error(
      paymentsAsync.error!,
      paymentsAsync.stackTrace ?? StackTrace.current,
    );
  }
  return const AsyncValue.loading();
});
