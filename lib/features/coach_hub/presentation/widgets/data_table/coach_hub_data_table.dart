import 'package:flutter/material.dart';

import '../../../../../app/theme/app_motion.dart';
import '../../../../../app/theme/app_palette.dart';
import '../../../../../app/theme/tokens/components/treino_focus_tokens.dart';
import '../../../../../app/theme/tokens/components/treino_table_tokens.dart';
import '../../../../../app/theme/tokens/primitives.dart';
import '../../../../../core/widgets/motion/treino_shimmer.dart';
import '../../../../../core/widgets/treino_icon.dart';
import '../empty_state/empty_state.dart';
import '../treino_interactive_state.dart';

/// Modelo de columna para [CoachHubDataTable].
@immutable
class CoachHubColumn {
  const CoachHubColumn({
    required this.key,
    required this.label,
    this.sortable = false,
    this.flex = 1,
  });

  /// Clave única que identifica la columna (usada en [CoachHubRow.cells]).
  final String key;

  /// Texto del encabezado.
  final String label;

  /// `true` si la columna acepta ordenamiento (muestra indicador + tap).
  final bool sortable;

  /// Factor de flex para el ancho relativo de la columna.
  final int flex;
}

/// Modelo de fila para [CoachHubDataTable].
@immutable
class CoachHubRow {
  const CoachHubRow({
    required this.id,
    required this.cells,
  });

  /// Identificador único de la fila (usado en [CoachHubDataTable.onRowTap]).
  final String id;

  /// Mapa de valores por clave de columna.
  final Map<String, String> cells;
}

/// Tabla de datos del kit Coach Hub Web — Fase 1.
///
/// Estados soportados:
/// - Normal: filas con hover alternado (TreinoTableTokens).
/// - Fila con `onRowTap`: focusable, activable por teclado (Enter/Space) y
///   expone Semantics(button: true) — vía TreinoInteractiveState
///   (fuente única de verdad, ADR-SH-002).
/// - Loading: TreinoShimmer skeleton rows.
/// - Vacío: EmptyState slot con mensaje configurable.
/// - Error: mensaje de error + botón retry.
/// - Columnas ordenables: indicador sort animado (AppMotionTokens.cardStateChange).
/// - SIN paginación en Fase 1 (diferida a Fase 3).
///
/// Tokens: [TreinoTableTokens.of(context)] — nunca hex inline.
///
/// Uso:
/// ```dart
/// CoachHubDataTable(
///   columns: [
///     CoachHubColumn(key: 'name', label: 'Nombre', sortable: true),
///   ],
///   rows: alumnos.map((a) => CoachHubRow(id: a.id, cells: {'name': a.name})).toList(),
///   onSort: (key, asc) => setState(() { ... }),
///   onRowTap: (id) => nav.push('/alumno/$id'),
/// )
/// ```
class CoachHubDataTable extends StatelessWidget {
  const CoachHubDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.loading = false,
    this.emptyMessage,
    this.emptyIcon = TreinoIcon.emptyState,
    this.emptyDescription,
    this.emptyCtaLabel,
    this.onEmptyCtaTap,
    this.errorMessage,
    this.onRetry,
    this.sortColumnKey,
    this.sortAscending = true,
    this.onSort,
    this.onRowTap,
  });

  /// Definición de columnas (orden, label, sortable).
  final List<CoachHubColumn> columns;

  /// Filas de datos. Vacío + no loading + no error = estado vacío.
  final List<CoachHubRow> rows;

  /// `true` mientras se cargan los datos.
  final bool loading;

  /// Mensaje a mostrar cuando [rows] está vacío y no hay error ni loading.
  /// Se pasa como `title` a [TreinoEmptyState] (fuente única de verdad,
  /// Finding C3).
  final String? emptyMessage;

  /// Ícono del estado vacío. Pasa a [TreinoEmptyState.icon].
  final IconData emptyIcon;

  /// Descripción opcional debajo del título del estado vacío. Pasa a
  /// [TreinoEmptyState.description].
  final String? emptyDescription;

  /// Texto del CTA opcional del estado vacío. Pasa a
  /// [TreinoEmptyState.ctaLabel].
  final String? emptyCtaLabel;

  /// Callback del CTA del estado vacío. Ignorado si [emptyCtaLabel] es null.
  final VoidCallback? onEmptyCtaTap;

  /// Mensaje de error. Si no-null, muestra el estado error.
  final String? errorMessage;

  /// Callback para el botón retry del estado error.
  final VoidCallback? onRetry;

  /// Clave de la columna actualmente ordenada. Null = sin orden activo.
  final String? sortColumnKey;

  /// Dirección del ordenamiento activo.
  final bool sortAscending;

  /// Llamado al tocar un encabezado sortable: (columnKey, ascending).
  final void Function(String key, bool ascending)? onSort;

  /// Llamado al tocar una fila: (rowId).
  final void Function(String id)? onRowTap;

  @override
  Widget build(BuildContext context) {
    final tokens = TreinoTableTokens.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(TreinoTableTokens.borderRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: tokens.borderColor),
          borderRadius: BorderRadius.circular(TreinoTableTokens.borderRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _HeaderRow(
              columns: columns,
              tokens: tokens,
              sortColumnKey: sortColumnKey,
              sortAscending: sortAscending,
              onSort: onSort,
            ),
            Divider(height: 1, thickness: 1, color: tokens.borderColor),
            if (loading)
              _SkeletonRows(tokens: tokens)
            else if (errorMessage != null)
              _ErrorState(message: errorMessage!, onRetry: onRetry)
            else if (rows.isEmpty)
              TreinoEmptyState(
                icon: emptyIcon,
                title: emptyMessage ?? 'Sin datos',
                description: emptyDescription,
                ctaLabel: emptyCtaLabel,
                onCtaTap: onEmptyCtaTap,
              )
            else
              _DataRows(
                columns: columns,
                rows: rows,
                tokens: tokens,
                onRowTap: onRowTap,
              ),
          ],
        ),
      ),
    );
  }
}

/// Fila de encabezado con soporte de ordenamiento.
class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.columns,
    required this.tokens,
    required this.sortColumnKey,
    required this.sortAscending,
    required this.onSort,
  });

  final List<CoachHubColumn> columns;
  final TreinoTableTokens tokens;
  final String? sortColumnKey;
  final bool sortAscending;
  final void Function(String key, bool ascending)? onSort;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: tokens.headerBackground,
      height: TreinoTableTokens.rowHeight,
      child: Row(
        children: [
          for (final col in columns)
            Expanded(
              flex: col.flex,
              child: _HeaderCell(
                column: col,
                tokens: tokens,
                isSorted: sortColumnKey == col.key,
                sortAscending: sortAscending,
                onSort: col.sortable && onSort != null
                    ? () => onSort!(
                          col.key,
                          sortColumnKey == col.key ? !sortAscending : true,
                        )
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

/// Celda de encabezado individual.
class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.column,
    required this.tokens,
    required this.isSorted,
    required this.sortAscending,
    this.onSort,
  });

  final CoachHubColumn column;
  final TreinoTableTokens tokens;
  final bool isSorted;
  final bool sortAscending;
  final VoidCallback? onSort;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TreinoTableTokens.cellPaddingH,
        vertical: TreinoTableTokens.cellPaddingV,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            column.label,
            style: TextStyle(
              fontFamily: 'Barlow',
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: tokens.headerTextColor,
            ),
          ),
          if (column.sortable && isSorted) ...[
            const SizedBox(width: 4),
            AnimatedRotation(
              key: Key('sort_indicator_${column.key}'),
              turns: sortAscending ? 0 : 0.5,
              duration: AppMotion.resolve(context, AppMotion.fast),
              child: Icon(
                TreinoIcon.sortAscending,
                size: 12,
                color: tokens.sortIndicatorColor,
              ),
            ),
          ],
          if (column.sortable && !isSorted) ...[
            const SizedBox(width: 4),
            Icon(
              TreinoIcon.sortable,
              size: 12,
              color: tokens.headerTextColor.withValues(alpha: 0.5),
            ),
          ],
        ],
      ),
    );

    if (onSort == null) return content;

    return InkWell(
      onTap: onSort,
      child: content,
    );
  }
}

/// Filas de datos con hover.
class _DataRows extends StatelessWidget {
  const _DataRows({
    required this.columns,
    required this.rows,
    required this.tokens,
    this.onRowTap,
  });

  final List<CoachHubColumn> columns;
  final List<CoachHubRow> rows;
  final TreinoTableTokens tokens;
  final void Function(String id)? onRowTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            Divider(height: 1, thickness: 1, color: tokens.borderColor),
          _DataRow(
            row: rows[i],
            columns: columns,
            tokens: tokens,
            isAlt: i.isOdd,
            onTap: onRowTap != null ? () => onRowTap!(rows[i].id) : null,
          ),
        ],
      ],
    );
  }
}

/// Fila de datos individual — estado de interacción vía
/// [TreinoInteractiveState] (fuente única de verdad, ADR-SH-002): cuando
/// `onTap` existe, la fila es focusable, activable por teclado (Enter/Space)
/// y expone Semantics(button: true). Sin `onTap` → fila estática, sin hover.
class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.row,
    required this.columns,
    required this.tokens,
    required this.isAlt,
    this.onTap,
  });

  final CoachHubRow row;
  final List<CoachHubColumn> columns;
  final TreinoTableTokens tokens;
  final bool isAlt;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final focusTokens = TreinoFocusTokens.of(context);

    return TreinoInteractiveState(
      onTap: onTap,
      builder: (ctx, states) {
        Color bg;
        if (states.hovered) {
          bg = tokens.rowHoverBackground;
        } else if (isAlt) {
          bg = tokens.rowAltBackground;
        } else {
          bg = tokens.rowBackground;
        }

        return AnimatedContainer(
          key: Key('data_table_row_${row.id}'),
          duration: AppMotion.resolve(ctx, AppMotion.fast),
          curve: AppMotion.standard,
          decoration: BoxDecoration(
            color: bg,
            border: states.focused ? Border.all(color: focusTokens.ring) : null,
          ),
          height: TreinoTableTokens.rowHeight,
          child: Row(
            children: [
              for (final col in columns)
                Expanded(
                  flex: col.flex,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: TreinoTableTokens.cellPaddingH,
                      vertical: TreinoTableTokens.cellPaddingV,
                    ),
                    child: Text(
                      row.cells[col.key] ?? '',
                      style: TextStyle(
                        fontFamily: 'Barlow',
                        fontWeight: FontWeight.w400,
                        fontSize: 14,
                        color: AppPalette.of(ctx).textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Skeleton de carga (shimmer rows).
class _SkeletonRows extends StatelessWidget {
  const _SkeletonRows({required this.tokens});

  final TreinoTableTokens tokens;

  static const _skeletonRowCount = 5;

  @override
  Widget build(BuildContext context) {
    return TreinoShimmer(
      child: Column(
        key: const Key('data_table_skeleton'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _skeletonRowCount; i++) ...[
            if (i > 0)
              Divider(height: 1, thickness: 1, color: tokens.borderColor),
            Container(
              height: TreinoTableTokens.rowHeight,
              color: i.isOdd ? tokens.rowAltBackground : tokens.rowBackground,
              padding: const EdgeInsets.symmetric(
                horizontal: TreinoTableTokens.cellPaddingH,
                vertical: TreinoTableTokens.cellPaddingV,
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: tokens.borderColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: tokens.borderColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Estado de error con retry.
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      key: const Key('data_table_error_content'),
      padding: const EdgeInsets.all(AppSpacing.s20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(TreinoIcon.errorState, size: 32, color: palette.danger),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              fontFamily: 'Barlow',
              fontSize: 14,
              color: palette.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            TextButton(
              key: const Key('data_table_retry'),
              onPressed: onRetry,
              child: Text(
                'Reintentar',
                style: TextStyle(color: palette.accent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
