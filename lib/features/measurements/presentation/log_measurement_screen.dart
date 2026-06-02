import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../application/measurement_providers.dart';
import '../domain/measurement.dart';

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
/// All fields are optional — the trainer saves whatever metrics they measured.
class LogMeasurementScreen extends ConsumerStatefulWidget {
  const LogMeasurementScreen({super.key, required this.athleteId});

  final String athleteId;

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
  bool _saving = false;

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

    final measurement = Measurement(
      id: '',
      athleteId: widget.athleteId,
      recordedBy: trainerUid,
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
                        'Cargar medición',
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
                    // Body composition
                    _sectionLabel('COMPOSICIÓN CORPORAL', palette),
                    const SizedBox(height: 12),
                    _numericField(
                      label: 'Peso (kg)',
                      controller: _weightCtrl,
                      palette: palette,
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: 'Grasa (%)',
                      controller: _fatCtrl,
                      palette: palette,
                    ),
                    const SizedBox(height: 12),
                    _numericField(
                      label: 'Masa muscular (kg)',
                      controller: _muscleCtrl,
                      palette: palette,
                    ),
                    const SizedBox(height: 20),

                    // Circumferences — collapsible
                    _CircumferencesSection(
                      palette: palette,
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
                        hint: 'Observaciones del entrenador…',
                      ),
                    ),

                    // Space so FAB doesn't cover last field
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

// ── Bilateral L/R pair builder ────────────────────────────────────────────────

Widget _bilateralField({
  required String label,
  required TextEditingController leftCtrl,
  required TextEditingController rightCtrl,
  required AppPalette palette,
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
        children: [
          Expanded(
            child: TextFormField(
              controller: leftCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
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

class _CircumferencesSection extends StatefulWidget {
  const _CircumferencesSection({
    required this.palette,
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
  State<_CircumferencesSection> createState() => _CircumferencesSectionState();
}

class _CircumferencesSectionState extends State<_CircumferencesSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;

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
            onTap: () => setState(() => _expanded = !_expanded),
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
                    _expanded ? TreinoIcon.chevronUp : TreinoIcon.chevronDown,
                    color: p.textMuted,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded content ──────────────────────────────────────────────
          if (_expanded) ...[
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
                    controller: widget.shouldersCtrl,
                    palette: p,
                    suffix: 'cm',
                  ),
                  const SizedBox(height: 12),
                  _numericField(
                    label: 'Pecho',
                    controller: widget.chestCtrl,
                    palette: p,
                    suffix: 'cm',
                  ),
                  const SizedBox(height: 12),
                  _numericField(
                    label: 'Cintura',
                    controller: widget.waistCtrl,
                    palette: p,
                    suffix: 'cm',
                  ),
                  const SizedBox(height: 12),
                  _numericField(
                    label: 'Cadera',
                    controller: widget.hipsCtrl,
                    palette: p,
                    suffix: 'cm',
                  ),
                  const SizedBox(height: 12),
                  _numericField(
                    label: 'Glúteos',
                    controller: widget.glutesCtrl,
                    palette: p,
                    suffix: 'cm',
                  ),
                  const SizedBox(height: 20),
                  _subGroupLabel('TREN SUPERIOR', p),
                  const SizedBox(height: 12),
                  _bilateralField(
                    label: 'Bíceps',
                    leftCtrl: widget.bicepsLCtrl,
                    rightCtrl: widget.bicepsRCtrl,
                    palette: p,
                  ),
                  const SizedBox(height: 12),
                  _bilateralField(
                    label: 'Bíceps (flex)',
                    leftCtrl: widget.bicepsFlexLCtrl,
                    rightCtrl: widget.bicepsFlexRCtrl,
                    palette: p,
                  ),
                  const SizedBox(height: 12),
                  _bilateralField(
                    label: 'Antebrazo',
                    leftCtrl: widget.forearmLCtrl,
                    rightCtrl: widget.forearmRCtrl,
                    palette: p,
                  ),
                  const SizedBox(height: 20),
                  _subGroupLabel('TREN INFERIOR', p),
                  const SizedBox(height: 12),
                  _bilateralField(
                    label: 'Muslo superior',
                    leftCtrl: widget.upperThighLCtrl,
                    rightCtrl: widget.upperThighRCtrl,
                    palette: p,
                  ),
                  const SizedBox(height: 12),
                  _bilateralField(
                    label: 'Muslo medio',
                    leftCtrl: widget.midThighLCtrl,
                    rightCtrl: widget.midThighRCtrl,
                    palette: p,
                  ),
                  const SizedBox(height: 12),
                  _bilateralField(
                    label: 'Gemelo',
                    leftCtrl: widget.calfLCtrl,
                    rightCtrl: widget.calfRCtrl,
                    palette: p,
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
