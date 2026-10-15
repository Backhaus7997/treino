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
import 'package:treino/core/utils/argentina_time.dart';
import 'package:treino/features/coach_hub/presentation/widgets/stale_async.dart';

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

PagosBuckets _computeBuckets(List<Payment> payments) {
  // Bucket de DIA en ART (#671): con UTC los pagos saltaban a "Vencidos"
  // 3h antes y volvian solos a medianoche.
  final now = argentinaNow();
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
/// Prioriza un valor previo sobre un error transitorio del stream. `whenData`
/// despacha por el subtipo de [AsyncValue] y perdería esos datos cacheados.
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

/// `true` cuando [trainerPaymentsProvider] ya había cargado pagos y DESPUÉS
/// falló (stream de Firestore cerrado por error, casi siempre permanente).
///
/// [pagosBucketsProvider] sigue sosteniendo los buckets ya calculados (nunca
/// emite el estado compuesto «valor + error», así que sus otros consumidores
/// no cambian), y este flag le deja a la UI avisar «Datos desactualizados ·
/// Reintentar». El reintento es `ref.invalidate(trainerPaymentsProvider)`.
final pagosBucketsStaleProvider = Provider.autoDispose<bool>(
  (ref) => ref.watch(trainerPaymentsProvider).isStale,
);
