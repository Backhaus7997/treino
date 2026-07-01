// PR3b — Formularios de excepción de disponibilidad (AlertDialog web idiom).
// Puerto de _BlockOverrideFormSheet (availability_editor_screen.dart:607-756).
// Strings en español hardcodeado + // i18n. NO se usa AppL10n (constraint C-6).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../coach/application/agenda_providers.dart';
import '../../../../coach/domain/availability_override.dart';
import '../../../../coach/presentation/agenda_formatters.dart';

// ─── BlockOverrideFormDialog ──────────────────────────────────────────────────

/// AlertDialog para bloquear un día completo (override tipo `block`).
///
/// Puerto web de [_BlockOverrideFormSheet] (availability_editor_screen.dart:607-756).
/// Llama a [addOverride(block)] al confirmar.
///
/// REQ-AGW-302 (SCENARIO-302-A).
class BlockOverrideFormDialog extends ConsumerStatefulWidget {
  const BlockOverrideFormDialog({super.key, required this.trainerId});

  final String trainerId;

  @override
  ConsumerState<BlockOverrideFormDialog> createState() =>
      _BlockOverrideFormDialogState();
}

class _BlockOverrideFormDialogState
    extends ConsumerState<BlockOverrideFormDialog> {
  DateTime _date = DateTime.now().toUtc().add(const Duration(days: 1));
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return AlertDialog(
      backgroundColor: palette.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Bloquear día', // i18n
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: palette.textPrimary,
        ),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 340, maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FormLabel('Fecha a bloquear', palette), // i18n
            const SizedBox(height: 6),
            _DateField(
              date: _date,
              onChanged: (d) => setState(() => _date = d),
              palette: palette,
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
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
            'CONFIRMAR', // i18n
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
    setState(() => _saving = true);
    try {
      await ref.read(availabilityRepositoryProvider).addOverride(
            AvailabilityOverride.block(
              id: _generateId(),
              trainerId: widget.trainerId,
              date: _date,
            ),
          );
      if (context.mounted) Navigator.of(context).pop();
    } catch (_) {
      // Failure: stay open so trainer can retry
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ─── ExtraOverrideFormDialog ──────────────────────────────────────────────────

/// AlertDialog para agregar una ventana de disponibilidad extra un día puntual.
///
/// Valida: endTotal > startTotal. slotDurationMin fijo en 60 (no editable en web,
/// sigue la restricción del dominio de los valores válidos {30,60,90,120}).
///
/// REQ-AGW-302 (SCENARIO-302-B).
class ExtraOverrideFormDialog extends ConsumerStatefulWidget {
  const ExtraOverrideFormDialog({super.key, required this.trainerId});

  final String trainerId;

  @override
  ConsumerState<ExtraOverrideFormDialog> createState() =>
      _ExtraOverrideFormDialogState();
}

class _ExtraOverrideFormDialogState
    extends ConsumerState<ExtraOverrideFormDialog> {
  DateTime _date = DateTime.now().toUtc().add(const Duration(days: 1));
  int _startHour = 7;
  int _startMinute = 0;
  int _endHour = 9;
  int _endMinute = 0;

  static const _kDurations = [30, 60, 90, 120];
  int _slotDurationMin = 60;

  String? _windowError;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return AlertDialog(
      backgroundColor: palette.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Ventana extra', // i18n
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: palette.textPrimary,
        ),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 340, maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FormLabel('Fecha', palette), // i18n
              const SizedBox(height: 6),
              _DateField(
                date: _date,
                onChanged: (d) => setState(() => _date = d),
                palette: palette,
              ),
              const SizedBox(height: 16),

              _FormLabel('Hora inicio', palette), // i18n
              const SizedBox(height: 6),
              _TimeField(
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

              _FormLabel('Hora fin', palette), // i18n
              const SizedBox(height: 6),
              _TimeField(
                hour: _endHour,
                minute: _endMinute,
                onChanged: (h, m) => setState(() {
                  _endHour = h;
                  _endMinute = m;
                  _windowError = null;
                }),
                palette: palette,
              ),

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
              _FormLabel('Duración del turno', palette), // i18n
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
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
                    onSelected: (_) => setState(() => _slotDurationMin = d),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
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
            'CONFIRMAR', // i18n
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
    final startTotal = _startHour * 60 + _startMinute;
    final endTotal = _endHour * 60 + _endMinute;
    if (endTotal <= startTotal) {
      setState(() => _windowError =
          'La hora fin debe ser posterior a la hora inicio.'); // i18n
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(availabilityRepositoryProvider).addOverride(
            AvailabilityOverride.extra(
              id: _generateId(),
              trainerId: widget.trainerId,
              date: _date,
              startHour: _startHour,
              startMinute: _startMinute,
              endHour: _endHour,
              endMinute: _endMinute,
              slotDurationMin: _slotDurationMin,
            ),
          );
      if (context.mounted) Navigator.of(context).pop();
    } catch (_) {
      // Failure: stay open so trainer can retry
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ─── Shared sub-widgets ───────────────────────────────────────────────────────

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

class _DateField extends StatelessWidget {
  const _DateField({
    required this.date,
    required this.onChanged,
    required this.palette,
  });

  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _pick(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_outlined,
                size: 18, color: palette.textMuted),
            const SizedBox(width: 8),
            Text(
              AgendaFormatters.formatDate(date),
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
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: date.toLocal(),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      onChanged(DateTime.utc(picked.year, picked.month, picked.day));
    }
  }
}

class _TimeField extends StatelessWidget {
  const _TimeField({
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

// ─── Helpers ──────────────────────────────────────────────────────────────────

String _generateId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final rand = math.Random();
  return List.generate(20, (_) => chars[rand.nextInt(chars.length)]).join();
}
