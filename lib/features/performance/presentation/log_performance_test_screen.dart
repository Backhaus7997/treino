import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/form_scroll_to_error.dart';
import '../../../core/utils/kg_format.dart';
import '../../../core/utils/metric_range.dart';
import '../../../core/utils/metric_range_message.dart';
import '../../../l10n/app_l10n.dart';
import '../domain/performance_test_ranges.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../application/performance_test_providers.dart';
import '../domain/performance_test.dart';
import 'package:treino/core/widgets/treino_toast.dart';

// ── Date header ──────────────────────────────────────────────────────────────

/// Formats [dt] for the screen header using the active [localeName].
///
/// [PerformanceTest.recordedAt] is a real instant (persisted as
/// `DateTime.now().toUtc()`), so it must be shown in the viewer's local time —
/// same convention as `log_measurement_screen`. [intl.DateFormat.format] reads
/// the [DateTime]'s own calendar fields directly, so callers pass an already
/// `.toLocal()`-ed value; a raw UTC instant would read +3h in Argentina (#392).
String _formatDateTime(DateTime dt, String localeName) {
  final local = dt.toLocal();
  final date = intl.DateFormat('d MMM y', localeName).format(local);
  final time = intl.DateFormat('HH:mm', localeName).format(local);
  return '$date · $time';
}

// ── Screen ────────────────────────────────────────────────────────────────────

/// Full-screen dialog to log a new [PerformanceTest] for [athleteId].
///
/// Opened via:
/// ```dart
/// Navigator.of(context).push(MaterialPageRoute(
///   fullscreenDialog: true,
///   builder: (_) => LogPerformanceTestScreen(athleteId: athleteId),
/// ));
/// ```
///
/// All fields are optional — the trainer saves whatever metrics they tested.
///
/// Con [initial] EDITA una evaluación existente (#1485): pre-carga cada campo
/// y guarda con `update()` preservando `id`/`athleteId`/`recordedBy`/
/// `recordedAt` — lo que exige la regla de update de `performance_tests`.
/// Sólo el autor (`initial.recordedBy == currentUid`) llega a este modo: el
/// historial no ofrece el lápiz en filas ajenas.
class LogPerformanceTestScreen extends ConsumerStatefulWidget {
  const LogPerformanceTestScreen({
    super.key,
    required this.athleteId,
    this.initial,
  });

  final String athleteId;

  /// Evaluación a corregir; null = alta nueva.
  final PerformanceTest? initial;

  @override
  ConsumerState<LogPerformanceTestScreen> createState() =>
      _LogPerformanceTestScreenState();
}

class _LogPerformanceTestScreenState
    extends ConsumerState<LogPerformanceTestScreen> {
  // ── Saltos ─────────────────────────────────────────────────────────────────
  late final TextEditingController _cmjCtrl;
  late final TextEditingController _squatJumpCtrl;
  late final TextEditingController _abalakovCtrl;
  late final TextEditingController _broadJumpCtrl;

  // ── Velocidad ──────────────────────────────────────────────────────────────
  late final TextEditingController _sprint10Ctrl;
  late final TextEditingController _sprint20Ctrl;
  late final TextEditingController _sprint30Ctrl;
  late final TextEditingController _sprint40Ctrl;

  // ── Fuerza 1RM ────────────────────────────────────────────────────────────
  late final TextEditingController _squat1rmCtrl;
  late final TextEditingController _benchPress1rmCtrl;
  late final TextEditingController _deadlift1rmCtrl;
  late final TextEditingController _overheadPress1rmCtrl;
  late final TextEditingController _pullUp1rmCtrl;

  // ── Resistencia / otros ───────────────────────────────────────────────────
  late final TextEditingController _vo2maxCtrl;
  late final TextEditingController _courseNavetteCtrl;
  late final TextEditingController _cooperCtrl;
  late final TextEditingController _sitAndReachCtrl;

  // ── Notes ──────────────────────────────────────────────────────────────────
  late final TextEditingController _notesCtrl;

  // ── State ──────────────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  bool _hasAnyMetric = false;

  /// Hay al menos una métrica fuera de rango o no numérica (#1485).
  bool _hasInvalid = false;

  /// Las notas tienen texto. Sólo cuenta en edición — ver [_hasContent].
  bool _hasNotes = false;

  /// Every metric controller (excludes [_notesCtrl]) — used to detect whether
  /// at least one metric has a value so empty evaluations can't be saved.
  late final List<TextEditingController> _metricCtrls;

  @override
  void initState() {
    super.initState();
    // Edición (#1485): cada campo arranca con el valor guardado, sin ".0".
    final i = widget.initial;
    _cmjCtrl = TextEditingController(text: formatWeightKg(i?.cmjCm));
    _squatJumpCtrl =
        TextEditingController(text: formatWeightKg(i?.squatJumpCm));
    _abalakovCtrl = TextEditingController(text: formatWeightKg(i?.abalakovCm));
    _broadJumpCtrl =
        TextEditingController(text: formatWeightKg(i?.broadJumpCm));
    _sprint10Ctrl = TextEditingController(text: formatWeightKg(i?.sprint10mS));
    _sprint20Ctrl = TextEditingController(text: formatWeightKg(i?.sprint20mS));
    _sprint30Ctrl = TextEditingController(text: formatWeightKg(i?.sprint30mS));
    _sprint40Ctrl = TextEditingController(text: formatWeightKg(i?.sprint40mS));
    _squat1rmCtrl = TextEditingController(text: formatWeightKg(i?.squat1rmKg));
    _benchPress1rmCtrl =
        TextEditingController(text: formatWeightKg(i?.benchPress1rmKg));
    _deadlift1rmCtrl =
        TextEditingController(text: formatWeightKg(i?.deadlift1rmKg));
    _overheadPress1rmCtrl =
        TextEditingController(text: formatWeightKg(i?.overheadPress1rmKg));
    _pullUp1rmCtrl =
        TextEditingController(text: formatWeightKg(i?.pullUp1rmKg));
    _vo2maxCtrl = TextEditingController(text: formatWeightKg(i?.vo2maxMlKgMin));
    _courseNavetteCtrl =
        TextEditingController(text: formatWeightKg(i?.courseNavetteLevel));
    _cooperCtrl = TextEditingController(text: formatWeightKg(i?.cooperMeters));
    _sitAndReachCtrl =
        TextEditingController(text: formatWeightKg(i?.sitAndReachCm));
    _notesCtrl = TextEditingController(text: i?.notes ?? '');

    _metricCtrls = [
      _cmjCtrl,
      _squatJumpCtrl,
      _abalakovCtrl,
      _broadJumpCtrl,
      _sprint10Ctrl,
      _sprint20Ctrl,
      _sprint30Ctrl,
      _sprint40Ctrl,
      _squat1rmCtrl,
      _benchPress1rmCtrl,
      _deadlift1rmCtrl,
      _overheadPress1rmCtrl,
      _pullUp1rmCtrl,
      _vo2maxCtrl,
      _courseNavetteCtrl,
      _cooperCtrl,
      _sitAndReachCtrl,
    ];
    for (final ctrl in _metricCtrls) {
      ctrl.addListener(_recomputeHasAnyMetric);
    }
    _notesCtrl.addListener(_recomputeHasAnyMetric);
    _hasNotes = _notesCtrl.text.trim().isNotEmpty;
    // En edición los campos ya traen valores: GUARDAR tiene que reflejarlo
    // desde el primer frame.
    _hasAnyMetric = _metricCtrls.any((c) => c.text.trim().isNotEmpty);
    _hasInvalid = _metricCtrls.any((c) => _ranges[c]!.check(c.text).isError);
    // Un valor viejo fuera de rango (el CMJ de 999 del QA) deja GUARDAR
    // deshabilitado; `onUserInteraction` no mostraría el error hasta tocar ESE
    // campo. Validar al primer frame para que diga qué corregir (Codex, #1524).
    if (_hasInvalid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _formKey.currentState?.validate();
      });
    }
  }

  /// Recomputes whether any metric field is non-empty so the Save button
  /// reflects it. Cheap string check; only calls [setState] on a real change.
  void _recomputeHasAnyMetric() {
    final hasAny = _metricCtrls.any((c) => c.text.trim().isNotEmpty);
    final invalid = _metricCtrls.any((c) => _ranges[c]!.check(c.text).isError);
    final notes = _notesCtrl.text.trim().isNotEmpty;
    if (hasAny != _hasAnyMetric ||
        invalid != _hasInvalid ||
        notes != _hasNotes) {
      setState(() {
        _hasAnyMetric = hasAny;
        _hasInvalid = invalid;
        _hasNotes = notes;
      });
    }
  }

  /// Hay algo que guardar. Un ALTA exige al menos una métrica (una evaluación
  /// vacía no aporta nada). Una EDICIÓN acepta también sólo notas: el Coach
  /// Hub crea evaluaciones con todos los campos opcionales, y sin esto el
  /// lápiz del historial abría un form que nunca habilitaba GUARDAR (Codex,
  /// #1532).
  bool get _hasContent =>
      _hasAnyMetric || (widget.initial != null && _hasNotes);

  @override
  void dispose() {
    for (final ctrl in _metricCtrls) {
      ctrl.removeListener(_recomputeHasAnyMetric);
    }
    _notesCtrl.removeListener(_recomputeHasAnyMetric);
    _cmjCtrl.dispose();
    _squatJumpCtrl.dispose();
    _abalakovCtrl.dispose();
    _broadJumpCtrl.dispose();
    _sprint10Ctrl.dispose();
    _sprint20Ctrl.dispose();
    _sprint30Ctrl.dispose();
    _sprint40Ctrl.dispose();
    _squat1rmCtrl.dispose();
    _benchPress1rmCtrl.dispose();
    _deadlift1rmCtrl.dispose();
    _overheadPress1rmCtrl.dispose();
    _pullUp1rmCtrl.dispose();
    _vo2maxCtrl.dispose();
    _courseNavetteCtrl.dispose();
    _cooperCtrl.dispose();
    _sitAndReachCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Parses a controller value to double — null if empty or invalid.
  double? _parseDouble(TextEditingController ctrl) {
    final raw = ctrl.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  /// Rango de cada métrica (#1485).
  late final Map<TextEditingController, MetricRange> _ranges = {
    _cmjCtrl: PerformanceTestRanges.verticalJumpCm,
    _squatJumpCtrl: PerformanceTestRanges.verticalJumpCm,
    _abalakovCtrl: PerformanceTestRanges.verticalJumpCm,
    _broadJumpCtrl: PerformanceTestRanges.broadJumpCm,
    _sprint10Ctrl: PerformanceTestRanges.sprint10mS,
    _sprint20Ctrl: PerformanceTestRanges.sprint20mS,
    _sprint30Ctrl: PerformanceTestRanges.sprint30mS,
    _sprint40Ctrl: PerformanceTestRanges.sprint40mS,
    _squat1rmCtrl: PerformanceTestRanges.oneRepMaxKg,
    _benchPress1rmCtrl: PerformanceTestRanges.oneRepMaxKg,
    _deadlift1rmCtrl: PerformanceTestRanges.oneRepMaxKg,
    _overheadPress1rmCtrl: PerformanceTestRanges.oneRepMaxKg,
    _pullUp1rmCtrl: PerformanceTestRanges.pullUpLoadKg,
    _vo2maxCtrl: PerformanceTestRanges.vo2maxMlKgMin,
    _courseNavetteCtrl: PerformanceTestRanges.courseNavetteLevel,
    _cooperCtrl: PerformanceTestRanges.cooperMeters,
    _sitAndReachCtrl: PerformanceTestRanges.sitAndReachCm,
  };

  /// Validator de un campo contra su rango. Vacío es válido (todos los campos
  /// son opcionales); un typo como `12.x.3` o un CMJ de 999 cm muestra el
  /// error inline en vez de guardarse.
  FormFieldValidator<String> _validatorFor(TextEditingController ctrl) =>
      (value) => metricRangeError(_ranges[ctrl]!, value, AppL10n.of(context));

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppL10n.of(context);
    final trainerUid = ref.read(currentUidProvider);
    if (trainerUid == null) {
      showTreinoToast(
        context,
        l10n.performanceLogNoSession,
        type: TreinoToastType.error,
      );
      return;
    }

    // Block empty evaluations: at least one metric must be filled before save.
    // The Save button is already disabled while [_hasAnyMetric] is false
    // (see `canSave` in build), so this is a defensive guard only.
    if (!_hasContent) return;

    // Surface inline errors for any non-numeric / non-positive field instead of
    // silently dropping the value via tryParse.
    if (!validateAndRevealFirstError(_formKey)) return;

    setState(() => _saving = true);

    final initial = widget.initial;
    assert(
      initial == null || initial.recordedBy == trainerUid,
      'sólo el autor edita: la regla de update pinea recordedBy',
    );
    // Edición: id, alumno, autor y fecha se conservan — la regla de update
    // rechaza cualquier cambio de athleteId/recordedBy, y corregir un valor
    // no mueve el punto en la línea de tiempo.
    final test = PerformanceTest(
      id: initial?.id ?? '',
      athleteId: initial?.athleteId ?? widget.athleteId,
      recordedBy: initial?.recordedBy ?? trainerUid,
      recordedAt: initial?.recordedAt ?? DateTime.now().toUtc(),
      cmjCm: _parseDouble(_cmjCtrl),
      squatJumpCm: _parseDouble(_squatJumpCtrl),
      abalakovCm: _parseDouble(_abalakovCtrl),
      broadJumpCm: _parseDouble(_broadJumpCtrl),
      sprint10mS: _parseDouble(_sprint10Ctrl),
      sprint20mS: _parseDouble(_sprint20Ctrl),
      sprint30mS: _parseDouble(_sprint30Ctrl),
      sprint40mS: _parseDouble(_sprint40Ctrl),
      squat1rmKg: _parseDouble(_squat1rmCtrl),
      benchPress1rmKg: _parseDouble(_benchPress1rmCtrl),
      deadlift1rmKg: _parseDouble(_deadlift1rmCtrl),
      overheadPress1rmKg: _parseDouble(_overheadPress1rmCtrl),
      pullUp1rmKg: _parseDouble(_pullUp1rmCtrl),
      vo2maxMlKgMin: _parseDouble(_vo2maxCtrl),
      courseNavetteLevel: _parseDouble(_courseNavetteCtrl),
      cooperMeters: _parseDouble(_cooperCtrl),
      sitAndReachCm: _parseDouble(_sitAndReachCtrl),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );

    try {
      final repo = ref.read(performanceTestRepositoryProvider);
      if (initial != null) {
        await repo.update(test);
      } else {
        await repo.add(test);
      }
      if (!mounted) return;
      // Messenger capturado ANTES del pop: después la pantalla se desmonta.
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      showTreinoToastOn(
        messenger,
        initial != null
            ? l10n.performanceLogUpdateSuccess
            : l10n.performanceLogSaveSuccess,
        type: TreinoToastType.success,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      showTreinoToast(
        context,
        l10n.performanceLogSaveError,
        type: TreinoToastType.error,
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final trainerUid = ref.watch(currentUidProvider);
    // Deshabilitado mientras haya un valor fuera de rango (#1485).
    final canSave =
        trainerUid != null && !_saving && _hasContent && !_hasInvalid;
    // Real instant; _formatDateTime localizes it for display (#392). The record
    // is still persisted as UTC in _save — same instant, shown in local time.
    // Alta muestra «ahora»; edición, la fecha original de la evaluación.
    final now = widget.initial?.recordedAt ?? DateTime.now();

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ─────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
              child: Row(
                children: [
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      l10n.performanceLogCancel,
                      style: GoogleFonts.barlow(
                        color: _saving ? palette.textMuted : palette.highlight,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        widget.initial != null
                            ? l10n.performanceLogTitleEdit
                            : l10n.performanceLogTitle,
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: palette.textPrimary,
                        ),
                      ),
                      Text(
                        _formatDateTime(now, l10n.localeName),
                        style: GoogleFonts.barlow(
                          fontSize: 12,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Body ────────────────────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Form(
                  key: _formKey,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── SALTOS ───────────────────────────────────────────────
                      _sectionLabel(l10n.performanceLogSectionJumps, palette),
                      const SizedBox(height: 12),
                      _numericField(
                        label: l10n.performanceLogFieldCmj,
                        controller: _cmjCtrl,
                        validator: _validatorFor(_cmjCtrl),
                        palette: palette,
                        suffix: 'cm',
                      ),
                      const SizedBox(height: 12),
                      _numericField(
                        label: l10n.performanceLogFieldSquatJump,
                        controller: _squatJumpCtrl,
                        validator: _validatorFor(_squatJumpCtrl),
                        palette: palette,
                        suffix: 'cm',
                      ),
                      const SizedBox(height: 12),
                      _numericField(
                        label: l10n.performanceLogFieldAbalakov,
                        controller: _abalakovCtrl,
                        validator: _validatorFor(_abalakovCtrl),
                        palette: palette,
                        suffix: 'cm',
                      ),
                      const SizedBox(height: 12),
                      _numericField(
                        label: l10n.performanceLogFieldBroadJump,
                        controller: _broadJumpCtrl,
                        validator: _validatorFor(_broadJumpCtrl),
                        palette: palette,
                        suffix: 'cm',
                      ),
                      const SizedBox(height: 20),

                      // ── VELOCIDAD ────────────────────────────────────────────
                      _sectionLabel(l10n.performanceLogSectionSpeed, palette),
                      const SizedBox(height: 12),
                      _numericField(
                        label: l10n.performanceLogFieldSprint10,
                        controller: _sprint10Ctrl,
                        validator: _validatorFor(_sprint10Ctrl),
                        palette: palette,
                        suffix: 's',
                      ),
                      const SizedBox(height: 12),
                      _numericField(
                        label: l10n.performanceLogFieldSprint20,
                        controller: _sprint20Ctrl,
                        validator: _validatorFor(_sprint20Ctrl),
                        palette: palette,
                        suffix: 's',
                      ),
                      const SizedBox(height: 12),
                      _numericField(
                        label: l10n.performanceLogFieldSprint30,
                        controller: _sprint30Ctrl,
                        validator: _validatorFor(_sprint30Ctrl),
                        palette: palette,
                        suffix: 's',
                      ),
                      const SizedBox(height: 12),
                      _numericField(
                        label: l10n.performanceLogFieldSprint40,
                        controller: _sprint40Ctrl,
                        validator: _validatorFor(_sprint40Ctrl),
                        palette: palette,
                        suffix: 's',
                      ),
                      const SizedBox(height: 20),

                      // ── FUERZA 1RM ───────────────────────────────────────────
                      _sectionLabel(
                          l10n.performanceLogSectionStrength, palette),
                      const SizedBox(height: 12),
                      _numericField(
                        label: l10n.performanceLogFieldSquat1rm,
                        controller: _squat1rmCtrl,
                        validator: _validatorFor(_squat1rmCtrl),
                        palette: palette,
                        suffix: 'kg',
                      ),
                      const SizedBox(height: 12),
                      _numericField(
                        label: l10n.performanceLogFieldBenchPress,
                        controller: _benchPress1rmCtrl,
                        validator: _validatorFor(_benchPress1rmCtrl),
                        palette: palette,
                        suffix: 'kg',
                      ),
                      const SizedBox(height: 12),
                      _numericField(
                        label: l10n.performanceLogFieldDeadlift,
                        controller: _deadlift1rmCtrl,
                        validator: _validatorFor(_deadlift1rmCtrl),
                        palette: palette,
                        suffix: 'kg',
                      ),
                      const SizedBox(height: 12),
                      _numericField(
                        label: l10n.performanceLogFieldOverheadPress,
                        controller: _overheadPress1rmCtrl,
                        validator: _validatorFor(_overheadPress1rmCtrl),
                        palette: palette,
                        suffix: 'kg',
                      ),
                      const SizedBox(height: 12),
                      _numericField(
                        label: l10n.performanceLogFieldPullUp,
                        controller: _pullUp1rmCtrl,
                        validator: _validatorFor(_pullUp1rmCtrl),
                        palette: palette,
                        suffix: 'kg',
                      ),
                      const SizedBox(height: 20),

                      // ── RESISTENCIA / OTROS ──────────────────────────────────
                      _sectionLabel(
                          l10n.performanceLogSectionEndurance, palette),
                      const SizedBox(height: 12),
                      _numericField(
                        label: l10n.performanceLogFieldVo2max,
                        controller: _vo2maxCtrl,
                        validator: _validatorFor(_vo2maxCtrl),
                        palette: palette,
                        suffix: 'ml/kg/min',
                      ),
                      const SizedBox(height: 12),
                      _numericField(
                        label: l10n.performanceLogFieldCourseNavette,
                        controller: _courseNavetteCtrl,
                        validator: _validatorFor(_courseNavetteCtrl),
                        palette: palette,
                      ),
                      const SizedBox(height: 12),
                      _numericField(
                        label: l10n.performanceLogFieldCooper,
                        controller: _cooperCtrl,
                        validator: _validatorFor(_cooperCtrl),
                        palette: palette,
                        suffix: 'm',
                      ),
                      const SizedBox(height: 12),
                      _numericField(
                        label: l10n.performanceLogFieldSitAndReach,
                        controller: _sitAndReachCtrl,
                        validator: _validatorFor(_sitAndReachCtrl),
                        allowNegative: true,
                        palette: palette,
                        suffix: 'cm',
                      ),
                      const SizedBox(height: 20),

                      // ── NOTAS ────────────────────────────────────────────────
                      _sectionLabel(l10n.performanceLogSectionNotes, palette),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _notesCtrl,
                        minLines: 3,
                        maxLines: 6,
                        keyboardType: TextInputType.multiline,
                        style: GoogleFonts.barlow(
                          color: palette.textPrimary,
                          fontSize: 14,
                        ),
                        decoration: _inputDecoration(
                          palette: palette,
                          hint: l10n.performanceLogNotesHint,
                        ),
                      ),

                      // Space so pinned button doesn't cover last field
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
              ),
            ),

            // ── Pinned save button ───────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: canSave ? _save : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canSave ? palette.accent : palette.border,
                    foregroundColor: TreinoButtonTokens.foreground(context),
                    disabledBackgroundColor: palette.border,
                    disabledForegroundColor: palette.textMuted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                  ),
                  child: _saving
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: TreinoButtonTokens.foreground(context),
                          ),
                        )
                      : Text(
                          widget.initial != null
                              ? l10n.performanceLogUpdateCta
                              : l10n.performanceLogSaveCta,
                          style: GoogleFonts.barlowCondensed(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            letterSpacing: 0.8,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

Widget _sectionLabel(String label, AppPalette palette) {
  return Text(
    label,
    style: GoogleFonts.barlowCondensed(
      fontWeight: FontWeight.w700,
      fontSize: 12,
      letterSpacing: 1.2,
      color: palette.textMuted,
    ),
  );
}

// ── Input decoration helper ───────────────────────────────────────────────────

InputDecoration _inputDecoration({
  required AppPalette palette,
  required String hint,
  String? suffix,
}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.barlow(
      color: palette.textMuted,
      fontSize: 14,
    ),
    suffixText: suffix,
    suffixStyle: GoogleFonts.barlow(
      color: palette.textMuted,
      fontSize: 14,
    ),
    filled: true,
    fillColor: palette.bgCard,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: BorderSide(
        color: palette.textMuted.withValues(alpha: 0.2),
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: BorderSide(
        color: palette.textMuted.withValues(alpha: 0.2),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: BorderSide(color: palette.accent),
    ),
  );
}

// ── Numeric field builder ─────────────────────────────────────────────────────

Widget _numericField({
  required String label,
  required TextEditingController controller,
  required AppPalette palette,
  String? suffix,
  String? Function(String?)? validator,
  bool allowNegative = false,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: GoogleFonts.barlow(
          color: palette.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 6),
      TextFormField(
        controller: controller,
        // `signed` en iOS cambia el teclado numérico por uno con signo menos:
        // sólo donde el rango admite negativos (sit and reach).
        keyboardType: TextInputType.numberWithOptions(
          decimal: true,
          signed: allowNegative,
        ),
        // Allow digits and decimal separators (, or .) only; blocks letters and
        // stray symbols at the keyboard level. Multiple separators (e.g.
        // '1.2.3') can still be typed, so the validator is the source of truth
        // and rejects any value double.tryParse can't read.
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            allowNegative ? RegExp(r'[-0-9.,]') : RegExp(r'[0-9.,]'),
          ),
        ],
        validator: validator,
        style: GoogleFonts.barlow(
          color: palette.textPrimary,
          fontSize: 14,
        ),
        decoration: _inputDecoration(
          palette: palette,
          hint: '0',
          suffix: suffix,
        ),
      ),
    ],
  );
}
