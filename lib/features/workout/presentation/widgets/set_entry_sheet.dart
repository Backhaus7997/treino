import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../domain/routine_slot.dart';

/// Hoja de entrada de set — stepper de reps y peso + botón CHECK.
/// Diseño §2.2 y §5.3.
class SetEntrySheet extends StatefulWidget {
  const SetEntrySheet({
    super.key,
    required this.slot,
    required this.setNumber,
    required this.onCheck,
    this.techniqueInstructions,
    this.videoUrl,
  });

  final RoutineSlot slot;
  final int setNumber;
  final void Function(int reps, double weightKg) onCheck;

  /// Pasos de técnica del ejercicio. Si es null o vacío no se muestra el
  /// botón de info (no abrir un modal vacío).
  final List<String>? techniqueInstructions;

  /// Placeholder para futura carga de videos demostrativos.
  final String? videoUrl;

  @override
  State<SetEntrySheet> createState() => _SetEntrySheetState();
}

class _SetEntrySheetState extends State<SetEntrySheet> {
  late int _reps;
  late double _weight;

  @override
  void initState() {
    super.initState();
    _reps = widget.slot.targetRepsMin;
    _weight = widget.slot.targetWeightKg ?? 0.0;
  }

  void _incReps() => setState(() => _reps = (_reps + 1).clamp(0, 50));
  void _decReps() => setState(() => _reps = (_reps - 1).clamp(0, 50));
  void _incWeight() =>
      setState(() => _weight = (_weight + 2.5).clamp(0.0, 500.0));
  void _decWeight() =>
      setState(() => _weight = (_weight - 2.5).clamp(0.0, 500.0));

  void _onCheckTap() {
    // Editor de un único set: aplicar los valores actuales al callback y
    // cerrar. La lista del player tiene filas inline por set, así que el
    // sheet nunca auto-avanza — cada set se loguea desde su propia fila.
    widget.onCheck(_reps, _weight);
    Navigator.of(context).pop();
  }

  void _showTechniqueModal() {
    final instructions = widget.techniqueInstructions;
    if (instructions == null || instructions.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TechniqueSheet(
        exerciseName: widget.slot.exerciseName,
        instructions: instructions,
        videoUrl: widget.videoUrl,
      ),
    );
  }

  String _formatWeight(double w) =>
      w == w.truncateToDouble() ? w.toInt().toString() : w.toString();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // Padding para el teclado
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPad),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          // Título + botón de info (técnica) cuando hay instrucciones cargadas.
          Row(
            children: [
              const SizedBox(width: 32), // balance del lado izquierdo del ícono
              Expanded(
                child: Text(
                  widget.slot.exerciseName.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    letterSpacing: 1.2,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              SizedBox(
                width: 32,
                child: (widget.techniqueInstructions?.isNotEmpty ?? false)
                    ? GestureDetector(
                        onTap: _showTechniqueModal,
                        child: Icon(
                          TreinoIcon.infoCircle,
                          size: 20,
                          color: palette.textMuted,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Subtítulo set progress
          Text(
            'SET ${widget.setNumber} DE ${widget.slot.targetSets}',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              letterSpacing: 1.0,
              color: palette.accent,
            ),
          ),
          const SizedBox(height: 8),
          // Hint objetivo
          Text(
            'Objetivo: ${widget.slot.targetRepsMin}–${widget.slot.targetRepsMax} reps '
            '· ${widget.slot.targetWeightKg != null ? '${widget.slot.targetWeightKg} kg' : '– kg'}',
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w400,
              fontSize: 12,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 20),
          // Stepper reps
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StepperButton(icon: '–', onTap: _decReps),
              const SizedBox(width: 20),
              Text(
                '$_reps',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 40,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(width: 20),
              _StepperButton(icon: '+', onTap: _incReps),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'REPS',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 1.2,
                color: palette.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Stepper peso
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StepperButton(icon: '–', onTap: _decWeight),
              const SizedBox(width: 20),
              Text(
                _formatWeight(_weight),
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 40,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(width: 20),
              _StepperButton(icon: '+', onTap: _incWeight),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'KG',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 1.2,
                color: palette.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Botón CHECK
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _onCheckTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.accent,
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9999),
                ),
              ),
              child: Text(
                'CHECK',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  letterSpacing: 1.0,
                  color: palette.bg,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── _StepperButton ────────────────────────────────────────────────────────────

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onTap});

  final String icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: palette.bgCard,
          border: Border.all(color: palette.border),
        ),
        child: Center(
          child: Text(
            icon,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 24,
              color: palette.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

// ── TechniqueSheet ──────────────────────────────────────────────────────────

/// Hoja anidada con la técnica del ejercicio + placeholder de video.
/// Se abre desde el botón ⓘ del header de la sección de ejercicio
/// (anteriormente vivía sobre la SetEntrySheet).
class TechniqueSheet extends StatelessWidget {
  const TechniqueSheet({
    super.key,
    required this.exerciseName,
    required this.instructions,
    this.videoUrl,
  });

  final String exerciseName;
  final List<String> instructions;
  final String? videoUrl;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPad),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          // Título
          Text(
            exerciseName.toUpperCase(),
            textAlign: TextAlign.center,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              letterSpacing: 1.2,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'TÉCNICA',
            textAlign: TextAlign.center,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              letterSpacing: 1.0,
              color: palette.accent,
            ),
          ),
          const SizedBox(height: 18),
          // Video placeholder — se reemplaza cuando carguemos videos reales.
          if (videoUrl == null)
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: palette.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.border),
              ),
              child: Center(
                child: Text(
                  'Video próximamente',
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: palette.textMuted,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 18),
          // Lista de pasos numerados — scrollable si son muchos.
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              itemCount: instructions.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: palette.accent.withValues(alpha: 0.15),
                      border: Border.all(color: palette.accent, width: 1),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${i + 1}',
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: palette.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      instructions[i],
                      style: GoogleFonts.barlow(
                        fontWeight: FontWeight.w400,
                        fontSize: 14,
                        color: palette.textPrimary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
