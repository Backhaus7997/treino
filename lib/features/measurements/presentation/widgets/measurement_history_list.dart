import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/date_labels.dart';
import '../../../../core/utils/kg_format.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../application/measurement_providers.dart';
import '../../domain/measurement.dart';

/// Cantidad de filas visibles antes del toggle "Ver todas". Mantiene liviano
/// el build dentro de pantallas que ya scrollean (la lista vive dentro de un
/// ListView/Column padre, no puede ser un builder perezoso propio).
const int _kCollapsedCount = 5;

String _formatRowDate(DateTime dt, String localeName) {
  // recordedAt es un instante real (UTC) — localizar antes de formatear o la
  // fecha corre +3h y salta de día cerca de medianoche (#392).
  final local = dt.toLocal();
  return '${local.day} ${monthAbbrev(local, localeName)} ${local.year}';
}

/// Historial de mediciones con acciones EDITAR/BORRAR por fila (#439).
///
/// Compartido por las dos superficies mobile que listan mediciones: la
/// sección ANTROPOMETRÍA del detalle de alumno (óptica del PF) y la pantalla
/// MEDIDAS del propio atleta (Insights → Mediciones).
///
/// Las acciones sólo se ofrecen cuando `measurement.recordedBy ==
/// [currentUid]`: el MISMO pin que exigen las rules de `measurements` para
/// update/delete (sólo el autor toca su doc). Una fila ajena — un self-log
/// visto por el PF, o una carga del PF vista por el atleta — muestra
/// [readOnlyLabel] en su lugar, explicando por qué no hay acciones.
///
/// El borrado confirma con AlertDialog (patrón `_onDeletePlan` de
/// athlete_detail_screen) y llama al repo directamente; los streams de
/// `snapshots()` refrescan la lista solos, sin invalidaciones manuales.
class MeasurementHistoryList extends ConsumerStatefulWidget {
  const MeasurementHistoryList({
    super.key,
    required this.measurements,
    required this.currentUid,
    required this.readOnlyLabel,
    required this.onEdit,
  });

  /// Mediciones en cualquier orden; se renderizan DESC (más reciente primero)
  /// porque el caso de uso dominante es corregir lo último cargado.
  final List<Measurement> measurements;

  /// Uid autenticado — gate de autoría para editar/borrar.
  final String currentUid;

  /// Etiqueta para filas NO editables (autor ≠ [currentUid]).
  final String readOnlyLabel;

  /// Abre el formulario de edición pre-poblado. La navegación difiere por
  /// superficie (modo trainer vs self-log), por eso la decide el caller.
  final ValueChanged<Measurement> onEdit;

  @override
  ConsumerState<MeasurementHistoryList> createState() =>
      _MeasurementHistoryListState();
}

class _MeasurementHistoryListState
    extends ConsumerState<MeasurementHistoryList> {
  bool _showAll = false;

  Future<void> _confirmDelete(Measurement m) async {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final dateLabel = _formatRowDate(m.recordedAt, l10n.localeName);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.bgCard,
        title: Text(
          l10n.measurementDeleteConfirmTitle,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
        content: Text(
          l10n.measurementDeleteConfirmBody(dateLabel),
          style: GoogleFonts.barlow(fontSize: 13, color: palette.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              l10n.commonCancel,
              style: GoogleFonts.barlowCondensed(color: palette.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              l10n.measurementDeleteConfirmAction,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                color: palette.danger,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref.read(measurementRepositoryProvider).delete(m.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.measurementDeleteSuccess)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.measurementDeleteError)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Los callers actuales gatean la lista vacía, pero un widget "compartido"
    // no puede depender de eso: sin filas no hay card que dibujar.
    if (widget.measurements.isEmpty) return const SizedBox.shrink();

    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    final sorted = [...widget.measurements]
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    final visible = _showAll ? sorted : sorted.take(_kCollapsedCount).toList();
    final hiddenCount = sorted.length - visible.length;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) Divider(color: palette.border, height: 1, thickness: 1),
            _HistoryRow(
              measurement: visible[i],
              editable: visible[i].recordedBy == widget.currentUid,
              readOnlyLabel: widget.readOnlyLabel,
              onEdit: () => widget.onEdit(visible[i]),
              onDelete: () => _confirmDelete(visible[i]),
            ),
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
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.accent,
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
    required this.measurement,
    required this.editable,
    required this.readOnlyLabel,
    required this.onEdit,
    required this.onDelete,
  });

  final Measurement measurement;
  final bool editable;
  final String readOnlyLabel;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  /// Summary: las mismas 4 métricas clave que la summary card del trainer
  /// (peso, % grasa, masa muscular, cintura). Sin ninguna de ellas cae a las
  /// notas; "Sin datos de composición" queda sólo para registros que
  /// efectivamente no traen composición (p.ej. sólo circunferencias).
  String _summary() {
    final m = measurement;
    final parts = <String>[
      if (m.weightKg != null) '${formatWeightKg(m.weightKg)} kg',
      if (m.fatPercentage != null)
        '${formatWeightKg(m.fatPercentage)}% grasa', // i18n: Fase W2
      if (m.muscleMassKg != null)
        'masa ${formatWeightKg(m.muscleMassKg)} kg', // i18n: Fase W2
      if (m.waistCm != null)
        'cintura ${formatWeightKg(m.waistCm)} cm', // i18n: Fase W2
    ];
    if (parts.isEmpty) {
      final notes = m.notes;
      return (notes != null && notes.isNotEmpty)
          ? notes
          : 'Sin datos de composición'; // i18n: Fase W2
    }
    return parts.join(' · ');
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
                  _formatRowDate(measurement.recordedAt, l10n.localeName),
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.4,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _summary(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.barlow(
                    fontSize: 12,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (editable) ...[
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: l10n.measurementHistoryEditTooltip,
              onPressed: onEdit,
              icon: Icon(TreinoIcon.edit, size: 18, color: palette.textMuted),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: l10n.measurementHistoryDeleteTooltip,
              onPressed: onDelete,
              icon: Icon(TreinoIcon.trash, size: 18, color: palette.danger),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                readOnlyLabel,
                style: GoogleFonts.barlow(
                  fontSize: 11,
                  color: palette.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
