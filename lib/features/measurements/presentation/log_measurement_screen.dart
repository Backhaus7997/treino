import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/utils/date_labels.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../application/measurement_providers.dart';
import '../domain/measurement.dart';

/// Upper sanity bound for any logged metric (kg, %, or cm).
///
/// Caps absurd entries (e.g. 9999 kg) without rejecting realistic values:
/// the tallest measured circumferences and heaviest body weights stay well
/// under 500. Combined with the `>= 0` floor this is an error-prevention
/// guard, not a clinical range.
const double _kMaxMetricValue = 500;

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

/// Full-screen dialog to log a new [Measurement] for [athleteId].
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
enum _LogAuthorMode { trainerForAthlete, athleteSelf }

class LogMeasurementScreen extends ConsumerStatefulWidget {
  /// Trainer logging FOR an athlete (existing behavior).
  const LogMeasurementScreen({super.key, required this.athleteId})
      : _mode = _LogAuthorMode.trainerForAthlete;

  /// Athlete logging their OWN measurement. `athleteId` resolves from the
  /// authenticated uid at save time.
  const LogMeasurementScreen.selfLog({super.key})
      : athleteId = null,
        _mode = _LogAuthorMode.athleteSelf;

  /// The subject athlete in trainer mode; null in self mode (derived from uid).
  final String? athleteId;
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

  /// Every controller on the form — used to wire change listeners and to
  /// recompute [_hasValue] on each edit.
  late final List<TextEditingController> _allCtrls;

  @override
  void initState() {
    super.initState();
    _weightCtrl = TextEditingController();
    _fatCtrl = TextEditingController();
    _muscleCtrl = TextEditingController();
    _shouldersCtrl = TextEditingController();
    _chestCtrl = TextEditingController();
    _waistCtrl = TextEditingController();
    _hipsCtrl = TextEditingController();
    _glutesCtrl = TextEditingController();
    _bicepsLCtrl = TextEditingController();
    _bicepsRCtrl = TextEditingController();
    _bicepsFlexLCtrl = TextEditingController();
    _bicepsFlexRCtrl = TextEditingController();
    _forearmLCtrl = TextEditingController();
    _forearmRCtrl = TextEditingController();
    _upperThighLCtrl = TextEditingController();
    _upperThighRCtrl = TextEditingController();
    _midThighLCtrl = TextEditingController();
    _midThighRCtrl = TextEditingController();
    _calfLCtrl = TextEditingController();
    _calfRCtrl = TextEditingController();
    _notesCtrl = TextEditingController();

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
  }

  /// Recomputes [_hasValue] whenever any field changes so GUARDAR reflects the
  /// current form state without waiting for a submit attempt.
  void _onFieldChanged() {
    final has = _hasAnyValue();
    if (has != _hasValue) {
      setState(() => _hasValue = has);
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

  /// Validator for every numeric field. Empty stays valid (all fields are
  /// optional), but a non-empty value must parse and fall within sane bounds.
  /// Surfaces the error inline instead of silently nulling the value.
  String? _validateMetric(String? value, AppL10n l10n) {
    final raw = value?.trim().replaceAll(',', '.') ?? '';
    if (raw.isEmpty) return null;
    final parsed = double.tryParse(raw);
    if (parsed == null) return l10n.logFieldInvalidNumber;
    if (parsed < 0 || parsed > _kMaxMetricValue) return l10n.logFieldOutOfRange;
    return null;
  }

  /// True when [ctrl] holds a non-empty value that fails [_validateMetric].
  /// Used to detect invalid input inside the collapsed circumferences section,
  /// whose fields are unmounted and therefore skipped by `Form.validate()`.
  bool _isMetricInvalid(TextEditingController ctrl) {
    final raw = ctrl.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return false;
    final parsed = double.tryParse(raw);
    return parsed == null || parsed < 0 || parsed > _kMaxMetricValue;
  }

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
        const SnackBar(
          content: Text(
            'No hay sesión activa. No se puede guardar.',
          ),
        ),
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

    final measurement = Measurement(
      id: '',
      athleteId: effectiveAthleteId,
      recordedBy: uid,
      recordedAt: DateTime.now().toUtc(),
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
      await ref.read(measurementRepositoryProvider).add(measurement);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Medición guardada')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No pudimos guardar la medición. Probá de nuevo.',
          ),
        ),
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
    final canSave = uid != null && !_saving && _hasValue;
    final now = DateTime.now();

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
                      'Cancelar',
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
                        'Cargar medición',
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: palette.textPrimary,
                        ),
                      ),
                      Text(
                        _formatDateTimeEs(now, l10n.localeName),
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Body composition
                      _sectionLabel('COMPOSICIÓN CORPORAL', palette),
                      const SizedBox(height: 12),
                      _numericField(
                        label: 'Peso (kg)',
                        controller: _weightCtrl,
                        palette: palette,
                        validator: (v) => _validateMetric(v, l10n),
                      ),
                      const SizedBox(height: 12),
                      _numericField(
                        label: 'Grasa (%)',
                        controller: _fatCtrl,
                        palette: palette,
                        validator: (v) => _validateMetric(v, l10n),
                      ),
                      const SizedBox(height: 12),
                      _numericField(
                        label: 'Masa muscular (kg)',
                        controller: _muscleCtrl,
                        palette: palette,
                        validator: (v) => _validateMetric(v, l10n),
                      ),
                      const SizedBox(height: 20),

                      // Circumferences — collapsible
                      _CircumferencesSection(
                        palette: palette,
                        validateMetric: (v) => _validateMetric(v, l10n),
                        expanded: _circumferencesExpanded,
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
                      _sectionLabel('NOTAS', palette),
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
                              : 'Observaciones del entrenador…',
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
                    foregroundColor: palette.bg,
                    disabledBackgroundColor: palette.border,
                    disabledForegroundColor: palette.textMuted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                  child: _saving
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: palette.bg,
                          ),
                        )
                      : Text(
                          'GUARDAR MEDICIÓN',
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
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: palette.textMuted.withValues(alpha: 0.2),
      ),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
        color: palette.textMuted.withValues(alpha: 0.2),
      ),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
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
                hint: 'I (cm)',
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
                hint: 'D (cm)',
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
    required this.validateMetric,
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
  final FormFieldValidator<String> validateMetric;
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

    return Container(
      decoration: BoxDecoration(
        color: p.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ────────────────────────────────────────────────────
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CIRCUNFERENCIAS',
                          style: GoogleFonts.barlowCondensed(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            letterSpacing: 1.2,
                            color: p.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Opcional. Cargá las que quieras.',
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
                  _subGroupLabel('TRONCO', p),
                  const SizedBox(height: 12),
                  _numericField(
                    label: 'Hombros',
                    controller: shouldersCtrl,
                    palette: p,
                    suffix: 'cm',
                    validator: validateMetric,
                  ),
                  const SizedBox(height: 12),
                  _numericField(
                    label: 'Pecho',
                    controller: chestCtrl,
                    palette: p,
                    suffix: 'cm',
                    validator: validateMetric,
                  ),
                  const SizedBox(height: 12),
                  _numericField(
                    label: 'Cintura',
                    controller: waistCtrl,
                    palette: p,
                    suffix: 'cm',
                    validator: validateMetric,
                  ),
                  const SizedBox(height: 12),
                  _numericField(
                    label: 'Cadera',
                    controller: hipsCtrl,
                    palette: p,
                    suffix: 'cm',
                    validator: validateMetric,
                  ),
                  const SizedBox(height: 12),
                  _numericField(
                    label: 'Glúteos',
                    controller: glutesCtrl,
                    palette: p,
                    suffix: 'cm',
                    validator: validateMetric,
                  ),
                  const SizedBox(height: 20),
                  _subGroupLabel('TREN SUPERIOR', p),
                  const SizedBox(height: 12),
                  _bilateralField(
                    label: 'Bíceps',
                    leftCtrl: bicepsLCtrl,
                    rightCtrl: bicepsRCtrl,
                    palette: p,
                    validator: validateMetric,
                  ),
                  const SizedBox(height: 12),
                  _bilateralField(
                    label: 'Bíceps (flex)',
                    leftCtrl: bicepsFlexLCtrl,
                    rightCtrl: bicepsFlexRCtrl,
                    palette: p,
                    validator: validateMetric,
                  ),
                  const SizedBox(height: 12),
                  _bilateralField(
                    label: 'Antebrazo',
                    leftCtrl: forearmLCtrl,
                    rightCtrl: forearmRCtrl,
                    palette: p,
                    validator: validateMetric,
                  ),
                  const SizedBox(height: 20),
                  _subGroupLabel('TREN INFERIOR', p),
                  const SizedBox(height: 12),
                  _bilateralField(
                    label: 'Muslo superior',
                    leftCtrl: upperThighLCtrl,
                    rightCtrl: upperThighRCtrl,
                    palette: p,
                    validator: validateMetric,
                  ),
                  const SizedBox(height: 12),
                  _bilateralField(
                    label: 'Muslo medio',
                    leftCtrl: midThighLCtrl,
                    rightCtrl: midThighRCtrl,
                    palette: p,
                    validator: validateMetric,
                  ),
                  const SizedBox(height: 12),
                  _bilateralField(
                    label: 'Gemelo',
                    leftCtrl: calfLCtrl,
                    rightCtrl: calfRCtrl,
                    palette: p,
                    validator: validateMetric,
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
