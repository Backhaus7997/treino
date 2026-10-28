import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/tokens/tokens.dart';
import '../../../../app/theme/app_motion.dart';
import '../../../../core/utils/kg_format.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../workout/domain/set_enums.dart';
import '../../../workout/domain/set_spec.dart';
import '../../data/periodized_import_draft.dart';
import '../../data/periodized_routine_mapper.dart';
import '../../domain/periodized_plan.dart';
import 'button/treino_button.dart';
import 'filter_chips/filter_chips.dart';
import 'import_plan_widgets.dart';
import 'treino_interactive_state.dart';

/// Vista previa del plan periodizado: selector de semana y una tarjeta por
/// día con los renglones, las superseries agrupadas y los chips de cada serie.

/// Etiqueta del chip de la semana [index] (0-based).
String weekLabel(int index) => 'SEMANA ${index + 1}';

/// Selector SEMANA 1..N. Siempre hay una semana elegida: tocar la elegida no
/// la deselecciona.
class PeriodizedWeekSelector extends StatelessWidget {
  const PeriodizedWeekSelector({
    super.key,
    required this.numWeeks,
    required this.selected,
    required this.onChanged,
  });

  final int numWeeks;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final labels = [for (var w = 0; w < numWeeks; w++) weekLabel(w)];
    return TreinoFilterChips(
      options: labels,
      selected: {weekLabel(selected)},
      onChanged: (next) {
        if (next.isEmpty) return;
        onChanged(labels.indexOf(next.first));
      },
    );
  }
}

/// Resumen en texto de las series de una semana: `3 × 8`, `3 × 8–10`,
/// `3 × 8 + 1 × 6`, o sólo la cantidad de series cuando el detalle va en los
/// chips (fallo, duración, distancia).
///
/// La carga va pegada a su grupo (`5 × 5 · 80 kg`; una pirámide sale
/// `1 × 10 · 60 kg + 1 × 8 · 70 kg`). Antes no se mostraba: el peso llegaba
/// al borrador y a la rutina, pero la vista previa sólo leía las reps, y el
/// rango (`repsMin`/`repsMax`) salía como «3 series».
String describeWeekSets(List<SetSpec> sets, {String localeName = 'es'}) {
  final groups = <(String, double?), int>{};
  for (final s in sets) {
    final token = switch (s) {
      SetSpec(type: SetType.failure) => '',
      SetSpec(durationSeconds: final d?) when d > 0 => '',
      SetSpec(distanceMeters: final m?) when m > 0 => '',
      SetSpec(reps: final r?) => '$r',
      SetSpec(repsMin: final min?, repsMax: final max?) => '$min–$max',
      _ => '',
    };
    final kg = s.weightKg;
    final key = (token, kg != null && kg > 0 ? kg : null);
    groups[key] = (groups[key] ?? 0) + 1;
  }
  String withLoad(String text, double? kg) =>
      kg == null ? text : '$text · ${formatWeightDisplay(kg, localeName)} kg';
  final parts = [
    for (final MapEntry(key: (token, kg), value: n) in groups.entries)
      if (token.isNotEmpty) withLoad('$n × $token', kg),
    for (final MapEntry(key: (token, kg), value: n) in groups.entries)
      if (token.isEmpty) withLoad('$n ${n == 1 ? 'serie' : 'series'}', kg),
  ];
  return parts.join(' + ');
}

/// «Confirmar las N sugerencias», arriba de la vista previa: confirma de una
/// todas las filas con sugerencia pendiente, igual que tocar «Confirmar» en
/// cada una. Con [count] en 0 no se dibuja.
class ConfirmAllSuggestionsButton extends StatelessWidget {
  const ConfirmAllSuggestionsButton({
    super.key,
    required this.count,
    required this.onPressed,
  });

  final int count;

  /// Null = deshabilitado (hay una escritura en curso).
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return TreinoButton(
      key: const Key('pdf_import_confirm_all'),
      label: AppL10n.of(context).pdfImportConfirmAll(count),
      icon: TreinoIcon.checkBare,
      variant: TreinoButtonVariant.secondaryAccent,
      expand: true,
      onPressed: onPressed,
    );
  }
}

String _formatMinutes(int seconds) {
  if (seconds % 60 == 0) return '${seconds ~/ 60} min';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return m == 0 ? '$s s' : '$m min $s s';
}

String _formatMeters(double m) =>
    m == m.truncateToDouble() ? '${m.toInt()} m' : '$m m';

/// ¿El ejercicio se pliega en una línea? Sólo si ya está resuelto y no le
/// falta nada esta semana: lo que pide atención (sugerencia pendiente, sin
/// match, celda vacía) queda desplegado.
bool _foldable(PeriodizedImportDraft draft, ExerciseKey key,
        PeriodizedExercise exercise, int week) =>
    draft.isResolved(key) && !exercise.emptyWeeks.contains(week);

/// Una tarjeta por día.
class PeriodizedDayPreviewCard extends StatefulWidget {
  const PeriodizedDayPreviewCard({
    super.key,
    required this.day,
    required this.week,
    required this.draft,
    required this.onConfirmSuggestion,
    required this.onPickManual,
    required this.onCreateCustom,
    this.onUseAlternative,
    this.collapseResolved = false,
  });

  final PeriodizedDay day;

  /// Semana mostrada (0-based).
  final int week;
  final PeriodizedImportDraft draft;
  final void Function(ExerciseKey key) onConfirmSuggestion;
  final void Function(ExerciseKey key, String rawName) onPickManual;

  /// «Crear como propio»: el padre pasa por el tope del plan y abre el
  /// formulario de ejercicio propio con [rawName] precargado.
  final void Function(ExerciseKey key, String rawName) onCreateCustom;

  /// PDF: usar la alternativa del extractor ([PeriodizedImportDraft.alternatives])
  /// en vez de la sugerencia. Null = no se ofrece (el Excel no tiene).
  final void Function(ExerciseKey key)? onUseAlternative;

  /// Mobile (PDF): un ejercicio resuelto se pliega en una línea —nombre,
  /// series y ✓— y al tocarlo se despliega con «Cambiar» y el texto del PDF.
  /// El Coach Hub (Excel) no lo usa: ahí casi todo matchea exacto y lo que el
  /// PF revisa son justamente los chips de cada fila.
  final bool collapseResolved;

  @override
  State<PeriodizedDayPreviewCard> createState() =>
      _PeriodizedDayPreviewCardState();
}

class _PeriodizedDayPreviewCardState extends State<PeriodizedDayPreviewCard> {
  /// Resueltos que el PF desplegó a mano. Es presentación: `setState`
  /// alcanza. Uno que se resuelve después arranca plegado.
  final Set<ExerciseKey> _expanded = {};

  void _toggle(ExerciseKey key) => setState(() {
        if (!_expanded.remove(key)) _expanded.add(key);
      });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final day = widget.day;
    return ImportCard(
      padding: AppSpacing.s14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DÍA ${day.dayNumber}',
            style: TextStyle(
              fontFamily: AppFonts.barlowCondensed,
              color: palette.highlight,
              fontSize: AppTextSize.caption,
              fontWeight: AppFonts.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          for (final row in day.rows)
            _RowBlock(
              day: day,
              row: row,
              week: widget.week,
              draft: widget.draft,
              onConfirmSuggestion: widget.onConfirmSuggestion,
              onPickManual: widget.onPickManual,
              onCreateCustom: widget.onCreateCustom,
              onUseAlternative: widget.onUseAlternative,
              collapseResolved: widget.collapseResolved,
              expanded: _expanded,
              onToggle: _toggle,
            ),
        ],
      ),
    );
  }
}

class _RowBlock extends StatelessWidget {
  const _RowBlock({
    required this.day,
    required this.row,
    required this.week,
    required this.draft,
    required this.onConfirmSuggestion,
    required this.onPickManual,
    required this.onCreateCustom,
    required this.onUseAlternative,
    required this.collapseResolved,
    required this.expanded,
    required this.onToggle,
  });

  final PeriodizedDay day;
  final PeriodizedRow row;
  final int week;
  final PeriodizedImportDraft draft;
  final void Function(ExerciseKey key) onConfirmSuggestion;
  final void Function(ExerciseKey key, String rawName) onPickManual;

  /// «Crear como propio»: el padre pasa por el tope del plan y abre el
  /// formulario de ejercicio propio con [rawName] precargado.
  final void Function(ExerciseKey key, String rawName) onCreateCustom;
  final void Function(ExerciseKey key)? onUseAlternative;
  final bool collapseResolved;
  final Set<ExerciseKey> expanded;
  final void Function(ExerciseKey key) onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    bool folded(PeriodizedExercise ex) {
      final key = exerciseKeyOf(day, row, ex);
      return collapseResolved &&
          _foldable(draft, key, ex, week) &&
          !expanded.contains(key);
    }

    final lines = [
      for (final ex in row.exercises)
        if (folded(ex))
          _CollapsedExerciseLine(
            key: ValueKey(
                'ex-folded-${day.dayNumber}-${row.position}-${ex.component}'),
            exKey: exerciseKeyOf(day, row, ex),
            exercise: ex,
            week: week,
            draft: draft,
            onExpand: onToggle,
          )
        else
          _ExerciseLine(
            key:
                ValueKey('ex-${day.dayNumber}-${row.position}-${ex.component}'),
            exKey: exerciseKeyOf(day, row, ex),
            exercise: ex,
            week: week,
            draft: draft,
            onConfirmSuggestion: onConfirmSuggestion,
            onPickManual: onPickManual,
            onCreateCustom: onCreateCustom,
            onUseAlternative: onUseAlternative,
            onCollapse: collapseResolved &&
                    _foldable(draft, exerciseKeyOf(day, row, ex), ex, week)
                ? onToggle
                : null,
          ),
    ];

    // Con la fila entera plegada, el descanso se ve al desplegar: si no,
    // cada línea compacta arrastra su renglón de chips. El calentamiento
    // queda, porque cambia cómo se lee la serie.
    final allFolded = row.exercises.every(folded);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (row.isSuperset)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.hairline),
            child: Text(
              'SUPERSERIE',
              style: importText(
                palette.accent,
                size: AppTextSize.micro,
                weight: AppFonts.w700,
              ),
            ),
          ),
        ...lines,
        if (!allFolded || row.isWarmup)
          Wrap(
            spacing: AppSpacing.s8,
            runSpacing: AppSpacing.s8,
            children: [
              if (row.isWarmup)
                ImportChip(label: 'CALENTAMIENTO', color: palette.warning),
              if (!allFolded)
                ImportChip(label: 'Descanso ${row.restSeconds} s'),
            ],
          ),
      ],
    );

    return Padding(
      // Plegada, el aire lo pone la propia línea (es su área de toque).
      padding: allFolded && !row.isSuperset
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(vertical: AppSpacing.s8),
      child: row.isSuperset
          // Las superseries se agrupan con un borde de acento y un fondo propio: se leen como UN bloque con varios ejercicios.
          ? Container(
              key: ValueKey('superset-${day.dayNumber}-${row.position}'),
              padding: const EdgeInsets.all(AppSpacing.s12),
              decoration: BoxDecoration(
                color: palette.bg,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: palette.accent),
              ),
              child: content,
            )
          : content,
    );
  }
}

class _ExerciseLine extends StatelessWidget {
  const _ExerciseLine({
    super.key,
    required this.exKey,
    required this.exercise,
    required this.week,
    required this.draft,
    required this.onConfirmSuggestion,
    required this.onPickManual,
    required this.onCreateCustom,
    required this.onUseAlternative,
    required this.onCollapse,
  });

  final ExerciseKey exKey;
  final PeriodizedExercise exercise;
  final int week;
  final PeriodizedImportDraft draft;
  final void Function(ExerciseKey key) onConfirmSuggestion;
  final void Function(ExerciseKey key, String rawName) onPickManual;

  /// «Crear como propio»: el padre pasa por el tope del plan y abre el
  /// formulario de ejercicio propio con [rawName] precargado.
  final void Function(ExerciseKey key, String rawName) onCreateCustom;
  final void Function(ExerciseKey key)? onUseAlternative;

  /// No null = es un resuelto que el PF desplegó: el encabezado lo vuelve a
  /// plegar, y se ofrece «Cambiar».
  final void Function(ExerciseKey key)? onCollapse;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final assigned = draft.assignments[exKey];
    final alternative =
        onUseAlternative == null ? null : draft.alternatives[exKey];
    final source = exercise.sourceText;
    final suggestion = draft.suggestions[exKey];
    final resolved = assigned != null;
    final reopened = resolved && onCollapse != null;
    // Ya asignada, la alternativa no es alternativa de nada.
    final showAlternative = alternative != null &&
        alternative.id != assigned?.id &&
        (!resolved || reopened);
    final emptyWeek = exercise.emptyWeeks.contains(week);
    final sets =
        week < exercise.weeks.length ? exercise.weeks[week] : const <SetSpec>[];

    // Un ejercicio con la celda de la semana vacía va igual, pero en rojo.
    final nameColor = emptyWeek ? palette.dangerText : palette.textPrimary;

    // Wrap y no Row: en un teléfono angosto, o con la letra grande, el chip
    // no entra al lado del nombre y baja de renglón (en una Row desbordaba).
    final header = Wrap(
      spacing: AppSpacing.s8,
      runSpacing: AppSpacing.hairline,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          resolved ? assigned.name : exercise.rawName,
          style: importText(nameColor, weight: AppFonts.w600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (!resolved)
          ImportChip(
            label: suggestion != null ? 'sugerencia pendiente' : 'sin match',
            color: palette.warning,
          ),
        if (reopened) ...[
          Icon(
            TreinoIcon.check,
            size: AppSpacing.s18,
            color: palette.accent,
            semanticLabel: l10n.pdfImportRowResolved,
          ),
          Icon(TreinoIcon.chevronUp,
              size: AppSpacing.s18, color: palette.textMuted),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (reopened)
            _FoldToggle(
              key: ValueKey('fold-$exKey'),
              expanded: true,
              hint: l10n.pdfImportRowHideDetail,
              onTap: () => onCollapse!(exKey),
              child: header,
            )
          else
            header,
          const SizedBox(height: AppSpacing.hairline),
          if (emptyWeek)
            Row(
              children: [
                Icon(TreinoIcon.warning, color: palette.dangerText),
                const SizedBox(width: AppSpacing.hairline),
                Text(
                  'falta cargar reps',
                  style: importText(
                    palette.dangerText,
                    size: AppTextSize.caption,
                    weight: AppFonts.w600,
                  ),
                ),
              ],
            )
          else
            Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.hairline,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  describeWeekSets(sets, localeName: l10n.localeName),
                  style: importText(
                    palette.textMuted,
                    size: AppTextSize.caption,
                  ),
                ),
                ..._chipsFor(sets, exercise.note, palette),
              ],
            ),
          if (!resolved && suggestion != null) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(
              'Sugerencia: ${suggestion.name}',
              style: importText(
                palette.accent,
                size: AppTextSize.bodyDense,
                weight: AppFonts.w600,
              ),
            ),
          ],
          if (showAlternative) ...[
            const SizedBox(height: AppSpacing.hairline),
            Text(
              l10n.pdfImportAlternative(alternative.name),
              style: importText(palette.textMuted,
                  size: AppTextSize.bodyDense, weight: AppFonts.w600),
            ),
          ],
          if (!resolved || reopened) ...[
            const SizedBox(height: AppSpacing.s8),
            Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: [
                if (!resolved && suggestion != null)
                  TreinoButton(
                    label: 'Confirmar',
                    variant: TreinoButtonVariant.primary,
                    size: TreinoButtonSize.sm,
                    onPressed: () => onConfirmSuggestion(exKey),
                  ),
                TreinoButton(
                  label: resolved || suggestion != null
                      ? 'Cambiar'
                      : 'Vincular con la biblioteca',
                  icon: TreinoIcon.search,
                  variant: TreinoButtonVariant.ghostAccent,
                  size: TreinoButtonSize.sm,
                  onPressed: () => onPickManual(exKey, exercise.rawName),
                ),
                if (showAlternative)
                  TreinoButton(
                    label: l10n.pdfImportUseAlternative,
                    variant: TreinoButtonVariant.ghostAccent,
                    size: TreinoButtonSize.sm,
                    onPressed: () => onUseAlternative!(exKey),
                  ),
                // Sólo sin candidato: con una sugerencia el camino es
                // confirmarla o cambiarla.
                if (!resolved && suggestion == null)
                  TreinoButton(
                    label: 'Crear como propio',
                    icon: TreinoIcon.plus,
                    variant: TreinoButtonVariant.ghostAccent,
                    size: TreinoButtonSize.sm,
                    onPressed: () => onCreateCustom(exKey, exercise.rawName),
                  ),
              ],
            ),
          ],
          if (source != null && source.trim().isNotEmpty)
            _SourceText(key: ValueKey('src-$exKey'), text: source),
        ],
      ),
    );
  }

  /// Chips de las series de la semana: AL FALLO, duración, distancia y la
  /// nota del slot (`c/pierna`…).
  List<Widget> _chipsFor(List<SetSpec> sets, String? note, AppPalette palette) {
    final durations = <String>{
      for (final s in sets)
        if ((s.durationSeconds ?? 0) > 0) _formatMinutes(s.durationSeconds!),
    };
    final distances = <String>{
      for (final s in sets)
        if ((s.distanceMeters ?? 0) > 0) _formatMeters(s.distanceMeters!),
    };
    return [
      if (sets.any((s) => s.type == SetType.failure))
        ImportChip(label: 'AL FALLO', color: palette.highlight),
      for (final d in durations) ImportChip(label: d),
      for (final m in distances) ImportChip(label: m),
      if (note != null && note.isNotEmpty) ImportChip(label: note),
    ];
  }
}

/// Un ejercicio resuelto, plegado en UNA línea: el ejercicio de la
/// biblioteca, el resumen de series de la semana y un ✓. Tocarla lo
/// despliega ([_ExerciseLine] con «Cambiar» y el texto del PDF).
class _CollapsedExerciseLine extends StatelessWidget {
  const _CollapsedExerciseLine({
    super.key,
    required this.exKey,
    required this.exercise,
    required this.week,
    required this.draft,
    required this.onExpand,
  });

  final ExerciseKey exKey;
  final PeriodizedExercise exercise;
  final int week;
  final PeriodizedImportDraft draft;
  final void Function(ExerciseKey key) onExpand;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final sets =
        week < exercise.weeks.length ? exercise.weeks[week] : const <SetSpec>[];
    final summary = describeWeekSets(sets, localeName: l10n.localeName);
    final name = draft.assignments[exKey]?.name ?? exercise.rawName;
    return _FoldToggle(
      expanded: false,
      hint: l10n.pdfImportRowShowDetail,
      onTap: () => onExpand(exKey),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
        child: Row(
          children: [
            // Una sola línea: si no entra, se corta el final (las series) y
            // el nombre completo está al desplegar.
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: name,
                      style: importText(palette.textPrimary,
                          weight: AppFonts.w600),
                    ),
                    if (summary.isNotEmpty)
                      TextSpan(
                        text: '  ·  $summary',
                        style: importText(palette.textMuted,
                            size: AppTextSize.caption),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            Icon(
              TreinoIcon.check,
              size: AppSpacing.s18,
              color: palette.accent,
              semanticLabel: l10n.pdfImportRowResolved,
            ),
            const SizedBox(width: AppSpacing.hairline),
            Icon(TreinoIcon.chevronDown,
                size: AppSpacing.s18, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}

/// Área tocable que pliega o despliega un ejercicio resuelto: hover y foco de
/// teclado del kit ([TreinoInteractiveState]) y, para el lector de pantalla,
/// si está desplegado y qué hace tocarlo.
class _FoldToggle extends StatelessWidget {
  const _FoldToggle({
    super.key,
    required this.expanded,
    required this.hint,
    required this.onTap,
    required this.child,
  });

  final bool expanded;
  final String hint;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      expanded: expanded,
      onTapHint: hint,
      child: TreinoInteractiveState(
        onTap: onTap,
        builder: (ctx, states) => DecoratedBox(
          decoration: BoxDecoration(
            color: states.hovered || states.pressed
                ? TreinoListRowTokens.of(ctx).hoverBackground
                : null,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: states.focused
                ? Border.all(
                    color: TreinoFocusTokens.of(ctx).ring,
                    width: TreinoFocusTokens.ringWidth,
                  )
                : null,
          ),
          child: SizedBox(width: double.infinity, child: child),
        ),
      ),
    );
  }
}

/// PDF: el texto del que salió el ejercicio, plegado, para que el PF lo
/// compare con lo que se leyó sin que la tarjeta crezca de entrada. El
/// estado abierto/cerrado es de presentación: `setState` alcanza.
class _SourceText extends StatefulWidget {
  const _SourceText({super.key, required this.text});
  final String text;

  @override
  State<_SourceText> createState() => _SourceTextState();
}

class _SourceTextState extends State<_SourceText> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TreinoButton(
          label: _open ? l10n.pdfImportSourceHide : l10n.pdfImportSourceShow,
          icon: _open ? TreinoIcon.chevronUp : TreinoIcon.chevronDown,
          variant: TreinoButtonVariant.ghost,
          size: TreinoButtonSize.xs,
          onPressed: () => setState(() => _open = !_open),
        ),
        AnimatedSize(
          duration: AppMotion.resolve(context, AppMotion.fast),
          curve: AppMotion.standard,
          alignment: Alignment.topLeft,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.hairline),
                  child: Text(
                    widget.text,
                    style: importText(
                      palette.textMuted,
                      size: AppTextSize.caption,
                      height: 1.4,
                    ).copyWith(fontStyle: FontStyle.italic),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
