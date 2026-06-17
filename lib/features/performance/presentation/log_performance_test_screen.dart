import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;

import '../../../app/theme/app_palette.dart';
import '../../../l10n/app_l10n.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../application/performance_test_providers.dart';
import '../domain/performance_test.dart';

// ── Date header ──────────────────────────────────────────────────────────────

/// Formats [dt] for the screen header using the active [localeName].
///
/// Uses the same UTC convention as every reader of
/// [PerformanceTest.recordedAt] (chart `_shortDate`, athlete detail
/// `_formatMeasurementDate`): the stored UTC instant is shown as-is, with no
/// `.toLocal()`. [intl.DateFormat.format] reads the [DateTime]'s own calendar
/// fields (day/month/year/hour/minute) directly, so passing a UTC value (e.g.
/// `DateTime.now().toUtc()`) keeps the header aligned with the date that gets
/// persisted and rendered after saving, while localizing the month name.
String _formatDateTime(DateTime dt, String localeName) {
  final date = intl.DateFormat('d MMM y', localeName).format(dt);
  final time = intl.DateFormat('HH:mm', localeName).format(dt);
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
class LogPerformanceTestScreen extends ConsumerStatefulWidget {
  const LogPerformanceTestScreen({super.key, required this.athleteId});

  final String athleteId;

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

  /// Every metric controller (excludes [_notesCtrl]) — used to detect whether
  /// at least one metric has a value so empty evaluations can't be saved.
  late final List<TextEditingController> _metricCtrls;

  @override
  void initState() {
    super.initState();
    _cmjCtrl = TextEditingController();
    _squatJumpCtrl = TextEditingController();
    _abalakovCtrl = TextEditingController();
    _broadJumpCtrl = TextEditingController();
    _sprint10Ctrl = TextEditingController();
    _sprint20Ctrl = TextEditingController();
    _sprint30Ctrl = TextEditingController();
    _sprint40Ctrl = TextEditingController();
    _squat1rmCtrl = TextEditingController();
    _benchPress1rmCtrl = TextEditingController();
    _deadlift1rmCtrl = TextEditingController();
    _overheadPress1rmCtrl = TextEditingController();
    _pullUp1rmCtrl = TextEditingController();
    _vo2maxCtrl = TextEditingController();
    _courseNavetteCtrl = TextEditingController();
    _cooperCtrl = TextEditingController();
    _sitAndReachCtrl = TextEditingController();
    _notesCtrl = TextEditingController();

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
  }

  /// Recomputes whether any metric field is non-empty so the Save button
  /// reflects it. Cheap string check; only calls [setState] on a real change.
  void _recomputeHasAnyMetric() {
    final hasAny = _metricCtrls.any((c) => c.text.trim().isNotEmpty);
    if (hasAny != _hasAnyMetric) {
      setState(() => _hasAnyMetric = hasAny);
    }
  }

  @override
  void dispose() {
    for (final ctrl in _metricCtrls) {
      ctrl.removeListener(_recomputeHasAnyMetric);
    }
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

  /// Validates a numeric metric field. Empty is valid (all fields optional);
  /// non-numeric input or a non-positive value surfaces inline error text so a
  /// typo like `12.x.3` is never silently dropped. Reuses the existing generic
  /// "valid number" string — a non-parseable or non-positive measurement is not
  /// a valid value, so the same message covers both cases.
  String? _validateMetric(String? value) {
    final l10n = AppL10n.of(context);
    final raw = (value ?? '').trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    final parsed = double.tryParse(raw);
    if (parsed == null || parsed <= 0) {
      return l10n.profileEditPersonalWeightInvalidNumber;
    }
    return null;
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppL10n.of(context);
    final trainerUid = ref.read(currentUidProvider);
    if (trainerUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.performanceLogNoSession),
        ),
      );
      return;
    }

    // Block empty evaluations: at least one metric must be filled before save.
    // The Save button is already disabled while [_hasAnyMetric] is false
    // (see `canSave` in build), so this is a defensive guard only.
    if (!_hasAnyMetric) return;

    // Surface inline errors for any non-numeric / non-positive field instead of
    // silently dropping the value via tryParse.
    if (!(_formKey.currentState?.validate() ?? true)) return;

    setState(() => _saving = true);

    final test = PerformanceTest(
      id: '',
      athleteId: widget.athleteId,
      recordedBy: trainerUid,
      recordedAt: DateTime.now().toUtc(),
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
      await ref.read(performanceTestRepositoryProvider).add(test);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.performanceLogSaveSuccess)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.performanceLogSaveError),
        ),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final trainerUid = ref.watch(currentUidProvider);
    final canSave = trainerUid != null && !_saving && _hasAnyMetric;
    // Use UTC to match the persisted recordedAt (see _save) and the UTC display
    // convention of every reader, so the header date never disagrees with the
    // saved record near midnight.
    final now = DateTime.now().toUtc();

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
                        l10n.performanceLogTitle,
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
                      validator: _validateMetric,
                      palette: palette,
                      suffix: 'cm',
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: l10n.performanceLogFieldSquatJump,
                      controller: _squatJumpCtrl,
                      validator: _validateMetric,
                      palette: palette,
                      suffix: 'cm',
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: l10n.performanceLogFieldAbalakov,
                      controller: _abalakovCtrl,
                      validator: _validateMetric,
                      palette: palette,
                      suffix: 'cm',
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: l10n.performanceLogFieldBroadJump,
                      controller: _broadJumpCtrl,
                      validator: _validateMetric,
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
                      validator: _validateMetric,
                      palette: palette,
                      suffix: 's',
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: l10n.performanceLogFieldSprint20,
                      controller: _sprint20Ctrl,
                      validator: _validateMetric,
                      palette: palette,
                      suffix: 's',
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: l10n.performanceLogFieldSprint30,
                      controller: _sprint30Ctrl,
                      validator: _validateMetric,
                      palette: palette,
                      suffix: 's',
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: l10n.performanceLogFieldSprint40,
                      controller: _sprint40Ctrl,
                      validator: _validateMetric,
                      palette: palette,
                      suffix: 's',
                    ),
                    const SizedBox(height: 20),

                    // ── FUERZA 1RM ───────────────────────────────────────────
                    _sectionLabel(l10n.performanceLogSectionStrength, palette),
                    const SizedBox(height: 12),
                    _numericField(
                      label: l10n.performanceLogFieldSquat1rm,
                      controller: _squat1rmCtrl,
                      validator: _validateMetric,
                      palette: palette,
                      suffix: 'kg',
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: l10n.performanceLogFieldBenchPress,
                      controller: _benchPress1rmCtrl,
                      validator: _validateMetric,
                      palette: palette,
                      suffix: 'kg',
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: l10n.performanceLogFieldDeadlift,
                      controller: _deadlift1rmCtrl,
                      validator: _validateMetric,
                      palette: palette,
                      suffix: 'kg',
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: l10n.performanceLogFieldOverheadPress,
                      controller: _overheadPress1rmCtrl,
                      validator: _validateMetric,
                      palette: palette,
                      suffix: 'kg',
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: l10n.performanceLogFieldPullUp,
                      controller: _pullUp1rmCtrl,
                      validator: _validateMetric,
                      palette: palette,
                      suffix: 'kg',
                    ),
                    const SizedBox(height: 20),

                    // ── RESISTENCIA / OTROS ──────────────────────────────────
                    _sectionLabel(l10n.performanceLogSectionEndurance, palette),
                    const SizedBox(height: 12),
                    _numericField(
                      label: l10n.performanceLogFieldVo2max,
                      controller: _vo2maxCtrl,
                      validator: _validateMetric,
                      palette: palette,
                      suffix: 'ml/kg/min',
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: l10n.performanceLogFieldCourseNavette,
                      controller: _courseNavetteCtrl,
                      validator: _validateMetric,
                      palette: palette,
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: l10n.performanceLogFieldCooper,
                      controller: _cooperCtrl,
                      validator: _validateMetric,
                      palette: palette,
                      suffix: 'm',
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: l10n.performanceLogFieldSitAndReach,
                      controller: _sitAndReachCtrl,
                      validator: _validateMetric,
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
                          l10n.performanceLogSaveCta,
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
  String? Function(String?)? validator,
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
        // Allow digits and decimal separators (, or .) only; blocks letters and
        // stray symbols at the keyboard level. Multiple separators (e.g.
        // '1.2.3') can still be typed, so the validator is the source of truth
        // and rejects any value double.tryParse can't read.
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
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
