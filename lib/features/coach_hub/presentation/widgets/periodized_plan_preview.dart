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
/// día con los renglones y las superseries agrupadas en bloque.
///
/// Diseño neutro: UN solo color de acento, y sólo en lo que se toca
/// («Confirmar las N sugerencias» relleno y «Confirmar» de cada fila como
/// texto). Todo lo demás —datos, sugerencia, acciones secundarias, encabezados—
/// va en los grises del tema. El estado de cada fila es una marca chica al
/// final, no una pastilla: punto ámbar (sugerencia por confirmar), anillo
/// (sin match) o ✓ gris (resuelto).

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
/// `3 × 8 + 1 × 6`, o sólo la cantidad de series cuando el detalle va aparte
/// en la línea de datos (fallo, duración, distancia).
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

/// Descanso en su forma corta: `45 s`, `90 s`, `2 min`, `2 min 30 s`.
///
/// Por debajo de dos minutos un descanso que no es redondo se lee en
/// segundos (`90 s`, como lo escribe un PF); desde ahí, en minutos y
/// segundos. 0 o menos = no hay descanso que mostrar (cadena vacía).
String formatRestCompact(int seconds) {
  if (seconds <= 0) return '';
  if (seconds % 60 == 0) return '${seconds ~/ 60} min';
  if (seconds < 120) return '$seconds s';
  return '${seconds ~/ 60} min ${seconds % 60} s';
}

/// La línea gris de datos de un ejercicio, todo en un renglón separado por
/// « · »: series y carga ([describeWeekSets]), al fallo, duración, distancia,
/// la nota del slot (`16 kg c/u`, `RIR 2`…) y, si se pasa [restSeconds], el
/// descanso al final (`4 × 8–10 · 60 kg · 2 min`).
///
/// En una superserie el descanso NO va acá: va una sola vez en el encabezado
/// del bloque.
String exerciseDataLine(
  List<SetSpec> sets, {
  required AppL10n l10n,
  String? note,
  int? restSeconds,
}) {
  final durations = <String>{
    for (final s in sets)
      if ((s.durationSeconds ?? 0) > 0) _formatMinutes(s.durationSeconds!),
  };
  final distances = <String>{
    for (final s in sets)
      if ((s.distanceMeters ?? 0) > 0) _formatMeters(s.distanceMeters!),
  };
  final summary = describeWeekSets(sets, localeName: l10n.localeName);
  final rest = restSeconds == null ? '' : formatRestCompact(restSeconds);
  return [
    if (summary.isNotEmpty) summary,
    if (sets.any((s) => s.type == SetType.failure)) l10n.pdfImportFailure,
    ...durations,
    ...distances,
    if (note != null && note.trim().isNotEmpty) note.trim(),
    if (rest.isNotEmpty) rest,
  ].join(' · ');
}

/// Encabezado de un renglón con varios ejercicios: SUPERSERIE (2), TRISERIE
/// (3) o CIRCUITO (4 o más).
String blockHeaderLabel(AppL10n l10n, int count) => switch (count) {
      2 => l10n.pdfImportBlockSuperset(count),
      3 => l10n.pdfImportBlockTriset(count),
      _ => l10n.pdfImportBlockCircuit(count),
    };

/// Letra del bloque [index] (0-based) entre los renglones con varios
/// ejercicios DEL DÍA: A, B, … Z, AA, AB…
///
/// La letra sale de la posición entre los bloques y no del número de
/// renglón a propósito: el número puede faltar (calentamiento) o ser la fila
/// de Excel, y lo que el PF tiene que poder decir es «la A1 con la A2».
String blockLetter(int index) {
  var n = index;
  var out = '';
  do {
    out = String.fromCharCode(0x41 + n % 26) + out;
    n = n ~/ 26 - 1;
  } while (n >= 0);
  return out;
}

/// «Confirmar las N sugerencias», arriba de la vista previa: confirma de una
/// todas las filas con sugerencia pendiente, igual que tocar «Confirmar» en
/// cada una. Con [count] en 0 no se dibuja.
///
/// Es el ÚNICO relleno de acento de la vista previa: es la acción que más
/// trabajo ahorra, y que sea lo único que brilla es lo que la hace obvia.
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
      variant: TreinoButtonVariant.primary,
      expand: true,
      onPressed: onPressed,
    );
  }
}

/// Aviso de pendientes arriba de la vista previa, en superficie neutra:
/// «16 sugerencias por confirmar · 1 sin match». Con los dos en 0 no se
/// dibuja. La llave la pone cada pantalla (son sus enganches de test).
class PendingResolutionNotice extends StatelessWidget {
  const PendingResolutionNotice({
    super.key,
    required this.pendingSuggestions,
    required this.withoutSuggestion,
  });

  final int pendingSuggestions;
  final int withoutSuggestion;

  @override
  Widget build(BuildContext context) {
    if (pendingSuggestions <= 0 && withoutSuggestion <= 0) {
      return const SizedBox.shrink();
    }
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return ImportCard(
      padding: AppSpacing.s14,
      child: Text(
        [
          if (pendingSuggestions > 0)
            l10n.pdfImportPendingSuggestions(pendingSuggestions),
          if (withoutSuggestion > 0)
            l10n.pdfImportPendingNoMatch(withoutSuggestion),
        ].join(' · '),
        style: importText(palette.textMuted, size: AppTextSize.bodyDense),
      ),
    );
  }
}

/// Avisos del parser en superficie neutra: el ícono de aviso queda en ámbar,
/// chico, y el resto en los grises de la tarjeta. No bloquean la asignación.
class PreviewWarningsCard extends StatelessWidget {
  const PreviewWarningsCard({super.key, required this.warnings});

  final List<ImportDiagnostic> warnings;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return ImportCard(
      padding: AppSpacing.s14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                TreinoIcon.warning,
                size: _kSmallIcon,
                color: palette.warning,
                semanticLabel: l10n.commonWarning,
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: Text(
                  l10n.pdfImportWarningsCount(warnings.length),
                  style: importText(palette.textMuted,
                      size: AppTextSize.bodyDense, weight: AppFonts.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          ImportDiagnosticsList(diagnostics: warnings, neutralTitles: true),
        ],
      ),
    );
  }
}

/// Lado del punto de «sugerencia por confirmar» y del anillo de «sin match».
const double _kStatusDot = 7;

/// Grosor del anillo de «sin match»: lo que lo distingue del punto lleno
/// también sin color (daltonismo).
const double _kStatusRingStroke = 1.5;

/// Íconos chicos de la fila: ✓ de resuelto, chevrón, eslabón del bloque.
const double _kSmallIcon = 16;

/// Ancho mínimo del «A1» de un componente de superserie.
const double _kPrefixMinWidth = 18;

/// Flecha de la línea de sugerencia, a la altura del texto denso.
const double _kArrowIcon = 14;

/// Ancho del riel que une los ejercicios de una superserie.
const double _kRailWidth = 2;

/// Corrimiento del riel para que quede centrado bajo el eslabón.
const double _kRailInset = (_kSmallIcon - _kRailWidth) / 2;

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

List<SetSpec> _setsOf(PeriodizedExercise exercise, int week) =>
    week < exercise.weeks.length ? exercise.weeks[week] : const <SetSpec>[];

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
  /// datos y ✓— y al tocarlo se despliega con «Cambiar» y el texto del PDF.
  /// El Coach Hub no lo usa: ahí cada fila se revisa desplegada.
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
    // Letra de cada bloque: posición entre los renglones con varios
    // ejercicios del día ([blockLetter]).
    var blocks = 0;
    final letters = <int, String>{
      for (final row in day.rows)
        if (row.isSuperset) row.position: blockLetter(blocks++),
    };
    return ImportCard(
      padding: AppSpacing.s14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sin título de día: el plan importado no trae uno (sólo el número).
          Text(
            'DÍA ${day.dayNumber}',
            style: TextStyle(
              fontFamily: AppFonts.barlowCondensed,
              color: palette.textMuted,
              fontSize: AppTextSize.caption,
              fontWeight: AppFonts.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.hairline),
          for (final row in day.rows)
            _RowBlock(
              day: day,
              row: row,
              letter: letters[row.position],
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
    required this.letter,
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

  /// Letra del bloque (A, B…) si el renglón es una superserie.
  final String? letter;
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
    final l10n = AppL10n.of(context);
    final block = row.isSuperset;
    bool folded(PeriodizedExercise ex) {
      final key = exerciseKeyOf(day, row, ex);
      return collapseResolved &&
          _foldable(draft, key, ex, week) &&
          !expanded.contains(key);
    }

    // Una superserie lleva el descanso una sola vez, en su encabezado.
    final rest = block ? null : row.restSeconds;

    Widget lineFor(int i, PeriodizedExercise ex) {
      final key = exerciseKeyOf(day, row, ex);
      final prefix = block ? '$letter${i + 1}' : null;
      if (folded(ex)) {
        return _CollapsedExerciseLine(
          key: ValueKey(
              'ex-folded-${day.dayNumber}-${row.position}-${ex.component}'),
          exKey: key,
          exercise: ex,
          prefix: prefix,
          restSeconds: rest,
          week: week,
          draft: draft,
          onExpand: onToggle,
        );
      }
      return _ExerciseLine(
        key: ValueKey('ex-${day.dayNumber}-${row.position}-${ex.component}'),
        exKey: key,
        exercise: ex,
        prefix: prefix,
        restSeconds: rest,
        week: week,
        draft: draft,
        onConfirmSuggestion: onConfirmSuggestion,
        onPickManual: onPickManual,
        onCreateCustom: onCreateCustom,
        onUseAlternative: onUseAlternative,
        onCollapse: collapseResolved && _foldable(draft, key, ex, week)
            ? onToggle
            : null,
      );
    }

    final allFolded = row.exercises.every(folded);
    final warmup = row.isWarmup
        ? Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.hairline),
            child: Text(
              l10n.pdfImportWarmup,
              key: ValueKey('warmup-${day.dayNumber}-${row.position}'),
              style: _blockHeaderStyle(palette.textMuted),
            ),
          )
        : null;

    if (!block) {
      return Padding(
        // Plegada, el aire lo pone la propia línea (es su área de toque).
        padding: allFolded
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(vertical: AppSpacing.s8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (warmup != null)
              Padding(
                padding: EdgeInsets.only(top: allFolded ? AppSpacing.s8 : 0),
                child: warmup,
              ),
            for (final (i, ex) in row.exercises.indexed) lineFor(i, ex),
          ],
        ),
      );
    }

    // Superserie / triserie / circuito: encabezado gris con el eslabón y el
    // descanso, y un riel a la izquierda que une los componentes. Se lee
    // como UN bloque sin pedir color.
    final restText = formatRestCompact(row.restSeconds);
    final count = row.exercises.length;
    return Padding(
      key: ValueKey('superset-${day.dayNumber}-${row.position}'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (warmup != null) warmup,
          Row(
            key: ValueKey('block-header-${day.dayNumber}-${row.position}'),
            children: [
              Icon(TreinoIcon.supersetLink,
                  size: _kSmallIcon, color: palette.textMuted),
              const SizedBox(width: AppSpacing.hairline),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: blockHeaderLabel(l10n, count),
                        style: _blockHeaderStyle(palette.textMuted),
                      ),
                      if (restText.isNotEmpty)
                        TextSpan(
                          text: ' · ${l10n.pdfImportBlockRest(restText)}',
                          style: importText(palette.textFaint,
                              size: AppTextSize.caption),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.hairline),
          Container(
            key: ValueKey('block-rail-${day.dayNumber}-${row.position}'),
            // El riel arranca bajo el eslabón: así el ícono y la línea son
            // la misma columna.
            margin: const EdgeInsets.only(left: _kRailInset),
            padding: const EdgeInsets.only(left: AppSpacing.s12),
            decoration: BoxDecoration(
              border: Border(
                left:
                    BorderSide(color: palette.borderStrong, width: _kRailWidth),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, ex) in row.exercises.indexed) ...[
                  if (i > 0) const _DashedDivider(),
                  lineFor(i, ex),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Encabezado de bloque y marca de calentamiento: gris, caps, peso medio.
TextStyle _blockHeaderStyle(Color color) => importText(
      color,
      size: AppTextSize.caption,
      weight: AppFonts.w600,
    ).copyWith(letterSpacing: 0.6);

/// Divisor punteado fino entre los componentes de una superserie.
class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    final color = AppPalette.of(context).border;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.hairline),
      child: SizedBox(
        width: double.infinity,
        height: 1,
        child: CustomPaint(painter: _DashPainter(color)),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);
  final Color color;

  static const double _dash = 4;
  static const double _gap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final y = size.height / 2;
    for (var x = 0.0; x < size.width; x += _dash + _gap) {
      canvas.drawLine(
          Offset(x, y), Offset((x + _dash).clamp(0, size.width), y), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

/// Estado de una fila, dibujado como una marca chica al final del nombre.
enum _RowStatus { pending, noMatch, resolved }

/// La marca de estado: punto ámbar lleno (sugerencia por confirmar), anillo
/// hueco (sin match) o ✓ gris (resuelto). Forma distinta además de color,
/// para que se distingan también sin ver el color; y cada una con su label
/// para el lector de pantalla.
class _StatusMark extends StatelessWidget {
  const _StatusMark({required this.status, required this.exKey});

  final _RowStatus status;
  final ExerciseKey exKey;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final key = ValueKey('status-${status.name}-$exKey');
    return switch (status) {
      // Nodo propio, como las otras dos: si no, el label del ícono se funde
      // con el nombre del ejercicio y el lector lo lee pegado.
      _RowStatus.resolved => Semantics(
          key: key,
          container: true,
          label: l10n.pdfImportRowResolved,
          child: ExcludeSemantics(
            child: Icon(
              TreinoIcon.check,
              size: _kSmallIcon,
              color: palette.textFaint,
            ),
          ),
        ),
      _RowStatus.pending => Semantics(
          key: key,
          container: true,
          label: l10n.pdfImportMarkPending,
          child: Container(
            width: _kStatusDot,
            height: _kStatusDot,
            decoration: BoxDecoration(
              color: palette.warning,
              shape: BoxShape.circle,
            ),
          ),
        ),
      _RowStatus.noMatch => Semantics(
          key: key,
          container: true,
          label: l10n.pdfImportMarkNoMatch,
          child: Container(
            width: _kStatusDot + 1,
            height: _kStatusDot + 1,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: palette.dangerText, width: _kStatusRingStroke),
            ),
          ),
        ),
    };
  }
}

/// «A1», «A2»… del componente de una superserie, gris y en peso regular.
class _ComponentPrefix extends StatelessWidget {
  const _ComponentPrefix(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.s8),
      // Ancho mínimo fijo: «A1» y «B2» no miden lo mismo, y sin esto los
      // nombres de un bloque y del siguiente no quedan en la misma columna.
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: _kPrefixMinWidth),
        child: Text(
          text,
          style: importText(AppPalette.of(context).textFaint),
        ),
      ),
    );
  }
}

class _ExerciseLine extends StatefulWidget {
  const _ExerciseLine({
    super.key,
    required this.exKey,
    required this.exercise,
    required this.prefix,
    required this.restSeconds,
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

  /// «A1»… si es un componente de superserie.
  final String? prefix;

  /// Descanso para la línea de datos. Null en una superserie (va en el
  /// encabezado del bloque).
  final int? restSeconds;
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
  State<_ExerciseLine> createState() => _ExerciseLineState();
}

class _ExerciseLineState extends State<_ExerciseLine> {
  /// PDF: el texto del que salió el ejercicio, abierto o no. Es
  /// presentación: `setState` alcanza.
  bool _sourceOpen = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final w = widget;
    final exKey = w.exKey;
    final exercise = w.exercise;
    final assigned = w.draft.assignments[exKey];
    final alternative =
        w.onUseAlternative == null ? null : w.draft.alternatives[exKey];
    final source = exercise.sourceText;
    final hasSource = source != null && source.trim().isNotEmpty;
    final suggestion = w.draft.suggestions[exKey];
    final resolved = assigned != null;
    final reopened = resolved && w.onCollapse != null;
    // Ya asignada, la alternativa no es alternativa de nada.
    final showAlternative = alternative != null &&
        alternative.id != assigned?.id &&
        (!resolved || reopened);
    final emptyWeek = exercise.emptyWeeks.contains(w.week);
    final sets = _setsOf(exercise, w.week);
    final status = resolved
        ? _RowStatus.resolved
        : suggestion != null
            ? _RowStatus.pending
            : _RowStatus.noMatch;

    // Un ejercicio con la celda de la semana vacía va igual, pero en rojo.
    final nameColor = emptyWeek ? palette.dangerText : palette.textPrimary;

    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                resolved ? assigned.name : exercise.rawName,
                style: importText(nameColor, weight: AppFonts.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.s8),
            _StatusMark(status: status, exKey: exKey),
            if (reopened) ...[
              const SizedBox(width: AppSpacing.hairline),
              Icon(TreinoIcon.chevronUp,
                  size: _kSmallIcon, color: palette.textFaint),
            ],
          ],
        ),
        if (emptyWeek)
          Row(
            children: [
              Icon(TreinoIcon.warning,
                  size: _kSmallIcon, color: palette.dangerText),
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
          _DataLine(
            exerciseDataLine(
              sets,
              l10n: l10n,
              note: exercise.note,
              restSeconds: w.restSeconds,
            ),
          ),
      ],
    );

    final secondary = palette.textMuted;
    final actions = [
      if (!resolved && suggestion != null)
        _TextAction(
          label: l10n.pdfImportConfirm,
          accent: true,
          onPressed: () => w.onConfirmSuggestion(exKey),
        ),
      if (!resolved || reopened)
        _TextAction(
          label: resolved || suggestion != null
              ? l10n.pdfImportChange
              : l10n.pdfImportLinkLibrary,
          onPressed: () => w.onPickManual(exKey, exercise.rawName),
        ),
      if (showAlternative)
        _TextAction(
          label: l10n.pdfImportUseAlternative,
          onPressed: () => w.onUseAlternative!(exKey),
        ),
      // Sólo sin candidato: con una sugerencia el camino es confirmarla o
      // cambiarla.
      if (!resolved && suggestion == null)
        _TextAction(
          label: l10n.pdfImportCreateOwn,
          onPressed: () => w.onCreateCustom(exKey, exercise.rawName),
        ),
      if (hasSource)
        _TextAction(
          label:
              _sourceOpen ? l10n.pdfImportSourceHide : l10n.pdfImportSourceShow,
          onPressed: () => setState(() => _sourceOpen = !_sourceOpen),
        ),
    ];

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (reopened)
          _FoldToggle(
            key: ValueKey('fold-$exKey'),
            expanded: true,
            hint: l10n.pdfImportRowHideDetail,
            onTap: () => w.onCollapse!(exKey),
            child: head,
          )
        else
          head,
        if (!resolved && suggestion != null) ...[
          const SizedBox(height: AppSpacing.hairline),
          // La flecha va como ícono: Barlow no trae el glifo «→».
          Semantics(
            key: ValueKey('suggestion-$exKey'),
            container: true,
            label: l10n.pdfImportSuggestionA11y(suggestion.name),
            excludeSemantics: true,
            child: Row(
              children: [
                Icon(TreinoIcon.arrowRight,
                    size: _kArrowIcon, color: secondary),
                const SizedBox(width: AppSpacing.hairline),
                Flexible(
                  child: Text(
                    suggestion.name,
                    style: importText(secondary,
                        size: AppTextSize.bodyDense, weight: AppFonts.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
        // La alternativa queda como dato, debajo de la sugerencia, y la
        // acción como «Usar alternativa» a secas: los nombres se comparan
        // uno abajo del otro, y la fila de acciones no crece con un nombre
        // largo adentro.
        if (showAlternative)
          Text(
            l10n.pdfImportAlternative(alternative.name),
            style: importText(palette.textFaint, size: AppTextSize.caption),
          ),
        if (actions.isNotEmpty)
          // Corrido a la izquierda lo mismo que el padding del botón: el
          // texto de la primera acción queda alineado con el nombre.
          Transform.translate(
            offset: Offset(-TreinoButtonSize.sm.paddingH, 0),
            child: Wrap(children: actions),
          ),
        if (hasSource)
          AnimatedSize(
            key: ValueKey('src-$exKey'),
            duration: AppMotion.resolve(context, AppMotion.fast),
            curve: AppMotion.standard,
            alignment: Alignment.topLeft,
            child: _sourceOpen
                ? Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.s8),
                    child: Text(
                      source,
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

    final prefix = w.prefix;
    if (prefix == null) return body;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ComponentPrefix(prefix),
        Expanded(child: body),
      ],
    );
  }
}

/// La línea gris de datos: hasta dos renglones y, si no entra, puntos
/// suspensivos (el detalle completo está en el texto del PDF).
class _DataLine extends StatelessWidget {
  const _DataLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: importText(AppPalette.of(context).textMuted,
          size: AppTextSize.caption),
    );
  }
}

/// Acción de texto de una fila: gris, salvo «Confirmar» ([accent]), que es
/// la única de la fila en el color de acento.
class _TextAction extends StatelessWidget {
  const _TextAction({
    required this.label,
    required this.onPressed,
    this.accent = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return TreinoButton(
      label: label,
      variant:
          accent ? TreinoButtonVariant.ghostAccent : TreinoButtonVariant.ghost,
      size: TreinoButtonSize.sm,
      onPressed: onPressed,
    );
  }
}

/// Un ejercicio resuelto, plegado en UNA línea: el ejercicio de la
/// biblioteca, su línea de datos de la semana y un ✓ gris. Tocarla lo
/// despliega ([_ExerciseLine] con «Cambiar» y el texto del PDF).
class _CollapsedExerciseLine extends StatelessWidget {
  const _CollapsedExerciseLine({
    super.key,
    required this.exKey,
    required this.exercise,
    required this.prefix,
    required this.restSeconds,
    required this.week,
    required this.draft,
    required this.onExpand,
  });

  final ExerciseKey exKey;
  final PeriodizedExercise exercise;
  final String? prefix;
  final int? restSeconds;
  final int week;
  final PeriodizedImportDraft draft;
  final void Function(ExerciseKey key) onExpand;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final summary = exerciseDataLine(
      _setsOf(exercise, week),
      l10n: l10n,
      note: exercise.note,
      restSeconds: restSeconds,
    );
    final name = draft.assignments[exKey]?.name ?? exercise.rawName;
    return _FoldToggle(
      expanded: false,
      hint: l10n.pdfImportRowShowDetail,
      onTap: () => onExpand(exKey),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
        child: Row(
          children: [
            if (prefix != null) _ComponentPrefix(prefix!),
            // Una sola línea: si no entra, se corta el final (los datos) y
            // el detalle completo está al desplegar.
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
            _StatusMark(status: _RowStatus.resolved, exKey: exKey),
            const SizedBox(width: AppSpacing.hairline),
            Icon(TreinoIcon.chevronDown,
                size: _kSmallIcon, color: palette.textFaint),
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
