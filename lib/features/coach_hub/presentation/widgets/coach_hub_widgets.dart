/// Barrel del kit de componentes Coach Hub Web — Fase 1.
///
/// Punto único de importación para los 7 componentes del kit + el resolver
/// de interacción compartido (`TreinoInteractiveState`, ADR-SH-002). Preferir
/// este barrel en vez de importar cada archivo individual del kit.
///
/// Galería de desarrollo: ver `dev_gallery.dart` en este mismo directorio
/// para una vista que muestra los 7 componentes en todos sus estados
/// (normal/hover/selected/loading/disabled, dark+light).
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
