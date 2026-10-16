import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/utils/date_labels.dart';
import '../../../core/utils/kg_format.dart';
import '../../../core/widgets/motion/treino_success_check.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../core/utils/metric_range.dart';
import '../../../core/utils/metric_range_message.dart';
import '../../../l10n/app_l10n.dart';
import '../domain/measurement_ranges.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../application/measurement_providers.dart';
import '../domain/measurement.dart';

/// Upper sanity bound for any logged metric (kg, %, or cm).
///
/// Rejects any character that cannot be part of a decimal metric at entry
/// time, so the user never types a value that would be silently dropped.
final List<TextInputFormatter> _decimalInputFormatters = <TextInputFormatter>[
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
];

String _formatDateTimeEs(DateTime dt, String localeName) {
  final local = dt.toLocal();
  final d = local.day;
  final m = monthAbbrev(local, localeName);
  final y = local.year;
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$d $m $y · $hh:$mm';
}

// ── Screen ────────────────────────────────────────────────────────────────────

/// Full-screen dialog to log a new [Measurement] for [athleteId], or — when
/// [initial] is set — to EDIT an existing one (#439).
///
/// Opened via:
/// ```dart
/// Navigator.of(context).push(MaterialPageRoute(
///   fullscreenDialog: true,
///   builder: (_) => LogMeasurementScreen(athleteId: athleteId),
/// ));
/// ```
///
/// All fields are optional — whoever logs saves whatever metrics they measured.
///
/// Two authoring modes (design ADR-ASM-6):
/// - default [LogMeasurementScreen] — a TRAINER logging FOR [athleteId]
///   (`recordedBy = uid`, `athleteId = the passed athlete`).
/// - [LogMeasurementScreen.selfLog] — an ATHLETE logging their OWN measurement.
///   [athleteId] is null and the effective athleteId is derived from the
///   authenticated uid at save time, so the caller cannot inject someone
///   else's id → the write is always `recordedBy == athleteId == uid`, exactly
///   what the create rule's athlete-self branch requires.
///
/// Edit mode ([initial] != null) pre-populates every field and saves via
/// `update()` preserving `id`/`athleteId`/`recordedBy`/`recordedAt` — the
/// update rule pins the first three, and the measurement keeps its original
/// point on the chart timeline. Only the author may edit (the update rule
/// requires `recordedBy == uid`), so callers must gate the affordance on
/// `initial.recordedBy == currentUid`.
enum _LogAuthorMode { trainerForAthlete, athleteSelf }

class LogMeasurementScreen extends ConsumerStatefulWidget {
  /// Trainer logging FOR an athlete (existing behavior), or editing a
  /// measurement they recorded when [initial] is set.
  const LogMeasurementScreen({super.key, required this.athleteId, this.initial})
      : _mode = _LogAuthorMode.trainerForAthlete;

  /// Athlete logging their OWN measurement. `athleteId` resolves from the
  /// authenticated uid at save time. With [initial], edits a self-logged one.
  const LogMeasurementScreen.selfLog({super.key, this.initial})
      : athleteId = null,
        _mode = _LogAuthorMode.athleteSelf;

  /// The subject athlete in trainer mode; null in self mode (derived from uid).
  final String? athleteId;

  /// When set, the form edits THIS measurement instead of creating a new one.
  final Measurement? initial;
  final _LogAuthorMode _mode;

  @override
  ConsumerState<LogMeasurementScreen> createState() =>
      _LogMeasurementScreenState();
}

class _LogMeasurementScreenState extends ConsumerState<LogMeasurementScreen> {
  // ── Body composition ───────────────────────────────────────────────────────
  late final TextEditingController _weightCtrl;
  late final TextEditingController _fatCtrl;
  late final TextEditingController _muscleCtrl;

  // ── Trunk ──────────────────────────────────────────────────────────────────
  late final TextEditingController _shouldersCtrl;
  late final TextEditingController _chestCtrl;
  late final TextEditingController _waistCtrl;
  late final TextEditingController _hipsCtrl;
  late final TextEditingController _glutesCtrl;

  // ── Upper body bilateral ───────────────────────────────────────────────────
  late final TextEditingController _bicepsLCtrl;
  late final TextEditingController _bicepsRCtrl;
  late final TextEditingController _bicepsFlexLCtrl;
  late final TextEditingController _bicepsFlexRCtrl;
  late final TextEditingController _forearmLCtrl;
  late final TextEditingController _forearmRCtrl;

  // ── Lower body bilateral ───────────────────────────────────────────────────
  late final TextEditingController _upperThighLCtrl;
  late final TextEditingController _upperThighRCtrl;
  late final TextEditingController _midThighLCtrl;
  late final TextEditingController _midThighRCtrl;
  late final TextEditingController _calfLCtrl;
  late final TextEditingController _calfRCtrl;

  // ── Notes ──────────────────────────────────────────────────────────────────
  late final TextEditingController _notesCtrl;

  // ── State ──────────────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  /// Owned by the parent so a save attempt can force the circumferences
  /// section open when one of its (collapsed) fields fails validation —
  /// otherwise the inline error would render off-screen.
  bool _circumferencesExpanded = false;

  /// Tracks whether the form currently has at least one value, so GUARDAR can
  /// be disabled live as the user types/clears fields (error prevention).
  bool _hasValue = false;

  /// Hay al menos un campo fuera de rango o no numérico (#1483).
  bool _hasInvalid = false;

  /// Every controller on the form — used to wire change listeners and to
  /// recompute [_hasValue] on each edit.
  late final List<TextEditingController> _allCtrls;

  @override
  void initState() {
    super.initState();
    // Edit mode: pre-populate every field from the measurement being edited.
    // formatWeightKg renders the exact value with no redundant `.0` and maps
    // null → '' (empty field) — the same prefill contract set editors use.
    final i = widget.initial;
    _weightCtrl = TextEditingController(text: formatWeightKg(i?.weightKg));
    _fatCtrl = TextEditingController(text: formatWeightKg(i?.fatPercentage));
    _muscleCtrl = TextEditingController(text: formatWeightKg(i?.muscleMassKg));
    _shouldersCtrl =
        TextEditingController(text: formatWeightKg(i?.shouldersCm));
    _chestCtrl = TextEditingController(text: formatWeightKg(i?.chestCm));
    _waistCtrl = TextEditingController(text: formatWeightKg(i?.waistCm));
    _hipsCtrl = TextEditingController(text: formatWeightKg(i?.hipsCm));
    _glutesCtrl = TextEditingController(text: formatWeightKg(i?.glutesCm));
    _bicepsLCtrl = TextEditingController(text: formatWeightKg(i?.bicepsLCm));
    _bicepsRCtrl = TextEditingController(text: formatWeightKg(i?.bicepsRCm));
    _bicepsFlexLCtrl =
        TextEditingController(text: formatWeightKg(i?.bicepsFlexedLCm));
    _bicepsFlexRCtrl =
        TextEditingController(text: formatWeightKg(i?.bicepsFlexedRCm));
    _forearmLCtrl = TextEditingController(text: formatWeightKg(i?.forearmLCm));
    _forearmRCtrl = TextEditingController(text: formatWeightKg(i?.forearmRCm));
    _upperThighLCtrl =
        TextEditingController(text: formatWeightKg(i?.upperThighLCm));
    _upperThighRCtrl =
        TextEditingController(text: formatWeightKg(i?.upperThighRCm));
    _midThighLCtrl =
        TextEditingController(text: formatWeightKg(i?.midThighLCm));
    _midThighRCtrl =
        TextEditingController(text: formatWeightKg(i?.midThighRCm));
    _calfLCtrl = TextEditingController(text: formatWeightKg(i?.calfLCm));
    _calfRCtrl = TextEditingController(text: formatWeightKg(i?.calfRCm));
    _notesCtrl = TextEditingController(text: i?.notes ?? '');

    _allCtrls = <TextEditingController>[
      _weightCtrl,
      _fatCtrl,
      _muscleCtrl,
      _shouldersCtrl,
      _chestCtrl,
      _waistCtrl,
      _hipsCtrl,
      _glutesCtrl,
      _bicepsLCtrl,
      _bicepsRCtrl,
      _bicepsFlexLCtrl,
      _bicepsFlexRCtrl,
      _forearmLCtrl,
      _forearmRCtrl,
      _upperThighLCtrl,
      _upperThighRCtrl,
      _midThighLCtrl,
      _midThighRCtrl,
      _calfLCtrl,
      _calfRCtrl,
      _notesCtrl,
    ];
    for (final c in _allCtrls) {
      c.addListener(_onFieldChanged);
    }

    // Edit mode starts with values already present: reflect that in the
    // GUARDAR gate, and open the circumferences section when it holds
    // prefilled data (otherwise those values would start hidden).
    _hasValue = _hasAnyValue();
    _hasInvalid = _ranges.keys.any(_isMetricInvalid);
    // Un valor viejo, válido con el tope anterior de 500 y fuera del rango
    // nuevo (el 150 % de grasa del QA), deja GUARDAR deshabilitado desde el
    // arranque. `onUserInteraction` no mostraría el error hasta que el PF
    // tocara ESE campo: validar al primer frame para que diga qué corregir.
    // Lo marcó Codex en #1524.
    if (_hasInvalid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _formKey.currentState?.validate();
      });
    }
    _circumferencesExpanded = _circumferenceCtrls.any((c) => c.text.isNotEmpty);
  }

  /// Recomputes [_hasValue] whenever any field changes so GUARDAR reflects the
  /// current form state without waiting for a submit attempt.
  void _onFieldChanged() {
    final has = _hasAnyValue();
    final invalid = _ranges.keys.any(_isMetricInvalid);
    if (has != _hasValue || invalid != _hasInvalid) {
      setState(() {
        _hasValue = has;
        _hasInvalid = invalid;
      });
    }
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _fatCtrl.dispose();
    _muscleCtrl.dispose();
    _shouldersCtrl.dispose();
    _chestCtrl.dispose();
    _waistCtrl.dispose();
    _hipsCtrl.dispose();
    _glutesCtrl.dispose();
    _bicepsLCtrl.dispose();
    _bicepsRCtrl.dispose();
    _bicepsFlexLCtrl.dispose();
    _bicepsFlexRCtrl.dispose();
    _forearmLCtrl.dispose();
    _forearmRCtrl.dispose();
    _upperThighLCtrl.dispose();
    _upperThighRCtrl.dispose();
    _midThighLCtrl.dispose();
    _midThighRCtrl.dispose();
    _calfLCtrl.dispose();
    _calfRCtrl.dispose();
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

  /// Rango de cada campo numérico (#1483). Los bilaterales comparten rango.
  late final Map<TextEditingController, MetricRange> _ranges = {
    _weightCtrl: MeasurementRanges.weightKg,
    _fatCtrl: MeasurementRanges.fatPercentage,
    _muscleCtrl: MeasurementRanges.muscleMassKg,
    _shouldersCtrl: MeasurementRanges.shouldersCm,
    _chestCtrl: MeasurementRanges.chestCm,
    _waistCtrl: MeasurementRanges.waistCm,
    _hipsCtrl: MeasurementRanges.hipsCm,
    _glutesCtrl: MeasurementRanges.glutesCm,
    _bicepsLCtrl: MeasurementRanges.bicepsCm,
    _bicepsRCtrl: MeasurementRanges.bicepsCm,
    _bicepsFlexLCtrl: MeasurementRanges.bicepsCm,
    _bicepsFlexRCtrl: MeasurementRanges.bicepsCm,
    _forearmLCtrl: MeasurementRanges.forearmCm,
    _forearmRCtrl: MeasurementRanges.forearmCm,
    _upperThighLCtrl: MeasurementRanges.thighCm,
    _upperThighRCtrl: MeasurementRanges.thighCm,
    _midThighLCtrl: MeasurementRanges.thighCm,
    _midThighRCtrl: MeasurementRanges.thighCm,
    _calfLCtrl: MeasurementRanges.calfCm,
    _calfRCtrl: MeasurementRanges.calfCm,
  };

  /// Validator de un campo contra su [range]. Vacío es válido (todos los
  /// campos son opcionales); un valor no numérico o fuera de rango muestra el
  /// error inline en vez de anularse en silencio.
  FormFieldValidator<String> _validatorFor(MetricRange range, AppL10n l10n) =>
      (value) => metricRangeError(range, value, l10n);

  /// True when [ctrl] holds a non-empty value outside its range or not a
  /// number. Covers the collapsed circumferences section too, whose fields
  /// are unmounted and therefore skipped by `Form.validate()`.
  bool _isMetricInvalid(TextEditingController ctrl) =>
      _ranges[ctrl]!.check(ctrl.text).isError;

  /// All circumference controllers (the collapsible section). Kept separate so
  /// the section can be force-expanded when one of them holds invalid input.
  List<TextEditingController> get _circumferenceCtrls =>
      <TextEditingController>[
        _shouldersCtrl,
        _chestCtrl,
        _waistCtrl,
        _hipsCtrl,
        _glutesCtrl,
        _bicepsLCtrl,
        _bicepsRCtrl,
        _bicepsFlexLCtrl,
        _bicepsFlexRCtrl,
        _forearmLCtrl,
        _forearmRCtrl,
        _upperThighLCtrl,
        _upperThighRCtrl,
        _midThighLCtrl,
        _midThighRCtrl,
        _calfLCtrl,
        _calfRCtrl,
      ];

  /// True when at least one numeric field parses to a value or notes is filled.
  /// Guards against persisting a fully-null measurement document.
  bool _hasAnyValue() {
    final numericCtrls = <TextEditingController>[
      _weightCtrl,
      _fatCtrl,
      _muscleCtrl,
      _shouldersCtrl,
      _chestCtrl,
      _waistCtrl,
      _hipsCtrl,
      _glutesCtrl,
      _bicepsLCtrl,
      _bicepsRCtrl,
      _bicepsFlexLCtrl,
      _bicepsFlexRCtrl,
      _forearmLCtrl,
      _forearmRCtrl,
      _upperThighLCtrl,
      _upperThighRCtrl,
      _midThighLCtrl,
      _midThighRCtrl,
      _calfLCtrl,
      _calfRCtrl,
    ];
    final hasNumeric = numericCtrls.any((c) => _parseDouble(c) != null);
    return hasNumeric || _notesCtrl.text.trim().isNotEmpty;
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppL10n.of(context);
    final uid = ref.read(currentUidProvider);
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.measurementLogNoSession)),
      );
      return;
    }

    // Effective subject: self mode ALWAYS uses the authenticated uid (the
    // caller cannot inject another athleteId), trainer mode uses the passed id.
    // In self mode this guarantees `athleteId == recordedBy == uid`, the exact
    // invariant the create rule's athlete-self branch enforces.
    final effectiveAthleteId =
        widget._mode == _LogAuthorMode.athleteSelf ? uid : widget.athleteId!;
    assert(
      widget._mode != _LogAuthorMode.athleteSelf || effectiveAthleteId == uid,
      'self-log must attribute the measurement to the authenticated athlete',
    );

    // If a collapsed circumference holds an invalid value, expand the section
    // first so its inline error is actually visible before we validate.
    if (!_circumferencesExpanded && _circumferenceCtrls.any(_isMetricInvalid)) {
      setState(() => _circumferencesExpanded = true);
      // Let the section mount before its fields' validators run.
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
    }

    // Reject invalid / out-of-range entries before building the model so a
    // mistyped value is surfaced inline instead of being silently dropped.
    if (!(_formKey.currentState?.validate() ?? true)) return;

    if (!_hasAnyValue()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.logEmptyRecordWarning)),
      );
      return;
    }

    setState(() => _saving = true);

    // Edit mode: keep id/athleteId/recordedBy (the update rule pins them) and
    // the original recordedAt (editing values must not move the point on the
    // chart timeline). Create mode: fresh doc attributed to the current uid.
    final initial = widget.initial;
    assert(
      initial == null || initial.recordedBy == uid,
      'only the author may edit a measurement (update rule pins recordedBy)',
    );
    final measurement = Measurement(
      id: initial?.id ?? '',
      athleteId: initial?.athleteId ?? effectiveAthleteId,
      recordedBy: initial?.recordedBy ?? uid,
      recordedAt: initial?.recordedAt ?? DateTime.now().toUtc(),
      weightKg: _parseDouble(_weightCtrl),
      fatPercentage: _parseDouble(_fatCtrl),
      muscleMassKg: _parseDouble(_muscleCtrl),
      shouldersCm: _parseDouble(_shouldersCtrl),
      chestCm: _parseDouble(_chestCtrl),
      waistCm: _parseDouble(_waistCtrl),
      hipsCm: _parseDouble(_hipsCtrl),
      glutesCm: _parseDouble(_glutesCtrl),
      bicepsLCm: _parseDouble(_bicepsLCtrl),
      bicepsRCm: _parseDouble(_bicepsRCtrl),
      bicepsFlexedLCm: _parseDouble(_bicepsFlexLCtrl),
      bicepsFlexedRCm: _parseDouble(_bicepsFlexRCtrl),
      forearmLCm: _parseDouble(_forearmLCtrl),
      forearmRCm: _parseDouble(_forearmRCtrl),
      upperThighLCm: _parseDouble(_upperThighLCtrl),
      upperThighRCm: _parseDouble(_upperThighRCtrl),
      midThighLCm: _parseDouble(_midThighLCtrl),
      midThighRCm: _parseDouble(_midThighRCtrl),
      calfLCm: _parseDouble(_calfLCtrl),
      calfRCm: _parseDouble(_calfRCtrl),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );

    try {
      final repo = ref.read(measurementRepositoryProvider);
      if (initial != null) {
        await repo.update(measurement);
      } else {
        await repo.add(measurement);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // El pop ya pasó (línea de arriba) — el check no compite con
              // ninguna navegación, solo acompaña el mensaje mientras el
              // SnackBar hace su propia entrada.
              const TreinoSuccessCheck(size: 18, strokeWidth: 2),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  initial != null
                      ? l10n.measurementLogUpdateSuccess
                      : l10n.measurementLogSaveSuccess,
                ),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.measurementLogSaveError)),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final uid = ref.watch(currentUidProvider);
    // GUARDAR stays disabled until there is at least one value to save, so an
    // accidental tap cannot persist an all-null record.
    // Y deshabilitado mientras haya un valor fuera de rango (#1483): el error
    // inline dice qué corregir.
    final canSave = uid != null && !_saving && _hasValue && !_hasInvalid;
    final isEditing = widget.initial != null;
    // Create shows "now" (the instant being recorded); edit shows the original
    // recordedAt of the measurement being corrected.
    final headerDate = widget.initial?.recordedAt ?? DateTime.now();

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
                      l10n.commonCancel,
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
                        isEditing
                            ? l10n.measurementLogTitleEdit
                            : l10n.measurementLogTitleCreate,
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: palette.textPrimary,
                        ),
                      ),
                      Text(
                        _formatDateTimeEs(headerDate, l10n.localeName),
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
              child: Form(
                key: _formKey,
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Body composition
                      _sectionLabel(
                        l10n.measurementLogSectionBodyComposition,
                        palette,
                      ),
                      const SizedBox(height: 12),
                      _numericField(
                        label: l10n.measurementLogFieldWeight,
                        controller: _weightCtrl,
                        palette: palette,
                        validator:
                            _validatorFor(MeasurementRanges.weightKg, l10n),
                      ),
                      const SizedBox(height: 12),
                      _numericField(
                        label: l10n.measurementLogFieldBodyFat,
                        controller: _fatCtrl,
                        palette: palette,
                        validator: _validatorFor(
                            MeasurementRanges.fatPercentage, l10n),
                      ),
                      const SizedBox(height: 12),
                      _numericField(
                        label: l10n.measurementLogFieldMuscleMass,
                        controller: _muscleCtrl,
                        palette: palette,
                        validator:
                            _validatorFor(MeasurementRanges.muscleMassKg, l10n),
                      ),
                      const SizedBox(height: 20),

                      // Circumferences — collapsible
                      _CircumferencesSection(
                        palette: palette,
                        validatorFor: (range) => _validatorFor(range, l10n),
                        // Un perímetro inválido no puede quedar plegado: GUARDAR
                        // está deshabilitado y el error tiene que verse.
                        expanded: _circumferencesExpanded ||
                            _circumferenceCtrls.any(_isMetricInvalid),
                        onToggle: () => setState(
                          () => _circumferencesExpanded =
                              !_circumferencesExpanded,
                        ),
                        shouldersCtrl: _shouldersCtrl,
                        chestCtrl: _chestCtrl,
                        waistCtrl: _waistCtrl,
                        hipsCtrl: _hipsCtrl,
                        glutesCtrl: _glutesCtrl,
                        bicepsLCtrl: _bicepsLCtrl,
                        bicepsRCtrl: _bicepsRCtrl,
                        bicepsFlexLCtrl: _bicepsFlexLCtrl,
                        bicepsFlexRCtrl: _bicepsFlexRCtrl,
                        forearmLCtrl: _forearmLCtrl,
                        forearmRCtrl: _forearmRCtrl,
                        upperThighLCtrl: _upperThighLCtrl,
                        upperThighRCtrl: _upperThighRCtrl,
                        midThighLCtrl: _midThighLCtrl,
                        midThighRCtrl: _midThighRCtrl,
                        calfLCtrl: _calfLCtrl,
                        calfRCtrl: _calfRCtrl,
                      ),
                      const SizedBox(height: 20),

                      // Notes
                      _sectionLabel(l10n.measurementLogSectionNotes, palette),
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
                          hint: widget._mode == _LogAuthorMode.athleteSelf
                              ? l10n.measurementsSelfLogNotesHint
                              : l10n.measurementLogNotesHint,
                        ),
                      ),

                      // Space so FAB doesn't cover last field
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
                          isEditing
                              ? l10n.measurementLogUpdateCta
                              : l10n.measurementLogSaveCta,
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
  FormFieldValidator<String>? validator,
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
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: _decimalInputFormatters,
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

// ── Bilateral L/R pair builder ────────────────────────────────────────────────

Widget _bilateralField({
  required String label,
  required TextEditingController leftCtrl,
  required TextEditingController rightCtrl,
  required AppPalette palette,
  required AppL10n l10n,
  FormFieldValidator<String>? validator,
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
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              controller: leftCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: _decimalInputFormatters,
              validator: validator,
              style: GoogleFonts.barlow(
                color: palette.textPrimary,
                fontSize: 14,
              ),
              decoration: _inputDecoration(
                palette: palette,
                hint: l10n.measurementLogBilateralLeftHint,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: rightCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: _decimalInputFormatters,
              validator: validator,
              style: GoogleFonts.barlow(
                color: palette.textPrimary,
                fontSize: 14,
              ),
              decoration: _inputDecoration(
                palette: palette,
                hint: l10n.measurementLogBilateralRightHint,
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

// ── Circumferences section ────────────────────────────────────────────────────

class _CircumferencesSection extends StatelessWidget {
  const _CircumferencesSection({
    required this.palette,
    required this.validatorFor,
    required this.expanded,
    required this.onToggle,
    required this.shouldersCtrl,
    required this.chestCtrl,
    required this.waistCtrl,
    required this.hipsCtrl,
    required this.glutesCtrl,
    required this.bicepsLCtrl,
    required this.bicepsRCtrl,
    required this.bicepsFlexLCtrl,
    required this.bicepsFlexRCtrl,
    required this.forearmLCtrl,
    required this.forearmRCtrl,
    required this.upperThighLCtrl,
    required this.upperThighRCtrl,
    required this.midThighLCtrl,
    required this.midThighRCtrl,
    required this.calfLCtrl,
    required this.calfRCtrl,
  });

  final AppPalette palette;

  /// Validator para el rango de cada campo (#1483).
  final FormFieldValidator<String> Function(MetricRange range) validatorFor;
  final bool expanded;
  final VoidCallback onToggle;
  final TextEditingController shouldersCtrl;
  final TextEditingController chestCtrl;
  final TextEditingController waistCtrl;
  final TextEditingController hipsCtrl;
  final TextEditingController glutesCtrl;
  final TextEditingController bicepsLCtrl;
  final TextEditingController bicepsRCtrl;
  final TextEditingController bicepsFlexLCtrl;
  final TextEditingController bicepsFlexRCtrl;
  final TextEditingController forearmLCtrl;
  final TextEditingController forearmRCtrl;
  final TextEditingController upperThighLCtrl;
  final TextEditingController upperThighRCtrl;
  final TextEditingController midThighLCtrl;
  final TextEditingController midThighRCtrl;
  final TextEditingController calfLCtrl;
  final TextEditingController calfRCtrl;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final l10n = AppL10n.of(context);

    return Container(
      decoration: BoxDecoration(
        color: p.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ────────────────────────────────────────────────────
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.measurementLogCircumferencesTitle,
                          style: GoogleFonts.barlowCondensed(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            letterSpacing: 1.2,
                            color: p.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.measurementLogCircumferencesHint,
                          style: GoogleFonts.barlow(
                            fontSize: 12,
                            color: p.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    expanded ? TreinoIcon.chevronUp : TreinoIcon.chevronDown,
                    color: p.textMuted,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded content ──────────────────────────────────────────────
          if (expanded) ...[
            Divider(color: p.border, height: 1, thickness: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _subGroupLabel(l10n.measurementLogGroupTrunk, p),
                  const SizedBox(height: 12),
                  _numericField(
                    label: l10n.measurementLogFieldShoulders,
                    controller: shouldersCtrl,
                    palette: p,
                    suffix: 'cm',
                    validator: validatorFor(MeasurementRanges.shouldersCm),
                  ),
                  const SizedBox(height: 12),
                  _numericField(
                    label: l10n.measurementLogFieldChest,
                    controller: chestCtrl,
                    palette: p,
                    suffix: 'cm',
                    validator: validatorFor(MeasurementRanges.chestCm),
                  ),
                  const SizedBox(height: 12),
                  _numericField(
                    label: l10n.measurementLogFieldWaist,
                    controller: waistCtrl,
                    palette: p,
                    suffix: 'cm',
                    validator: validatorFor(MeasurementRanges.waistCm),
                  ),
                  const SizedBox(height: 12),
                  _numericField(
                    label: l10n.measurementLogFieldHips,
                    controller: hipsCtrl,
                    palette: p,
                    suffix: 'cm',
                    validator: validatorFor(MeasurementRanges.hipsCm),
                  ),
                  const SizedBox(height: 12),
                  _numericField(
                    label: l10n.measurementLogFieldGlutes,
                    controller: glutesCtrl,
                    palette: p,
                    suffix: 'cm',
                    validator: validatorFor(MeasurementRanges.glutesCm),
                  ),
                  const SizedBox(height: 20),
                  _subGroupLabel(l10n.measurementLogGroupUpperBody, p),
                  const SizedBox(height: 12),
                  _bilateralField(
                    label: l10n.measurementLogFieldBiceps,
                    leftCtrl: bicepsLCtrl,
                    rightCtrl: bicepsRCtrl,
                    palette: p,
                    l10n: l10n,
                    validator: validatorFor(MeasurementRanges.bicepsCm),
                  ),
                  const SizedBox(height: 12),
                  _bilateralField(
                    label: l10n.measurementLogFieldBicepsFlexed,
                    leftCtrl: bicepsFlexLCtrl,
                    rightCtrl: bicepsFlexRCtrl,
                    palette: p,
                    l10n: l10n,
                    validator: validatorFor(MeasurementRanges.bicepsCm),
                  ),
                  const SizedBox(height: 12),
                  _bilateralField(
                    label: l10n.measurementLogFieldForearm,
                    leftCtrl: forearmLCtrl,
                    rightCtrl: forearmRCtrl,
                    palette: p,
                    l10n: l10n,
                    validator: validatorFor(MeasurementRanges.forearmCm),
                  ),
                  const SizedBox(height: 20),
                  _subGroupLabel(l10n.measurementLogGroupLowerBody, p),
                  const SizedBox(height: 12),
                  _bilateralField(
                    label: l10n.measurementLogFieldUpperThigh,
                    leftCtrl: upperThighLCtrl,
                    rightCtrl: upperThighRCtrl,
                    palette: p,
                    l10n: l10n,
                    validator: validatorFor(MeasurementRanges.thighCm),
                  ),
                  const SizedBox(height: 12),
                  _bilateralField(
                    label: l10n.measurementLogFieldMidThigh,
                    leftCtrl: midThighLCtrl,
                    rightCtrl: midThighRCtrl,
                    palette: p,
                    l10n: l10n,
                    validator: validatorFor(MeasurementRanges.thighCm),
                  ),
                  const SizedBox(height: 12),
                  _bilateralField(
                    label: l10n.measurementLogFieldCalf,
                    leftCtrl: calfLCtrl,
                    rightCtrl: calfRCtrl,
                    palette: p,
                    l10n: l10n,
                    validator: validatorFor(MeasurementRanges.calfCm),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _subGroupLabel(String label, AppPalette p) {
    return Text(
      label,
      style: GoogleFonts.barlowCondensed(
        fontWeight: FontWeight.w700,
        fontSize: 11,
        letterSpacing: 1.0,
        color: p.textMuted,
      ),
    );
  }
}
