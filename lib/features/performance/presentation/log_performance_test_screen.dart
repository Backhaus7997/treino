import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../application/performance_test_providers.dart';
import '../domain/performance_test.dart';

// ── Month names (Spanish, no lib dependency) ──────────────────────────────────

const _kMonths = <String>[
  '',
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

String _formatDateTimeEs(DateTime dt) {
  final local = dt.toLocal();
  final d = local.day;
  final m = _kMonths[local.month];
  final y = local.year;
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$d $m $y · $hh:$mm';
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
  bool _saving = false;

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
  }

  @override
  void dispose() {
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

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_saving) return;
    final trainerUid = ref.read(currentUidProvider);
    if (trainerUid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No hay sesión activa. No se puede guardar.',
          ),
        ),
      );
      return;
    }

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
        const SnackBar(content: Text('Evaluación guardada')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No pudimos guardar la evaluación. Probá de nuevo.',
          ),
        ),
      );
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final trainerUid = ref.watch(currentUidProvider);
    final canSave = trainerUid != null && !_saving;
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
                        'Cargar evaluación',
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: palette.textPrimary,
                        ),
                      ),
                      Text(
                        _formatDateTimeEs(now),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── SALTOS ───────────────────────────────────────────────
                    _sectionLabel('SALTOS (cm)', palette),
                    const SizedBox(height: 12),
                    _numericField(
                      label: 'CMJ',
                      controller: _cmjCtrl,
                      palette: palette,
                      suffix: 'cm',
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: 'Squat Jump',
                      controller: _squatJumpCtrl,
                      palette: palette,
                      suffix: 'cm',
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: 'Abalakov',
                      controller: _abalakovCtrl,
                      palette: palette,
                      suffix: 'cm',
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: 'Salto largo',
                      controller: _broadJumpCtrl,
                      palette: palette,
                      suffix: 'cm',
                    ),
                    const SizedBox(height: 20),

                    // ── VELOCIDAD ────────────────────────────────────────────
                    _sectionLabel('VELOCIDAD (seg)', palette),
                    const SizedBox(height: 12),
                    _numericField(
                      label: 'Sprint 10m',
                      controller: _sprint10Ctrl,
                      palette: palette,
                      suffix: 's',
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: '20m',
                      controller: _sprint20Ctrl,
                      palette: palette,
                      suffix: 's',
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: '30m',
                      controller: _sprint30Ctrl,
                      palette: palette,
                      suffix: 's',
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: '40m',
                      controller: _sprint40Ctrl,
                      palette: palette,
                      suffix: 's',
                    ),
                    const SizedBox(height: 20),

                    // ── FUERZA 1RM ───────────────────────────────────────────
                    _sectionLabel('FUERZA 1RM (kg)', palette),
                    const SizedBox(height: 12),
                    _numericField(
                      label: 'Sentadilla',
                      controller: _squat1rmCtrl,
                      palette: palette,
                      suffix: 'kg',
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: 'Press banca',
                      controller: _benchPress1rmCtrl,
                      palette: palette,
                      suffix: 'kg',
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: 'Peso muerto',
                      controller: _deadlift1rmCtrl,
                      palette: palette,
                      suffix: 'kg',
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: 'Press militar',
                      controller: _overheadPress1rmCtrl,
                      palette: palette,
                      suffix: 'kg',
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: 'Dominada lastrada',
                      controller: _pullUp1rmCtrl,
                      palette: palette,
                      suffix: 'kg',
                    ),
                    const SizedBox(height: 20),

                    // ── RESISTENCIA / OTROS ──────────────────────────────────
                    _sectionLabel('RESISTENCIA / OTROS', palette),
                    const SizedBox(height: 12),
                    _numericField(
                      label: 'VO2máx',
                      controller: _vo2maxCtrl,
                      palette: palette,
                      suffix: 'ml/kg/min',
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: 'Course Navette (nivel)',
                      controller: _courseNavetteCtrl,
                      palette: palette,
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: 'Cooper',
                      controller: _cooperCtrl,
                      palette: palette,
                      suffix: 'm',
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: 'Flexibilidad sit-and-reach',
                      controller: _sitAndReachCtrl,
                      palette: palette,
                      suffix: 'cm',
                    ),
                    const SizedBox(height: 20),

                    // ── NOTAS ────────────────────────────────────────────────
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
                        hint: 'Observaciones del entrenador…',
                      ),
                    ),

                    // Space so pinned button doesn't cover last field
                    const SizedBox(height: 80),
                  ],
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
                          'GUARDAR EVALUACIÓN',
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
