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
/// Filtro activo de la sección Pagos.
///
/// Arranca en `porVencer` por #605 ("Registrar pago vincula alumno + abre en
/// 'Por vencer'"): el PF entra a Pagos para ver qué está por cobrar, no para
/// mirar lo que ya se venció. Los chips reemplazaron a los tabs en la Fase 9,
/// pero el destino inicial sigue siendo el mismo.
final pagosFiltroProvider =
    StateProvider.autoDispose<PagosFiltro>((_) => PagosFiltro.porVencer);

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
