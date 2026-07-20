// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../workout/application/custom_exercise_providers.dart';
import '../../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../../workout/domain/custom_exercise.dart';
import '../../../workout/domain/equipment_type.dart';
import '../../../workout/domain/muscle_group.dart';

/// Web-native "crear ejercicio nuevo" form for the Coach Hub exercise picker.
///
/// MVP scope — name (required), muscle group, equipment — persisted as a
/// [CustomExercise] via [CustomExerciseRepository.create]. Returns the created
/// exercise so the picker can auto-select it, or `null` if the trainer cancels.
///
/// Parity note: mobile's `CustomExerciseEditorScreen` also captures a
/// description and a validated YouTube video (that URL validation + embed
/// preview is the bulk of its 892 lines). Those richer fields stay on the app
/// for now — a trainer can add them later by editing the exercise there.
Future<CustomExercise?> showCreateCustomExerciseDialog(BuildContext context) {
  return showDialog<CustomExercise>(
    context: context,
    builder: (_) => const _CustomExerciseFormDialog(),
  );
}

/// Edit an existing custom exercise (name / muscle / equipment). Preserves the
/// fields the web form doesn't surface — video, description, secondary muscle —
/// by writing back through `existing.copyWith`. Returns the updated exercise,
/// or null on cancel.
Future<CustomExercise?> showEditCustomExerciseDialog(
  BuildContext context,
  CustomExercise existing,
) {
  return showDialog<CustomExercise>(
    context: context,
    builder: (_) => _CustomExerciseFormDialog(existing: existing),
  );
}

class _CustomExerciseFormDialog extends ConsumerStatefulWidget {
  const _CustomExerciseFormDialog({this.existing});

  /// Non-null → edit mode (pre-fills the form and updates); null → create mode.
  final CustomExercise? existing;

  @override
  ConsumerState<_CustomExerciseFormDialog> createState() =>
      _CustomExerciseFormDialogState();
}

class _CustomExerciseFormDialogState
    extends ConsumerState<_CustomExerciseFormDialog> {
  final TextEditingController _nameCtrl = TextEditingController();
  MuscleGroup? _muscle;
  EquipmentType? _equipment;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final ex = widget.existing;
    if (ex != null) {
      _nameCtrl.text = ex.name;
      _muscle = MuscleGroup.fromKey(ex.muscleGroup);
      _equipment = ex.equipment;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final uid = ref.read(currentUidProvider) ?? '';
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Poné un nombre al ejercicio.'); // i18n
      return;
    }
    if (uid.isEmpty) {
      setState(() => _error = 'No pudimos identificar tu usuario.'); // i18n
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(customExerciseRepositoryProvider);
      final existing = widget.existing;
      final CustomExercise result;
      if (existing != null) {
        // copyWith keeps video / description / secondary muscle intact — the
        // web form only edits the three fields it surfaces.
        result = existing.copyWith(
          name: name,
          muscleGroup: _muscle?.key ?? '',
          equipment: _equipment,
        );
        await repo.update(result);
      } else {
        result = await repo.create(
          trainerId: uid,
          name: name,
          muscleGroup: _muscle?.key ?? '',
          equipment: _equipment,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'No pudimos guardar el ejercicio.'; // i18n
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Dialog(
      backgroundColor: palette.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      child: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header ────────────────────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _isEdit ? 'Editar ejercicio' : 'Nuevo ejercicio', // i18n
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar', // i18n
                    icon: Icon(TreinoIcon.close, color: palette.textMuted),
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // ── Name ──────────────────────────────────────────────────────
              _FieldLabel('NOMBRE', palette: palette), // i18n
              const SizedBox(height: 6),
              TextField(
                key: const Key('create_exercise_name_field'),
                controller: _nameCtrl,
                autofocus: true,
                enabled: !_saving,
                textCapitalization: TextCapitalization.sentences,
                style: GoogleFonts.barlow(
                  color: palette.textPrimary,
                  fontSize: 14,
                ),
                decoration: _inputDecoration(
                  palette,
                  'Ej: Press inclinado con mancuernas', // i18n
                ),
                onSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 16),
              // ── Muscle group (optional) ───────────────────────────────────
              _FieldLabel('MÚSCULO (opcional)', palette: palette), // i18n
              const SizedBox(height: 6),
              _SelectChips<MuscleGroup>(
                values: MuscleGroup.displayOrder,
                selected: _muscle,
                labelOf: (m) => m.label,
                onChanged: (m) => setState(() => _muscle = m),
                palette: palette,
              ),
              const SizedBox(height: 16),
              // ── Equipment (optional) ──────────────────────────────────────
              _FieldLabel('EQUIPO (opcional)', palette: palette), // i18n
              const SizedBox(height: 6),
              _SelectChips<EquipmentType>(
                values: EquipmentType.values,
                selected: _equipment,
                labelOf: (e) => e.label,
                onChanged: (e) => setState(() => _equipment = e),
                palette: palette,
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: GoogleFonts.barlow(
                    color: palette.danger,
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              // ── Actions ───────────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancelar', // i18n
                      style: GoogleFonts.barlow(color: palette.textMuted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    key: const Key('create_exercise_submit_button'),
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: palette.bg,
                      disabledBackgroundColor: palette.accent.withValues(
                        alpha: 0.3,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                    ),
                    child: _saving
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: palette.bg,
                            ),
                          )
                        : Text(
                            _isEdit ? 'Guardar' : 'Crear', // i18n
                            style: GoogleFonts.barlowCondensed(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(AppPalette palette, String hint) {
    OutlineInputBorder border(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.barlow(color: palette.textMuted, fontSize: 14),
      filled: true,
      fillColor: palette.bg,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: border(palette.border),
      enabledBorder: border(palette.border),
      focusedBorder: border(palette.accent),
    );
  }
}

/// Uppercase section label above a field.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text, {required this.palette});

  final String text;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.barlowCondensed(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: palette.textMuted,
        letterSpacing: 1,
      ),
    );
  }
}

/// A single-select wrap of chips. Tapping the active chip clears the selection
/// (both muscle and equipment are optional).
class _SelectChips<T> extends StatelessWidget {
  const _SelectChips({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    required this.palette,
  });

  final List<T> values;
  final T? selected;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final value in values)
          GestureDetector(
            onTap: () => onChanged(selected == value ? null : value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: selected == value ? palette.accent : palette.border,
                  width: selected == value ? 1.5 : 1,
                ),
                color: selected == value
                    ? palette.accent.withValues(alpha: 0.12)
                    : palette.bg,
              ),
              child: Text(
                labelOf(value).toUpperCase(),
                style: GoogleFonts.barlowCondensed(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected == value ? palette.accent : palette.textMuted,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
