/// Filtro seleccionado y conteo de badge para la sección Pagos del Coach Hub
/// web.
///
/// Sección: coach_hub/pagos — contrato: sin Scaffold, sin HEX, es-AR + // i18n.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pagos_buckets_provider.dart';

// ── Filtro ────────────────────────────────────────────────────────────────────

/// Filtro de la sección Pagos — colapsa los 4 buckets de [PagosBuckets] en
/// una selección exclusiva para la UI (chips + tabla).
enum PagosFiltro { vencidos, porVencer, pagados, todos }

/// Filtro seleccionado en la sección Pagos. Default: Vencidos — la sección
/// abre en triage, igual que `solicitudTabProvider` (Pendientes).
final pagosFiltroProvider =
    StateProvider.autoDispose<PagosFiltro>((_) => PagosFiltro.vencidos);

// ── Badge ─────────────────────────────────────────────────────────────────────

/// Conteo de pagos vencidos — badge del sidebar (patrón
/// `invitacionesPendingCountProvider`).
///
/// `null` mientras [pagosBucketsProvider] está en loading/error (el `_Badge`
/// del kit no renderiza nada si el count es `null`); en `data`, cuenta los
/// pagos del bucket Vencidos.
final pagosBadgeCountProvider = Provider.autoDispose<int?>((ref) {
  final buckets = ref.watch(pagosBucketsProvider).valueOrNull;
  if (buckets == null) return null;
  return buckets.vencidos.length;
});
