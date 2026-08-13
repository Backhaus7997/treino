/// Barrel del kit de componentes Coach Hub Web — Fase 1.
///
/// Punto único de importación para los 7 componentes del kit + el resolver
/// de interacción compartido (`TreinoInteractiveState`, ADR-SH-002). Preferir
/// este barrel en vez de importar cada archivo individual del kit.
///
/// Galería de desarrollo: sin app de preview separada por decisión de
/// ADR-SH-006 ("Sin app real de preview separada — anotaciones sobre
/// funciones top-level parameter-less"). Cada componente expone sus propios
/// `@Preview` co-ubicados en su archivo (ver `preview_wrapper.dart` para el
/// wrapper compartido dark + `MaterialApp`).
///
/// Componentes exportados:
/// - [CoachHubDataTable] (`data_table/`)
/// - [KpiCard] (`kpi_card/`)
/// - [TreinoFilterChips] (`filter_chips/`)
/// - [TreinoListRow] (`list_row/`)
/// - [TreinoSectionHeader] (`section_header/`)
/// - [TreinoEmptyState] (`empty_state/`)
/// - [TreinoDialog] / [showTreinoDialog] (`dialog/`)
/// - [TreinoInteractiveState] (resolver de interacción, fuente única de verdad)
library;

export 'data_table/coach_hub_data_table.dart';
export 'dialog/treino_dialog.dart';
export 'empty_state/empty_state.dart';
export 'filter_chips/filter_chips.dart';
export 'kpi_card/kpi_card.dart';
export 'list_row/list_row.dart';
export 'section_header/section_header.dart';
export 'treino_interactive_state.dart';
