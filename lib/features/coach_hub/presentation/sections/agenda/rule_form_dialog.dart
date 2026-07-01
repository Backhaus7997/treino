// PR3a — Formulario de regla de disponibilidad (AlertDialog web idiom).
// Puerto de _RuleFormSheet (availability_editor_screen.dart:382-603).
// Strings en español hardcodeado + // i18n. NO se usa AppL10n (constraint C-6).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../coach/application/agenda_providers.dart';
import '../../../../coach/domain/availability_rule.dart';
import '../../../../coach/presentation/agenda_formatters.dart';

// ─── RuleFormDialog ───────────────────────────────────────────────────────────

/// AlertDialog que permite agregar o editar una regla de disponibilidad semanal.
///
/// Puerto web de [_RuleFormSheet] (availability_editor_screen.dart:382-603).
/// Valida: endTotal >= startTotal + slotDurationMin.
/// Llama a [addRule] o [updateRule] según si [existing] es null.
///
/// REQ-AGW-301 (SCENARIO-301-B/C).
class RuleFormDialog extends ConsumerStatefulWidget {
  const RuleFormDialog({
    super.key,
    required this.trainerId,
    this.existing,
  });

  final String trainerId;
  final AvailabilityRule? existing;

  @override
  ConsumerState<RuleFormDialog> createState() => _RuleFormDialogState();
}

class _RuleFormDialogState extends ConsumerState<RuleFormDialog> {
  late int _dayOfWeek;
  late int _startHour;
  late int _startMinute;
  late int _endHour;
  late int _endMinute;
  late int _slotDurationMin;

  String? _windowError;
  bool _saving = false;

  static const _kDurations = [30, 60, 90, 120];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _dayOfWeek = e?.dayOfWeek ?? DateTime.monday;
    _startHour = e?.startHour ?? 9;
    _startMinute = e?.startMinute ?? 0;
    _endHour = e?.endHour ?? 11;
    _endMinute = e?.endMinute ?? 0;
    _slotDurationMin = e?.slotDurationMin ?? 60;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isEdit = widget.existing != null;

    return AlertDialog(
      backgroundColor: palette.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        isEdit ? 'Editar horario' : 'Agregar horario', // i18n
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: palette.textPrimary,
        ),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Día de la semana
              _FormLabel('Día de la semana', palette), // i18n
              const SizedBox(height: 6),
              _DayPicker(
                value: _dayOfWeek,
                onChanged: (v) => setState(() {
                  _dayOfWeek = v;
                  _windowError = null;
                }),
                palette: palette,
              ),
              const SizedBox(height: 16),

              // Hora inicio
              _FormLabel('Hora de inicio', palette), // i18n
              const SizedBox(height: 6),
              _TimePicker(
                hour: _startHour,
                minute: _startMinute,
                onChanged: (h, m) => setState(() {
                  _startHour = h;
                  _startMinute = m;
                  _windowError = null;
                }),
                palette: palette,
              ),
              const SizedBox(height: 16),

              // Hora fin
              _FormLabel('Hora de fin', palette), // i18n
              const SizedBox(height: 6),
              _TimePicker(
                hour: _endHour,
                minute: _endMinute,
                onChanged: (h, m) => setState(() {
                  _endHour = h;
                  _endMinute = m;
                  _windowError = null;
                }),
                palette: palette,
              ),

              // Error inline de ventana inválida
              if (_windowError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _windowError!,
                  style: GoogleFonts.barlow(
                    fontSize: 12,
                    color: palette.highlight,
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Duración del turno
              _FormLabel('Duración del turno', palette), // i18n
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: _kDurations.map((d) {
                  final selected = d == _slotDurationMin;
                  return ChoiceChip(
                    label: Text(
                      '$d min', // i18n
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: selected ? palette.bg : palette.textPrimary,
                      ),
                    ),
                    selected: selected,
                    selectedColor: palette.accent,
                    backgroundColor: palette.bgCard,
                    side: BorderSide(
                      color: selected ? palette.accent : palette.border,
                    ),
                    onSelected: (_) => setState(() {
                      _slotDurationMin = d;
                      _windowError = null;
                    }),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(
            'CANCELAR', // i18n
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: palette.textPrimary,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: _saving ? null : () => _save(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: palette.accent,
            foregroundColor: palette.bg,
          ),
          child: Text(
            'GUARDAR', // i18n
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _save(BuildContext context) async {
    final startTotalMinutes = _startHour * 60 + _startMinute;
    final endTotalMinutes = _endHour * 60 + _endMinute;

    // Ventana debe terminar después de iniciar y ser suficiente para al menos
    // un turno, de lo contrario compute_free_slots genera 0 slots disponibles.
    if (endTotalMinutes < startTotalMinutes + _slotDurationMin) {
      setState(() {
        _windowError =
            'La ventana debe ser suficiente para al menos un turno de $_slotDurationMin min.'; // i18n
      });
      return;
    }

    setState(() => _saving = true);
    try {
      final repo = ref.read(availabilityRepositoryProvider);
      if (widget.existing != null) {
        await repo.updateRule(widget.existing!.copyWith(
          dayOfWeek: _dayOfWeek,
          startHour: _startHour,
          startMinute: _startMinute,
          endHour: _endHour,
          endMinute: _endMinute,
          slotDurationMin: _slotDurationMin,
        ));
      } else {
        final id = _generateId();
        await repo.addRule(AvailabilityRule(
          id: id,
          trainerId: widget.trainerId,
          dayOfWeek: _dayOfWeek,
          startHour: _startHour,
          startMinute: _startMinute,
          endHour: _endHour,
          endMinute: _endMinute,
          slotDurationMin: _slotDurationMin,
        ));
      }
      if (context.mounted) Navigator.of(context).pop();
    } catch (_) {
      // Mantener el formulario abierto para que el entrenador pueda reintentar.
      if (mounted) setState(() => _saving = false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ─── _DayPicker ───────────────────────────────────────────────────────────────

class _DayPicker extends StatelessWidget {
  const _DayPicker({
    required this.value,
    required this.onChanged,
    required this.palette,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: AgendaFormatters.dayOfWeekLabels.entries.map((entry) {
        final selected = entry.key == value;
        return ChoiceChip(
          label: Text(
            entry.value.substring(0, math.min(3, entry.value.length)),
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: selected ? palette.bg : palette.textPrimary,
            ),
          ),
          selected: selected,
          selectedColor: palette.accent,
          backgroundColor: palette.bgCard,
          side: BorderSide(
            color: selected ? palette.accent : palette.border,
          ),
          onSelected: (_) => onChanged(entry.key),
        );
      }).toList(),
    );
  }
}

// ─── _TimePicker ──────────────────────────────────────────────────────────────

class _TimePicker extends StatelessWidget {
  const _TimePicker({
    required this.hour,
    required this.minute,
    required this.onChanged,
    required this.palette,
  });

  final int hour;
  final int minute;
  final void Function(int, int) onChanged;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.access_time_outlined,
                size: 18, color: palette.textMuted),
            const SizedBox(width: 8),
            Text(
              '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}',
              style: GoogleFonts.barlow(
                fontSize: 14,
                color: palette.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) onChanged(picked.hour, picked.minute);
  }
}

// ─── _FormLabel ───────────────────────────────────────────────────────────────

class _FormLabel extends StatelessWidget {
  const _FormLabel(this.text, this.palette);
  final String text;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.barlow(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: palette.textMuted,
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _generateId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final rand = math.Random();
  return List.generate(20, (_) => chars[rand.nextInt(chars.length)]).join();
}
