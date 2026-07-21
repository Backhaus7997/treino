/// Tabla de pagos para la vista web del Coach Hub (trainer-wide).
///
/// Fase 9 WU-06: migrada de un `Container` plano ad-hoc a
/// [CoachHubDataTable] del kit v2, con celdas ricas (avatar de iniciales +
/// badge de estado por color) y estados completos resueltos por el kit
/// (loading shimmer / error+retry / empty). El ORDEN de [payments] es
/// responsabilidad del caller (`PagosScreen`, que posee el estado de sort);
/// este widget solo renderiza la lista tal cual llega junto con el
/// indicador de columna ordenada.
///
/// ADR-F9-02: sin columna PLAN (no hay plan real) — la columna real es
/// CONCEPTO.
///
/// Fase 9 WU-07: columna ACCIONES (Recordar / Marcar pagado) — visible solo
/// cuando [showActions] es `true` (se oculta en el tab Pagados). Reusa la
/// lógica existente de `marcar_pagado_actions.dart` vía los callbacks
/// [onMarcarPagado]/[onRecordar] — este widget NO conoce Firestore/chat, solo
/// pinta los botones y delega.
///
/// Sección: coach_hub/pagos — contrato: sin Scaffold, sin HEX, es-AR + // i18n.
library;

import 'package:flutter/material.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';

import '../../../widgets/coach_hub_widgets.dart'
    show CoachHubColumn, CoachHubDataTable, CoachHubRow;
import 'pagos_estado.dart';
import 'payment_format.dart';

// ── PagosWebTable ─────────────────────────────────────────────────────────────

/// Tabla de pagos del Coach Hub web. Muestra una fila por [Payment] vía
/// [CoachHubDataTable].
///
/// [profiles] mapea `athleteId → UserPublicProfile`; si falta el perfil se
/// muestra el fallback `'Alumno'`.
///
/// REQ-PAGW-TABLE-001, REQ-PAGW-EMPTY-001.
class PagosWebTable extends StatelessWidget {
  const PagosWebTable({
    super.key,
    required this.payments,
    required this.profiles,
    required this.emptyMessage,
    this.loading = false,
    this.errorMessage,
    this.onRetry,
    this.sortColumnKey,
    this.sortAscending = true,
    this.onSort,
    this.showActions = true,
    this.onMarcarPagado,
    this.onRecordar,
  });

  /// Pagos a renderizar, ya ordenados por el caller según [sortColumnKey].
  final List<Payment> payments;

  /// athleteId → UserPublicProfile (o ausente si no se resolvió aún).
  final Map<String, UserPublicProfile> profiles;

  /// Texto descriptivo cuando [payments] está vacío (por-filtro, es-AR). // i18n
  final String emptyMessage;

  /// `true` mientras se cargan los pagos — muestra el skeleton del kit.
  final bool loading;

  /// Mensaje de error; si no-null, muestra el estado error del kit.
  final String? errorMessage;

  /// Callback del botón "Reintentar" del estado error.
  final VoidCallback? onRetry;

  /// Clave de la columna actualmente ordenada (owned por el caller).
  final String? sortColumnKey;

  /// Dirección del ordenamiento activo.
  final bool sortAscending;

  /// Llamado al tocar un encabezado ordenable: (columnKey, ascending).
  final void Function(String key, bool ascending)? onSort;

  /// `false` oculta la columna ACCIONES por completo (tab Pagados).
  final bool showActions;

  /// Callback de "Marcar pagado" para una fila; solo se ofrece si el pago
  /// está `pending` (ver [_AccionesCell]).
  final void Function(Payment)? onMarcarPagado;

  /// Callback de "Recordar" para una fila.
  final void Function(Payment)? onRecordar;

  // ── Helpers ─────────────────────────────────────────────────────────────────

  String _displayName(String athleteId) {
    final profile = profiles[athleteId];
    return profile?.displayName?.isNotEmpty == true
        ? profile!.displayName!
        : 'Alumno'; // i18n fallback
  }

  CoachHubRow _rowFor(AppPalette palette, Payment p) {
    final name = _displayName(p.athleteId);
    final (:estado, :label) = pagoEstadoOf(p, DateTime.now().toUtc());
    final vencimiento = fmtDayMonth(p.dueAt ?? p.createdAt);

    return CoachHubRow(
      id: p.id,
      cells: {
        'alumno': name,
        'concepto': p.concept,
        'monto': fmtArs(p.amountArs),
        'vencimiento': vencimiento,
        'estado': label,
      },
      cellWidgets: {
        'alumno': _AlumnoCell(name: name, palette: palette),
        'monto': _MontoCell(amountArs: p.amountArs, palette: palette),
        'estado': _EstadoBadge(estado: estado, label: label, palette: palette),
        if (showActions)
          'acciones': _AccionesCell(
            payment: p,
            palette: palette,
            onRecordar: onRecordar,
            onMarcarPagado: onMarcarPagado,
          ),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return CoachHubDataTable(
      columns: [
        const CoachHubColumn(
            key: 'alumno', label: 'ALUMNO', sortable: true, flex: 3), // i18n
        const CoachHubColumn(
            key: 'concepto', label: 'CONCEPTO', flex: 4), // i18n
        const CoachHubColumn(
            key: 'monto', label: 'MONTO', sortable: true, flex: 2), // i18n
        const CoachHubColumn(
            key: 'vencimiento',
            label: 'VENCIMIENTO',
            sortable: true,
            flex: 2), // i18n
        const CoachHubColumn(key: 'estado', label: 'ESTADO', flex: 2), // i18n
        if (showActions)
          const CoachHubColumn(
              key: 'acciones', label: 'ACCIONES', flex: 3), // i18n
      ],
      rows: [for (final p in payments) _rowFor(palette, p)],
      loading: loading,
      errorMessage: errorMessage,
      onRetry: onRetry,
      emptyMessage: emptyMessage,
      sortColumnKey: sortColumnKey,
      sortAscending: sortAscending,
      onSort: onSort,
    );
  }
}

// ── _AlumnoCell ──────────────────────────────────────────────────────────────

/// Avatar circular con iniciales del [name] (NUNCA foto inventada) + nombre.
class _AlumnoCell extends StatelessWidget {
  const _AlumnoCell({required this.name, required this.palette});

  final String name;
  final AppPalette palette;

  static String _initialsOf(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.accent.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Text(
            _initialsOf(name),
            style: TextStyle(
              fontFamily: AppFonts.barlow,
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: palette.accent,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.s12),
        Flexible(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.textPrimary, fontSize: 14),
          ),
        ),
      ],
    );
  }
}

// ── _MontoCell ───────────────────────────────────────────────────────────────

class _MontoCell extends StatelessWidget {
  const _MontoCell({required this.amountArs, required this.palette});

  final int amountArs;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Text(
        fmtArs(amountArs),
        style: TextStyle(color: palette.textPrimary, fontSize: 14),
      ),
    );
  }
}

// ── _EstadoBadge ─────────────────────────────────────────────────────────────

/// Pill con dot + label, color por estado desde la palette semántica
/// (vencido → danger, porVencer → accent, pagado → textMuted).
class _EstadoBadge extends StatelessWidget {
  const _EstadoBadge({
    required this.estado,
    required this.label,
    required this.palette,
  });

  final PagoEstado estado;
  final String label;
  final AppPalette palette;

  Color get _color => switch (estado) {
        PagoEstado.vencido => palette.danger,
        PagoEstado.porVencer => palette.accent,
        PagoEstado.pagado => palette.textMuted,
      };

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.hairline,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.hairline),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _AccionesCell ────────────────────────────────────────────────────────────

/// Botones de acción de la fila: Recordar (siempre, si hay callback) y
/// Marcar pagado (solo si el pago está `pending`, si hay callback).
///
/// Sin `onRowTap` en `CoachHubDataTable` (ADR-F9-03) — no hay pelea de gestos
/// entre el tap de fila y el tap de estos botones.
class _AccionesCell extends StatelessWidget {
  const _AccionesCell({
    required this.payment,
    required this.palette,
    required this.onRecordar,
    required this.onMarcarPagado,
  });

  final Payment payment;
  final AppPalette palette;
  final void Function(Payment)? onRecordar;
  final void Function(Payment)? onMarcarPagado;

  @override
  Widget build(BuildContext context) {
    final pending = payment.status == PaymentStatus.pending;

    // `Flexible` en cada botón (en vez de tamaño natural fijo) evita que el
    // Row overflowee si el ancho de la columna es angosto — el label se
    // elide con TextOverflow.ellipsis en ese caso extremo, sin romper el
    // layout de la fila (finders por texto siguen matcheando el `data`).
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: _AccionButton(
            key: Key('pagos_accion_recordar_${payment.id}'),
            icon: TreinoIcon.bell,
            label: 'Recordar', // i18n
            color: palette.textMuted,
            onTap: onRecordar == null ? null : () => onRecordar!(payment),
          ),
        ),
        if (pending) ...[
          const SizedBox(width: AppSpacing.hairline),
          Flexible(
            child: _AccionButton(
              key: Key('pagos_accion_marcar_pagado_${payment.id}'),
              icon: TreinoIcon.check,
              label: 'Marcar pagado', // i18n
              color: palette.accent,
              onTap: onMarcarPagado == null
                  ? null
                  : () => onMarcarPagado!(payment),
            ),
          ),
        ],
      ],
    );
  }
}

/// Botón compacto de acción de fila — `TextButton` con `tapTargetSize`
/// achicado para no romper el `rowHeight` fijo de `CoachHubDataTable`.
class _AccionButton extends StatelessWidget {
  const _AccionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.hairline),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12),
          const SizedBox(width: AppSpacing.hairline),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
