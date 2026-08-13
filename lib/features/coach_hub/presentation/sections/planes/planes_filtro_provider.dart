/// Filtro de cadencia de la grilla de tarifas — sección Planes comerciales
/// del Coach Hub web (Fase 10, WU-04).
///
/// Sección: coach_hub/planes — contrato: sin Scaffold, sin HEX, es-AR +
/// // i18n.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../payments/domain/athlete_billing.dart';

// ── Filtro ────────────────────────────────────────────────────────────────────

/// Filtro de cadencia de la grilla de tarifas — colapsa las 4 cadencias de
/// [BillingCadence] + "Todas" en una selección exclusiva para la UI (chips +
/// grid).
enum PlanesFiltroCadencia { todas, mensual, semanal, porSesion, suelto }

/// [BillingCadence] equivalente a [filtro], o `null` para
/// [PlanesFiltroCadencia.todas] (sin filtro activo — todos los grupos
/// matchean).
BillingCadence? cadenceOfFiltro(PlanesFiltroCadencia filtro) =>
    switch (filtro) {
      PlanesFiltroCadencia.todas => null,
      PlanesFiltroCadencia.mensual => BillingCadence.mensual,
      PlanesFiltroCadencia.semanal => BillingCadence.semanal,
      PlanesFiltroCadencia.porSesion => BillingCadence.porSesion,
      PlanesFiltroCadencia.suelto => BillingCadence.suelto,
    };

/// Filtro de cadencia seleccionado en la grilla de tarifas. Default: todas —
/// a diferencia de Pagos (que abre en triage de vencidos), acá no hay un
/// grupo "urgente": la sección abre mostrando el panorama completo.
final planesFiltroProvider = StateProvider.autoDispose<PlanesFiltroCadencia>(
  (_) => PlanesFiltroCadencia.todas,
);
