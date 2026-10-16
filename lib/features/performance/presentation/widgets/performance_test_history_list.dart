import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/date_labels.dart';
import '../../../../core/utils/kg_format.dart';
import '../../../../core/widgets/treino_confirm_dialog.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../application/performance_test_providers.dart';
import '../../domain/performance_test.dart';

/// Filas visibles antes del toggle "Ver todas" — mismo criterio que el
/// historial de mediciones: la lista vive dentro de una pantalla que ya
/// scrollea y no puede ser un builder perezoso propio.
const int _kCollapsedCount = 5;

/// Alto de la lista expandida: unas seis filas. Acotado para que el
/// `ListView.builder` pueda ser perezoso dentro de la pantalla que scrollea.
const double _kExpandedHeight = 360;

String _formatRowDate(DateTime dt, String localeName) {
  // recordedAt es un instante real (UTC): localizar antes de formatear o la
  // fecha corre +3h y salta de día cerca de medianoche (#392).
  final local = dt.toLocal();
  return '${local.day} ${monthAbbrev(local, localeName)} ${local.year}';
}

/// Historial de evaluaciones de rendimiento con EDITAR/BORRAR por fila (#1485).
///
/// Sin esto, un typo (el CMJ de 999 cm del QA) quedaba para siempre en el
/// progreso del alumno: el repo ya tenía `update`/`delete`, faltaba la UI.
/// Copia el patrón de `MeasurementHistoryList` (#439).
///
/// Las acciones sólo aparecen cuando `test.recordedBy == [currentUid]`: el
/// mismo pin que exigen las reglas de `performance_tests` para update/delete.
/// Una fila de otro PF muestra la etiqueta de sólo lectura.
///
/// El borrado confirma con [showTreinoConfirmDialog] y llama al repo; el stream de
/// `snapshots()` refresca la lista solo.
class PerformanceTestHistoryList extends ConsumerStatefulWidget {
  const PerformanceTestHistoryList({
    super.key,
    required this.tests,
    required this.currentUid,
    required this.onEdit,
  });

  /// Evaluaciones en cualquier orden; se muestran DESC porque lo que se
  /// corrige casi siempre es lo último cargado.
  final List<PerformanceTest> tests;

  /// Uid autenticado: gate de autoría para editar/borrar.
  final String currentUid;

  /// Abre el form de edición pre-cargado; la navegación la decide el caller.
  final ValueChanged<PerformanceTest> onEdit;

  @override
  ConsumerState<PerformanceTestHistoryList> createState() =>
      _PerformanceTestHistoryListState();
}

class _PerformanceTestHistoryListState
    extends ConsumerState<PerformanceTestHistoryList> {
  bool _showAll = false;

  Future<void> _confirmDelete(PerformanceTest t) async {
    final l10n = AppL10n.of(context);
    final dateLabel = _formatRowDate(t.recordedAt, l10n.localeName);
    // La confirmación única de mobile (#1496): este historial nació antes
    // y traía su propio AlertDialog.
    final confirmed = await showTreinoConfirmDialog(
      context,
      title: l10n.performanceDeleteConfirmTitle,
      body: l10n.performanceDeleteConfirmBody(dateLabel),
      confirmLabel: l10n.measurementDeleteConfirmAction,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(performanceTestRepositoryProvider).delete(t.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.performanceDeleteSuccess)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.performanceDeleteError)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tests.isEmpty) return const SizedBox.shrink();

    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    final sorted = [...widget.tests]
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    final visible = _showAll ? sorted : sorted.take(_kCollapsedCount).toList();
    final hiddenCount = sorted.length - visible.length;
    Widget row(PerformanceTest t) => _HistoryRow(
          test: t,
          editable: t.recordedBy == widget.currentUid,
          onEdit: () => widget.onEdit(t),
          onDelete: () => _confirmDelete(t),
        );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_showAll)
            // Expandida, la lista puede ser de años: `ListView.builder` con
            // alto acotado construye sólo las filas visibles (AGENTS §6). Va
            // adentro de una pantalla que ya scrollea, por eso el alto fijo.
            SizedBox(
              height: _kExpandedHeight,
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: sorted.length,
                separatorBuilder: (_, __) =>
                    Divider(color: palette.border, height: 1, thickness: 1),
                itemBuilder: (_, i) => row(sorted[i]),
              ),
            )
          else
            for (var i = 0; i < visible.length; i++) ...[
              if (i > 0)
                Divider(color: palette.border, height: 1, thickness: 1),
              row(visible[i]),
            ],
          if (hiddenCount > 0 || _showAll)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: TextButton(
                onPressed: () => setState(() => _showAll = !_showAll),
                child: Text(
                  _showAll
                      ? l10n.measurementHistoryShowLess
                      : l10n.measurementHistoryShowAll(sorted.length),
                  style: GoogleFonts.barlow(
                    fontSize: AppTextSize.bodyDense,
                    fontWeight: FontWeight.w600,
                    color: palette.accentText,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.test,
    required this.editable,
    required this.onEdit,
    required this.onDelete,
  });

  final PerformanceTest test;
  final bool editable;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// Las mismas cuatro métricas clave que la card de resumen de RENDIMIENTO.
  /// Sin ninguna cae a las notas, y si tampoco hay notas, a cuántas métricas
  /// trae — una evaluación siempre tiene al menos una.
  String _summary(String localeName) {
    // Con el locale: «42,5 cm», no «42.5 cm» (#1481).
    String n(double? v) => formatNumberDisplay(v!, localeName, maxDecimals: 2);
    final t = test;
    final parts = <String>[
      if (t.cmjCm != null) 'CMJ ${n(t.cmjCm)} cm',
      if (t.squat1rmKg != null)
        'Sentadilla ${n(t.squat1rmKg)} kg', // i18n: Fase W2
      if (t.sprint20mS != null) '20m ${n(t.sprint20mS)} s',
      if (t.vo2maxMlKgMin != null) 'VO2máx ${n(t.vo2maxMlKgMin)}',
    ];
    if (parts.isNotEmpty) return parts.join(' · ');
    final notes = t.notes;
    if (notes != null && notes.isNotEmpty) return notes;
    return 'Otras métricas'; // i18n: Fase W2
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatRowDate(test.recordedAt, l10n.localeName),
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: AppTextSize.bodyDense,
                    letterSpacing: 0.4,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _summary(l10n.localeName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.barlow(
                    fontSize: AppTextSize.caption,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (editable) ...[
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: l10n.performanceHistoryEditTooltip,
              onPressed: onEdit,
              icon: Icon(TreinoIcon.edit, size: 18, color: palette.textMuted),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: l10n.performanceHistoryDeleteTooltip,
              onPressed: onDelete,
              icon: Icon(TreinoIcon.trash, size: 18, color: palette.dangerText),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                l10n.performanceHistoryOtherTrainerTag,
                style: GoogleFonts.barlow(
                  fontSize: AppTextSize.caption,
                  color: palette.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
