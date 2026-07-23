import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_shimmer.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/payment_format.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/measurements/application/measurement_providers.dart';
import 'package:treino/features/measurements/domain/measurement.dart';

/// Lista de mediciones antropométricas del tab Mediciones — Fase 3 WU-06a.
///
/// Extraído de `_AntropoList` (`alumno_detail_screen.dart`, ADR-A3-04).
/// `TreinoStateSwitcher` cross-fade entre loading (shimmer) / error / vacío
/// (`TreinoEmptyState`) / data (`TreinoListRow` expandible por fila).
class MedicionList extends ConsumerWidget {
  const MedicionList({
    super.key,
    required this.athleteId,
    required this.palette,
    required this.onDelete,
    required this.onEdit,
  });

  final String athleteId;
  final AppPalette palette;
  final Future<void> Function(Measurement) onDelete;
  final Future<void> Function(Measurement) onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final measAsync = ref.watch(measurementsForAthleteProvider(athleteId));

    return TreinoStateSwitcher(
      childKey: ValueKey('mediciones_list_${_stateKeyOf(measAsync)}'),
      child: measAsync.when(
        loading: () => const _MedicionListSkeleton(),
        error: (_, __) => Center(
          child: Text(
            'No pudimos cargar las mediciones.', // i18n: Fase W2
            style: TextStyle(color: palette.textMuted, fontSize: 14),
          ),
        ),
        data: (all) {
          // Provider ordena ASC — queremos DESC para "más nuevas arriba".
          final ms = all.reversed.toList();
          if (ms.isEmpty) {
            return const TreinoEmptyState(
              icon: TreinoIcon.ruler,
              title:
                  'Este alumno todavía no tiene mediciones cargadas.', // i18n: Fase W2
            );
          }
          return ListView.separated(
            itemCount: ms.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: palette.border),
            itemBuilder: (_, i) => MedicionRow(
              measurement: ms[i],
              palette: palette,
              onDelete: () => onDelete(ms[i]),
              onEdit: () => onEdit(ms[i]),
            ),
          );
        },
      ),
    );
  }
}

/// Copia local de `_stateKeyOf` (`alumnos_screen.dart`) — mismo criterio de
/// key por estado para el `TreinoStateSwitcher`.
String _stateKeyOf(AsyncValue<Object?> value) {
  if (value.hasError) return 'error';
  if (value.isLoading && !value.hasValue) return 'loading';
  return 'data';
}

/// Skeleton de carga — mismo patrón que `DatosPersonalesCard._skeleton()`
/// (`datos_personales_card.dart`).
class _MedicionListSkeleton extends StatelessWidget {
  const _MedicionListSkeleton();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return TreinoShimmer(
      child: Column(
        key: const Key('mediciones_list_skeleton'),
        children: [
          for (var i = 0; i < 3; i++) ...[
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            if (i < 2) const SizedBox(height: AppSpacing.s8),
          ],
        ],
      ),
    );
  }
}

/// Row de una medición individual — tap expande el detalle con todos los
/// campos cargados (los null se omiten). `TreinoListRow` como base visual
/// del kit v2, con el chevron de expandir en `leading` y editar/eliminar en
/// `trailing`.
class MedicionRow extends StatefulWidget {
  const MedicionRow({
    super.key,
    required this.measurement,
    required this.palette,
    required this.onDelete,
    required this.onEdit,
  });

  final Measurement measurement;
  final AppPalette palette;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  State<MedicionRow> createState() => _MedicionRowState();
}

class _MedicionRowState extends State<MedicionRow> {
  bool _expanded = false;

  /// Summary line: los 3 campos que suele pedir el PF: peso, % grasa,
  /// cintura. Si alguno es null, se omite del summary.
  String _summary() {
    final m = widget.measurement;
    final parts = <String>[];
    if (m.weightKg != null) parts.add('${m.weightKg} kg');
    if (m.fatPercentage != null) parts.add('${m.fatPercentage}% grasa');
    if (m.waistCm != null) parts.add('cintura ${m.waistCm} cm');
    if (parts.isEmpty) return 'Sin datos de composición'; // i18n: Fase W2
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.measurement;
    final palette = widget.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TreinoListRow(
          leading: Icon(
            _expanded ? TreinoIcon.chevronDown : TreinoIcon.chevronRight,
            size: 18,
            color: palette.textMuted,
          ),
          title: fmtDate(m.recordedAt),
          subtitle: _summary(),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Editar', // i18n: Fase W2
                onPressed: widget.onEdit,
                icon: Icon(TreinoIcon.edit, size: 18, color: palette.textMuted),
              ),
              IconButton(
                tooltip: 'Eliminar', // i18n: Fase W2
                onPressed: widget.onDelete,
                icon: Icon(TreinoIcon.trash, size: 18, color: palette.danger),
              ),
            ],
          ),
          onTap: () => setState(() => _expanded = !_expanded),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s20 + AppSpacing.s8,
              0,
              AppSpacing.s8,
              AppSpacing.s12,
            ),
            child: MedicionDetail(measurement: m, palette: palette),
          ),
      ],
    );
  }
}

/// Detalle expandido de una medición. Muestra solo los campos con valor,
/// en 2 columnas para aprovechar el ancho del web.
class MedicionDetail extends StatelessWidget {
  const MedicionDetail({
    super.key,
    required this.measurement,
    required this.palette,
  });

  final Measurement measurement;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final m = measurement;
    final entries = <(String, String)>[
      // Composición
      if (m.weightKg != null) ('Peso', '${m.weightKg} kg'),
      if (m.fatPercentage != null) ('% grasa', '${m.fatPercentage}%'),
      if (m.muscleMassKg != null) ('Masa muscular', '${m.muscleMassKg} kg'),
      // Trunk
      if (m.shouldersCm != null) ('Hombros', '${m.shouldersCm} cm'),
      if (m.chestCm != null) ('Pecho', '${m.chestCm} cm'),
      if (m.waistCm != null) ('Cintura', '${m.waistCm} cm'),
      if (m.hipsCm != null) ('Cadera', '${m.hipsCm} cm'),
      if (m.glutesCm != null) ('Glúteos', '${m.glutesCm} cm'),
      // Upper
      if (m.bicepsLCm != null) ('Bíceps izq.', '${m.bicepsLCm} cm'),
      if (m.bicepsRCm != null) ('Bíceps der.', '${m.bicepsRCm} cm'),
      if (m.bicepsFlexedLCm != null)
        ('Bíceps flex. izq.', '${m.bicepsFlexedLCm} cm'),
      if (m.bicepsFlexedRCm != null)
        ('Bíceps flex. der.', '${m.bicepsFlexedRCm} cm'),
      if (m.forearmLCm != null) ('Antebrazo izq.', '${m.forearmLCm} cm'),
      if (m.forearmRCm != null) ('Antebrazo der.', '${m.forearmRCm} cm'),
      // Lower
      if (m.upperThighLCm != null) ('Muslo sup. izq.', '${m.upperThighLCm} cm'),
      if (m.upperThighRCm != null) ('Muslo sup. der.', '${m.upperThighRCm} cm'),
      if (m.midThighLCm != null) ('Muslo med. izq.', '${m.midThighLCm} cm'),
      if (m.midThighRCm != null) ('Muslo med. der.', '${m.midThighRCm} cm'),
      if (m.calfLCm != null) ('Gemelo izq.', '${m.calfLCm} cm'),
      if (m.calfRCm != null) ('Gemelo der.', '${m.calfRCm} cm'),
    ];

    if (entries.isEmpty && (m.notes ?? '').isEmpty) {
      return Text(
        'Esta medición no tiene valores cargados.', // i18n: Fase W2
        style: TextStyle(color: palette.textMuted, fontSize: 13),
      );
    }

    // Split en 2 columnas para aprovechar ancho del web.
    final half = (entries.length / 2).ceil();
    final left = entries.take(half).toList();
    final right = entries.skip(half).toList();

    Widget colFor(List<(String, String)> items) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (label, value) in items)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s8 - 2),
                child: Row(
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(
                        label,
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      value,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: colFor(left)),
            const SizedBox(width: AppSpacing.s20 + AppSpacing.hairline),
            Expanded(child: colFor(right)),
          ],
        ),
        if ((m.notes ?? '').isNotEmpty) ...[
          const SizedBox(height: AppSpacing.s12),
          Text(
            'Nota', // i18n: Fase W2
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.hairline),
          Text(
            m.notes!,
            style: TextStyle(color: palette.textPrimary, fontSize: 13),
          ),
        ],
      ],
    );
  }
}
