import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_shimmer.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/payment_format.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/performance/application/performance_test_providers.dart';
import 'package:treino/features/performance/domain/performance_test.dart';

/// Lista de pruebas de rendimiento del tab Mediciones — Fase 3 WU-06a.
///
/// Extraído de `_RendimientoList` (`alumno_detail_screen.dart`, ADR-A3-04).
/// Mismo patrón que `MedicionList` (`medicion_list.dart`) — hermanas por
/// diseño, no se unificaron en un solo widget genérico porque `Measurement`
/// y `PerformanceTest` tienen forma de dato completamente distinta.
class RendimientoList extends ConsumerWidget {
  const RendimientoList({
    super.key,
    required this.athleteId,
    required this.palette,
    required this.onDelete,
    required this.onEdit,
  });

  final String athleteId;
  final AppPalette palette;
  final Future<void> Function(PerformanceTest) onDelete;
  final Future<void> Function(PerformanceTest) onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final testsAsync = ref.watch(performanceTestsForAthleteProvider(athleteId));

    return TreinoStateSwitcher(
      childKey: ValueKey('rendimiento_list_${_stateKeyOf(testsAsync)}'),
      child: testsAsync.when(
        loading: () => const _RendimientoListSkeleton(),
        error: (_, __) => Center(
          child: Text(
            'No pudimos cargar las pruebas.', // i18n: Fase W2
            style: TextStyle(color: palette.textMuted, fontSize: 14),
          ),
        ),
        data: (all) {
          final tests = all.reversed.toList();
          if (tests.isEmpty) {
            return const TreinoEmptyState(
              icon: TreinoIcon.dumbbell,
              title: 'Este alumno todavía no tiene pruebas de rendimiento '
                  'cargadas.', // i18n: Fase W2
            );
          }
          return ListView.separated(
            itemCount: tests.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: palette.border),
            itemBuilder: (_, i) => RendimientoRow(
              test: tests[i],
              palette: palette,
              onDelete: () => onDelete(tests[i]),
              onEdit: () => onEdit(tests[i]),
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

class _RendimientoListSkeleton extends StatelessWidget {
  const _RendimientoListSkeleton();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return TreinoShimmer(
      child: Column(
        key: const Key('rendimiento_list_skeleton'),
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

/// Row de una prueba de rendimiento individual. `TreinoListRow` como base
/// visual del kit v2 — mismo patrón que `MedicionRow` (`medicion_list.dart`).
class RendimientoRow extends StatefulWidget {
  const RendimientoRow({
    super.key,
    required this.test,
    required this.palette,
    required this.onDelete,
    required this.onEdit,
  });

  final PerformanceTest test;
  final AppPalette palette;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  State<RendimientoRow> createState() => _RendimientoRowState();
}

class _RendimientoRowState extends State<RendimientoRow> {
  bool _expanded = false;

  /// Summary line: los 3 campos más marker del test — CMJ, Sprint 10m,
  /// Sentadilla 1RM. Si alguno es null se omite.
  String _summary() {
    final t = widget.test;
    final parts = <String>[];
    if (t.cmjCm != null) parts.add('CMJ ${t.cmjCm} cm');
    if (t.sprint10mS != null) parts.add('10m ${t.sprint10mS}s');
    if (t.squat1rmKg != null) parts.add('Sent. ${t.squat1rmKg} kg');
    if (parts.isEmpty) return 'Sin métricas cargadas'; // i18n: Fase W2
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.test;
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
          title: fmtDate(t.recordedAt),
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
            child: RendimientoDetail(test: t, palette: palette),
          ),
      ],
    );
  }
}

/// Detalle expandido de una prueba de rendimiento. Muestra solo los campos
/// con valor cargado, agrupados por categoría (saltos / sprints / 1RM /
/// resistencia), en 2 columnas.
class RendimientoDetail extends StatelessWidget {
  const RendimientoDetail(
      {super.key, required this.test, required this.palette});

  final PerformanceTest test;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final t = test;
    final entries = <(String, String)>[
      // Saltos
      if (t.cmjCm != null) ('CMJ', '${t.cmjCm} cm'),
      if (t.squatJumpCm != null) ('Squat Jump', '${t.squatJumpCm} cm'),
      if (t.abalakovCm != null) ('Abalakov', '${t.abalakovCm} cm'),
      if (t.broadJumpCm != null) ('Salto largo', '${t.broadJumpCm} cm'),
      // Sprints
      if (t.sprint10mS != null) ('Sprint 10m', '${t.sprint10mS} s'),
      if (t.sprint20mS != null) ('Sprint 20m', '${t.sprint20mS} s'),
      if (t.sprint30mS != null) ('Sprint 30m', '${t.sprint30mS} s'),
      if (t.sprint40mS != null) ('Sprint 40m', '${t.sprint40mS} s'),
      // 1RM
      if (t.squat1rmKg != null) ('Sentadilla 1RM', '${t.squat1rmKg} kg'),
      if (t.benchPress1rmKg != null)
        ('Press banca 1RM', '${t.benchPress1rmKg} kg'),
      if (t.deadlift1rmKg != null) ('Peso muerto 1RM', '${t.deadlift1rmKg} kg'),
      if (t.overheadPress1rmKg != null)
        ('Press militar 1RM', '${t.overheadPress1rmKg} kg'),
      if (t.pullUp1rmKg != null) ('Dominada 1RM', '${t.pullUp1rmKg} kg'),
      // Resistencia
      if (t.vo2maxMlKgMin != null) ('VO2 máx', '${t.vo2maxMlKgMin} ml/kg/min'),
      if (t.courseNavetteLevel != null)
        ('Course Navette', 'nivel ${t.courseNavetteLevel}'),
      if (t.cooperMeters != null) ('Cooper', '${t.cooperMeters} m'),
      if (t.sitAndReachCm != null) ('Sit & Reach', '${t.sitAndReachCm} cm'),
    ];

    if (entries.isEmpty && (t.notes ?? '').isEmpty) {
      return Text(
        'Esta prueba no tiene valores cargados.', // i18n: Fase W2
        style: TextStyle(color: palette.textMuted, fontSize: 13),
      );
    }

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
                      width: 140,
                      child: Text(
                        label,
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        value,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
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
        if ((t.notes ?? '').isNotEmpty) ...[
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
            t.notes!,
            style: TextStyle(color: palette.textPrimary, fontSize: 13),
          ),
        ],
      ],
    );
  }
}
