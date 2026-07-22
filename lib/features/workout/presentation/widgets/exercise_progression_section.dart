// IMPORTANT: This widget MUST NOT import app_l10n.dart (R3 / SCENARIO-PROG-11C).
// All user-visible strings are injected as plain String parameters via
// [ExerciseProgressionSectionLabels]. The mobile caller resolves them from
// AppL10n; the web caller passes hardcoded Spanish strings.
//
// This is the shared section-level widget extracted from the duplicated
// `_ProgressionSection`/`_ProgressionChartLoader` (mobile coach shell) and
// `_ProgressionTabSection`/`_ProgressionChartLoader` (web coach_hub shell).
// AD1: dedupe at the SECTION level, not just the chart widget — both shells
// must render identically from ONE widget given the same data (dedup
// contract, see exercise_progression_section_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../insights/domain/chart_period.dart';
import '../../application/exercise_filter.dart' show foldSearch;
import '../../application/exercise_progression_providers.dart';
import '../../domain/exercise_progression.dart' show ExerciseListEntry;
import 'exercise_progression_chart.dart';
import 'personal_records_list.dart';

/// [AD7] Plain-string label bag for the chart period selector — one label
/// per [ChartPeriod] variant. NEVER imports AppL10n (same R3 rule as the
/// rest of this file's label bags).
class ChartPeriodLabels {
  const ChartPeriodLabels({
    required this.last30dLabel,
    required this.thisWeekLabel,
    required this.monthLabel,
  });

  /// E.g. 'Últimos 30 días' — [ChartPeriod.last30d] (default).
  final String last30dLabel;

  /// E.g. 'Esta semana' — [ChartPeriod.thisWeek].
  final String thisWeekLabel;

  /// E.g. 'Este mes' — [ChartPeriod.month].
  final String monthLabel;

  String labelFor(ChartPeriod period) {
    switch (period) {
      case ChartPeriod.last30d:
        return last30dLabel;
      case ChartPeriod.thisWeek:
        return thisWeekLabel;
      case ChartPeriod.month:
        return monthLabel;
    }
  }
}

/// Plain-string label bag for [ExerciseProgressionSection].
///
/// Wraps [ExerciseProgressionChartLabels] plus the section-level strings
/// (title, loading, error, empty state) so the whole section can be
/// label-injected without importing AppL10n.
///
/// [AD3] [chartLabels] now carries 4 distinct metric labels (Heaviest
/// Weight/1RM/Best Set Volume/Best Session Volume) instead of the original
/// 2 (PR/Volumen) — see exercise_progression_chart.dart.
class ExerciseProgressionSectionLabels {
  const ExerciseProgressionSectionLabels({
    required this.sectionTitle,
    required this.loadingText,
    this.exerciseListErrorText,
    required this.emptyStateText,
    required this.chartLabels,
    required this.periodLabels,
    required this.localeName,
    required this.personalRecordsLabels,
    this.searchLabels,
  });

  /// E.g. 'EVOLUCIÓN POR EJERCICIO'.
  ///
  /// Null → no se renderiza encabezado de sección. Los shells del coach SÍ lo
  /// pasan: ahí la sección convive con otras (Antropometría, Rendimiento…) y
  /// necesita identificarse. En una pantalla DEDICADA el header de la pantalla
  /// ya dice lo mismo, y repetirlo es ruido.
  final String? sectionTitle;

  /// E.g. 'Cargando…' — shown while the exercise list loads.
  final String loadingText;

  /// E.g. 'No se pudo cargar la evolución.' — shown on exercise-list error.
  /// Null preserves the mobile shell's original behavior of showing nothing
  /// on error (SizedBox.shrink).
  final String? exerciseListErrorText;

  /// E.g. 'Sin registros de series todavía.' — shown when no exercises exist.
  final String emptyStateText;

  /// Labels forwarded to [ExerciseProgressionChart].
  final ExerciseProgressionChartLabels chartLabels;

  /// [AD7] Labels for the chart period selector.
  final ChartPeriodLabels periodLabels;

  /// Locale name for date formatting (e.g. 'es_AR', 'en').
  final String localeName;

  /// [AD3] Labels for the per-exercise [PersonalRecordsList] shown below the
  /// progression chart.
  final PersonalRecordsListLabels personalRecordsLabels;

  /// Cuando es null (default), NO se renderiza el buscador y la chip row lista
  /// TODOS los ejercicios — o sea, el comportamiento actual, intacto. Los
  /// shells del coach no pasan esto, así que no cambian en nada.
  ///
  /// Cuando se pasa, aparece un campo de búsqueda y la chip row se recorta a
  /// [kPickerChipCap] (ver su doc). Es la variante que usa la pantalla del
  /// alumno: con decenas de ejercicios logueados, un carrusel horizontal es
  /// incómodo de recorrer.
  final ExercisePickerSearchLabels? searchLabels;
}

/// Plain-string label bag del buscador del picker. NUNCA importa AppL10n
/// (misma regla R3 que el resto de este archivo).
class ExercisePickerSearchLabels {
  const ExercisePickerSearchLabels({
    required this.hintText,
    required this.noResultsText,
  });

  /// E.g. 'Buscar ejercicio…'
  final String hintText;

  /// E.g. 'Ningún ejercicio tuyo coincide.' — la búsqueda corre SOBRE LOS
  /// EJERCICIOS QUE EL ATLETA REGISTRÓ, no sobre el catálogo. Un ejercicio que
  /// nunca entrenó no tiene progresión que mostrar, así que no debe aparecer.
  final String noResultsText;
}

/// Cuántos chips se muestran cuando el buscador está activo y el campo está
/// vacío. El resto se alcanza tipeando.
///
/// El pedido original era "5/10 principales"; 10 da suficiente alcance sin
/// convertir la fila en el mismo carrusel infinito que se quería evitar.
const int kPickerChipCap = 10;

/// Per-exercise progression section — shared between the mobile coach shell
/// and the web coach_hub shell (AD1).
///
/// Watches [athleteExerciseListProvider] to show an exercise picker row and
/// [exerciseProgressionProvider] to show the progression chart for the
/// selected exercise.
class ExerciseProgressionSection extends ConsumerStatefulWidget {
  const ExerciseProgressionSection({
    super.key,
    required this.athleteId,
    required this.labels,
    this.externalExerciseSelection,
    this.initialExerciseId,
  });

  /// Preselecciona un ejercicio al montar — p. ej. cuando se llega desde
  /// "Ejercicios frecuentes" tocando una fila. Null → default: el más
  /// recientemente logueado CON datos en el período activo
  /// (SCENARIO-PROG-05B acotado por #377).
  final String? initialExerciseId;

  final String athleteId;
  final ExerciseProgressionSectionLabels labels;

  /// [PR4] Optional external-selection hook — when a sibling widget (e.g.
  /// [MostFrequentExercisesList]) wants to drive which exercise this section
  /// displays (navigable to the existing exercise progression/detail),
  /// it calls `.value = exerciseId` on this notifier. Purely additive: when
  /// null (default), the section behaves exactly as before, owning its own
  /// selection state internally.
  final ValueNotifier<String?>? externalExerciseSelection;

  @override
  ConsumerState<ExerciseProgressionSection> createState() =>
      _ExerciseProgressionSectionState();
}

class _ExerciseProgressionSectionState
    extends ConsumerState<ExerciseProgressionSection> {
  String? _selectedExerciseId;

  /// [#377] Período activo cuando [_selectedExerciseId] se fijó por una
  /// acción EXPLÍCITA (tap en chip, [ExerciseProgressionSection.initialExerciseId],
  /// hook externo). Una selección explícita se respeta dentro de su período
  /// aunque no tenga datos ahí; al cambiar a un período donde queda vacía,
  /// vuelve la preselección acotada (ver [_effectiveExerciseId]) sin olvidar
  /// la elección — volver al período original la restaura.
  ChartPeriod? _selectionPeriod;

  /// [AD7] Defaults to [ChartPeriod.defaultPeriod] (last30d).
  ChartPeriod _selectedPeriod = ChartPeriod.defaultPeriod;

  /// Texto tipeado en el buscador. Sólo se usa cuando `labels.searchLabels`
  /// no es null.
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selectedExerciseId = widget.initialExerciseId;
    if (widget.initialExerciseId != null) {
      // Llegar con un ejercicio elegido (fila de "Ejercicios frecuentes") es
      // tan explícito como tocar un chip: se respeta en el período de apertura.
      _selectionPeriod = _selectedPeriod;
    }
    widget.externalExerciseSelection?.addListener(_onExternalSelection);
  }

  @override
  void dispose() {
    widget.externalExerciseSelection?.removeListener(_onExternalSelection);
    super.dispose();
  }

  /// Los ejercicios que la chip row muestra AHORA.
  ///
  /// Sin buscador → todos (comportamiento histórico, intacto).
  /// Con buscador y campo vacío → los primeros [kPickerChipCap]; si el
  /// ejercicio EFECTIVO cayó más allá del cap (#377: la preselección acotada
  /// puede elegir el #11+ cuando los 10 más recientes no tienen datos en el
  /// período), reemplaza al último para que el chip seleccionado siempre esté
  /// visible — el chart no nombra al ejercicio en ningún otro lado.
  /// Con buscador y texto → todos los que matchean, sin tope: si tipeaste algo
  /// concreto, querés verlo aunque sea el ejercicio número 37.
  ///
  /// El filtro corre sobre `exerciseName`, que viene DENORMALIZADO en el
  /// SetLog — sin lecturas extra a Firestore y sin tocar el catálogo (la razón
  /// exacta por la que el ADR de `exercise-progression` prohíbe reusar
  /// exercise_picker_sheet.dart acá: aquél busca sobre los 429 ejercicios del
  /// catálogo, y un ejercicio que nunca entrenaste no tiene progresión).
  List<ExerciseListEntry> _visibleExercises(
      List<ExerciseListEntry> all, String effectiveId) {
    if (widget.labels.searchLabels == null) return all;

    final q = foldSearch(_query.trim());
    if (q.isEmpty) {
      final capped = all.take(kPickerChipCap).toList();
      if (!capped.any((e) => e.exerciseId == effectiveId)) {
        final effective =
            all.where((e) => e.exerciseId == effectiveId).toList();
        if (effective.isNotEmpty && capped.isNotEmpty) {
          capped[capped.length - 1] = effective.first;
        }
      }
      return capped;
    }

    return all
        .where((e) => foldSearch(e.exerciseName).contains(q))
        .toList(growable: false);
  }

  void _onExternalSelection() {
    final id = widget.externalExerciseSelection?.value;
    if (id != null) {
      setState(() {
        _selectedExerciseId = id;
        _selectionPeriod = _selectedPeriod;
      });
    }
  }

  /// SCENARIO-PROG-05B acotado por #377: el ejercicio efectivo debe tener
  /// datos EN EL PERÍODO ACTIVO — nunca abrir por sí solo en el empty state
  /// del chart ("Sin datos para este ejercicio.").
  ///
  /// - Selección explícita ([_selectionPeriod] == período activo) → se
  ///   respeta siempre, tenga o no datos: el usuario la pidió en este período.
  /// - Selección recordada de otro período → se respeta sólo si tiene datos
  ///   en el período activo; si quedó vacía, cae la preselección de abajo.
  /// - Preselección: el más recientemente logueado CON datos en el período.
  ///   Si NINGUNO tiene datos en la ventana (todo el historial quedó afuera),
  ///   se mantiene el default histórico (el más reciente global) — el empty
  ///   state ahí es verdad y no hay candidato mejor.
  String _effectiveExerciseId(List<ExerciseListEntry> exercises) {
    final selected = _selectedExerciseId;
    if (selected != null) {
      final selectedHasData = exercises.any((e) =>
          e.exerciseId == selected &&
          e.periodsWithData.contains(_selectedPeriod));
      if (selectedHasData || _selectionPeriod == _selectedPeriod) {
        return selected;
      }
    }

    return exercises
        .firstWhere(
          (e) => e.periodsWithData.contains(_selectedPeriod),
          orElse: () => exercises.first,
        )
        .exerciseId;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final labels = widget.labels;
    final exerciseListAsync =
        ref.watch(athleteExerciseListProvider(widget.athleteId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header (omitido en pantallas dedicadas) ─────────────
        if (labels.sectionTitle != null) ...[
          Text(
            labels.sectionTitle!,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 12),
        ],

        exerciseListAsync.when(
          loading: () => Text(
            labels.loadingText,
            style: GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
          ),
          error: (e, _) => labels.exerciseListErrorText == null
              ? const SizedBox.shrink()
              : Text(
                  labels.exerciseListErrorText!,
                  style: GoogleFonts.barlow(
                      fontSize: 13, color: palette.textMuted),
                ),
          data: (exercises) {
            // SCENARIO-PROG-08A: no exercises → empty state, no picker
            if (exercises.isEmpty) {
              return Text(
                labels.emptyStateText,
                style:
                    GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
              );
            }

            // SCENARIO-PROG-05B + #377: bounded by the active period — see
            // [_effectiveExerciseId].
            final effectiveId = _effectiveExerciseId(exercises);

            final searchLabels = widget.labels.searchLabels;
            final visible = _visibleExercises(exercises, effectiveId);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Buscador (sólo si el caller lo pidió) ─────────────
                if (searchLabels != null) ...[
                  _ExerciseSearchField(
                    hintText: searchLabels.hintText,
                    onChanged: (v) => setState(() => _query = v),
                  ),
                  const SizedBox(height: 10),
                ],

                // ── Exercise picker chip row ──────────────────────────
                //
                // `selectedId: effectiveId` a propósito, aunque el ejercicio
                // seleccionado NO esté entre los visibles: la selección es
                // independiente del filtro. Si no fuera así, tipear en el
                // buscador borraría el gráfico que estabas mirando.
                if (visible.isEmpty && searchLabels != null)
                  Text(
                    searchLabels.noResultsText,
                    style: GoogleFonts.barlow(
                        fontSize: 13, color: palette.textMuted),
                  )
                else
                  ExercisePickerRow(
                    exercises: visible,
                    selectedId: effectiveId,
                    onSelect: (id) => setState(() {
                      _selectedExerciseId = id;
                      _selectionPeriod = _selectedPeriod;
                    }),
                  ),
                const SizedBox(height: 12),

                // ── Period selector ────────────────────────────────────
                Align(
                  alignment: Alignment.centerRight,
                  child: ChartPeriodSelector(
                    selected: _selectedPeriod,
                    labels: labels.periodLabels,
                    onSelect: (p) => setState(() => _selectedPeriod = p),
                  ),
                ),
                const SizedBox(height: 8),

                // ── Progression chart ─────────────────────────────────
                _ProgressionChartLoader(
                  athleteId: widget.athleteId,
                  exerciseId: effectiveId,
                  chartLabels: labels.chartLabels,
                  localeName: labels.localeName,
                  period: _selectedPeriod,
                  personalRecordsLabels: labels.personalRecordsLabels,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Loads and renders [ExerciseProgressionChart] + [PersonalRecordsList] for
/// one exercise — both are derived from the same [exerciseProgressionProvider]
/// read (single Firestore-backed fetch, see [ExerciseProgression]).
class _ProgressionChartLoader extends ConsumerWidget {
  const _ProgressionChartLoader({
    required this.athleteId,
    required this.exerciseId,
    required this.chartLabels,
    required this.localeName,
    required this.period,
    required this.personalRecordsLabels,
  });

  final String athleteId;
  final String exerciseId;
  final ExerciseProgressionChartLabels chartLabels;
  final String localeName;

  /// [AD7] Selected chart period — bounds the returned series.
  final ChartPeriod period;

  /// [AD3] Labels for the [PersonalRecordsList] shown below the chart.
  final PersonalRecordsListLabels personalRecordsLabels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressionAsync = ref.watch(
      exerciseProgressionProvider(
          (athleteUid: athleteId, exerciseId: exerciseId, period: period)),
    );

    return progressionAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (progression) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExerciseProgressionChart(
            progression: progression,
            labels: chartLabels,
            localeName: localeName,
          ),
          const SizedBox(height: 14),
          PersonalRecordsList(
            records: progression.personalRecords,
            labels: personalRecordsLabels,
          ),
        ],
      ),
    );
  }
}

// ── Period selector ──────────────────────────────────────────────────────────

/// [AD7] Hevy-style period selector pill — tap to pick [ChartPeriod.last30d]
/// (default) / [ChartPeriod.thisWeek] / [ChartPeriod.month].
class ChartPeriodSelector extends StatelessWidget {
  const ChartPeriodSelector({
    super.key,
    required this.selected,
    required this.labels,
    required this.onSelect,
  });

  final ChartPeriod selected;
  final ChartPeriodLabels labels;
  final void Function(ChartPeriod) onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return PopupMenuButton<ChartPeriod>(
      initialValue: selected,
      onSelected: onSelect,
      color: palette.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: palette.border),
      ),
      itemBuilder: (context) => ChartPeriod.values
          .map(
            (p) => PopupMenuItem<ChartPeriod>(
              value: p,
              child: Text(
                labels.labelFor(p),
                style: GoogleFonts.barlow(
                  fontSize: 13,
                  fontWeight: p == selected ? FontWeight.w700 : FontWeight.w400,
                  color: p == selected ? palette.accent : palette.textPrimary,
                ),
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              labels.labelFor(selected),
              style: GoogleFonts.barlow(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(TreinoIcon.chevronDown, size: 14, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}

// ── Search field ──────────────────────────────────────────────────────────────

/// Campo de búsqueda del picker de progresión.
///
/// Filtra SÓLO los ejercicios que el atleta registró — nunca el catálogo. Por
/// eso no reusa `exercise_picker_sheet.dart`: aquél busca sobre los 429
/// ejercicios del catálogo público + los custom, porque su trabajo es "elegir
/// un ejercicio para AGREGAR a una rutina". Acá el universo es otro: "elegir
/// entre los ejercicios que YA entrenaste", y uno que nunca hiciste no tiene
/// progresión que mostrar. Ver el ADR en
/// `openspec/changes/exercise-progression/proposal.md` (scope b).
class _ExerciseSearchField extends StatelessWidget {
  const _ExerciseSearchField({
    required this.hintText,
    required this.onChanged,
  });

  final String hintText;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return TextField(
      onChanged: onChanged,
      style: GoogleFonts.barlow(fontSize: 14, color: palette.textPrimary),
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        hintStyle: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
        prefixIcon: Icon(TreinoIcon.search, size: 18, color: palette.textMuted),
        filled: true,
        fillColor: palette.bg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.accent),
        ),
      ),
    );
  }
}
