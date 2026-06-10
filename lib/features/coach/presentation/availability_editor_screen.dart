import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../application/agenda_providers.dart';
import '../domain/availability_override.dart';
import '../domain/availability_rule.dart';
import 'agenda_formatters.dart';
import 'agenda_strings.dart';

/// Full-screen editor where the trainer manages their availability rules
/// and date overrides.
///
/// REQ-020: navigate here from TrainerAgendaTab via `/coach/availability-editor`
/// REQ-021: add / edit / delete recurring weekly rules
/// REQ-022: add block / extra overrides, deletable
///
/// SCENARIO-513: screen renders with title and addRuleCta
/// SCENARIO-514: existing rules appear in list
/// SCENARIO-515: tap addRuleCta → bottom sheet with save button
/// SCENARIO-516: tap delete → confirm dialog → deleteRule called
/// SCENARIO-517: blockDayCta is visible
/// SCENARIO-518: existing block overrides appear in list
/// SCENARIO-519: tap delete for override → confirm → deleteOverride called
class AvailabilityEditorScreen extends ConsumerWidget {
  const AvailabilityEditorScreen({super.key, required this.trainerId});

  final String trainerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: palette.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: palette.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          AgendaStrings.editorTitle,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: palette.textPrimary,
          ),
        ),
      ),
      body: _EditorBody(trainerId: trainerId),
    );
  }
}

// ── Body ─────────────────────────────────────────────────────────────────────

class _EditorBody extends ConsumerWidget {
  const _EditorBody({required this.trainerId});
  final String trainerId;

  static final _kRangeFrom = DateTime.utc(2026, 1, 1);
  static final _kRangeTo = DateTime.utc(2027, 12, 31);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rulesAsync = ref.watch(availabilityRulesStreamProvider(trainerId));
    final overridesAsync = ref.watch(overridesStreamProvider(OverridesKey(
      trainerId: trainerId,
      fromDate: _kRangeFrom,
      toDate: _kRangeTo,
    )));

    final rules = rulesAsync.valueOrNull ?? const [];
    final overrides = overridesAsync.valueOrNull ?? const [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        // ── Rules section ───────────────────────────────────────────────────
        const _SectionHeader(label: 'MIS HORARIOS DE TRABAJO'),
        const SizedBox(height: 12),
        if (rules.isEmpty)
          const _EmptyHint(
            message:
                'Sin horarios configurados. Agregá uno para que tus alumnos puedan reservar.',
          )
        else
          for (final rule in rules)
            _RuleTile(
              rule: rule,
              trainerId: trainerId,
              onEdit: () => _openRuleForm(context, ref, rule: rule),
              onDelete: () => _confirmDeleteRule(context, ref, rule),
            ),
        const SizedBox(height: 16),
        _AddButton(
          label: AgendaStrings.addRuleCta,
          onTap: () => _openRuleForm(context, ref),
        ),

        const SizedBox(height: 32),

        // ── Overrides section ───────────────────────────────────────────────
        const _SectionHeader(label: 'EXCEPCIONES'),
        const SizedBox(height: 12),
        if (overrides.isEmpty) const _EmptyHint(message: 'Sin excepciones.'),
        for (final avOverride in overrides)
          _OverrideTile(
            availOverride: avOverride,
            trainerId: trainerId,
            onDelete: () => _confirmDeleteOverride(context, ref, avOverride),
          ),
        const SizedBox(height: 16),
        _AddButton(
          label: AgendaStrings.blockDayCta,
          onTap: () => _openBlockOverrideForm(context, ref),
        ),
      ],
    );
  }

  // ── Rule form ─────────────────────────────────────────────────────────────

  Future<void> _openRuleForm(
    BuildContext context,
    WidgetRef ref, {
    AvailabilityRule? rule,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.of(context).bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RuleFormSheet(
        trainerId: trainerId,
        existing: rule,
      ),
    );
  }

  Future<void> _confirmDeleteRule(
    BuildContext context,
    WidgetRef ref,
    AvailabilityRule rule,
  ) async {
    final palette = AppPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ConfirmDialog(
        palette: palette,
        body: AgendaStrings.ruleDeleteConfirm,
        confirmLabel: AgendaStrings.bookingConfirmCta,
        cancelLabel: AgendaStrings.bookingCancel,
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref
        .read(availabilityRepositoryProvider)
        .deleteRule(trainerId, rule.id);
  }

  // ── Override form ─────────────────────────────────────────────────────────

  Future<void> _openBlockOverrideForm(
    BuildContext context,
    WidgetRef ref,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.of(context).bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _BlockOverrideFormSheet(trainerId: trainerId),
    );
  }

  Future<void> _confirmDeleteOverride(
    BuildContext context,
    WidgetRef ref,
    AvailabilityOverride override,
  ) async {
    final palette = AppPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ConfirmDialog(
        palette: palette,
        body: '¿Eliminar esta excepción?',
        confirmLabel: AgendaStrings.bookingConfirmCta,
        cancelLabel: AgendaStrings.bookingCancel,
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await ref
        .read(availabilityRepositoryProvider)
        .deleteOverride(trainerId, override.id);
  }
}

// ── Rule tile ─────────────────────────────────────────────────────────────────

class _RuleTile extends StatelessWidget {
  const _RuleTile({
    required this.rule,
    required this.trainerId,
    required this.onEdit,
    required this.onDelete,
  });

  final AvailabilityRule rule;
  final String trainerId;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final dayLabel =
        AgendaFormatters.dayOfWeekLabels[rule.dayOfWeek] ?? '${rule.dayOfWeek}';
    final startStr =
        '${rule.startHour.toString().padLeft(2, '0')}:${rule.startMinute.toString().padLeft(2, '0')}';
    final endStr =
        '${rule.endHour.toString().padLeft(2, '0')}:${rule.endMinute.toString().padLeft(2, '0')}';
    final durationStr = '${rule.slotDurationMin} min';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dayLabel,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$startStr – $endStr · $durationStr',
                  style: GoogleFonts.barlow(
                    fontSize: 13,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.edit_outlined, size: 20, color: palette.textMuted),
            onPressed: onEdit,
            tooltip: 'Editar',
          ),
          IconButton(
            icon:
                Icon(Icons.delete_outline, size: 20, color: palette.highlight),
            onPressed: onDelete,
            tooltip: 'Eliminar',
          ),
        ],
      ),
    );
  }
}

// ── Override tile ─────────────────────────────────────────────────────────────

class _OverrideTile extends StatelessWidget {
  const _OverrideTile({
    required this.availOverride,
    required this.trainerId,
    required this.onDelete,
  });

  final AvailabilityOverride availOverride;
  final String trainerId;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final dateStr = availOverride.when(
      block: (id, tId, date) => AgendaFormatters.formatDate(date),
      extra: (id, tId, date, sh, sm, eh, em, dur) =>
          AgendaFormatters.formatDate(date),
    );

    final typeLabel = availOverride.when(
      block: (_, __, ___) => AgendaStrings.slotBlockedLabel,
      extra: (_, __, date, sh, sm, eh, em, dur) =>
          'Extra ${sh.toString().padLeft(2, '0')}:${sm.toString().padLeft(2, '0')} – ${eh.toString().padLeft(2, '0')}:${em.toString().padLeft(2, '0')}',
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dateStr,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: palette.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  typeLabel,
                  style: GoogleFonts.barlow(
                    fontSize: 13,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon:
                Icon(Icons.delete_outline, size: 20, color: palette.highlight),
            onPressed: onDelete,
            tooltip: 'Eliminar',
          ),
        ],
      ),
    );
  }
}

// ── Rule form sheet ───────────────────────────────────────────────────────────

class _RuleFormSheet extends ConsumerStatefulWidget {
  const _RuleFormSheet({required this.trainerId, this.existing});

  final String trainerId;
  final AvailabilityRule? existing;

  @override
  ConsumerState<_RuleFormSheet> createState() => _RuleFormSheetState();
}

class _RuleFormSheetState extends ConsumerState<_RuleFormSheet> {
  late int _dayOfWeek;
  late int _startHour;
  late int _startMinute;
  late int _endHour;
  late int _endMinute;
  late int _slotDurationMin;

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
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              widget.existing == null
                  ? AgendaStrings.addRuleCta
                  : 'Editar horario',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 20),

            // Day of week
            _FormLabel('Día de la semana', palette),
            const SizedBox(height: 6),
            _DayPicker(
              value: _dayOfWeek,
              onChanged: (v) => setState(() => _dayOfWeek = v),
              palette: palette,
            ),
            const SizedBox(height: 16),

            // Start time
            _FormLabel('Hora inicio', palette),
            const SizedBox(height: 6),
            _TimePicker(
              hour: _startHour,
              minute: _startMinute,
              onChanged: (h, m) => setState(() {
                _startHour = h;
                _startMinute = m;
              }),
              palette: palette,
            ),
            const SizedBox(height: 16),

            // End time
            _FormLabel('Hora fin', palette),
            const SizedBox(height: 6),
            _TimePicker(
              hour: _endHour,
              minute: _endMinute,
              onChanged: (h, m) => setState(() {
                _endHour = h;
                _endMinute = m;
              }),
              palette: palette,
            ),
            const SizedBox(height: 16),

            // Slot duration
            _FormLabel('Duración del turno', palette),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: _kDurations.map((d) {
                final selected = d == _slotDurationMin;
                return ChoiceChip(
                  label: Text(
                    '$d min',
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
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : () => _save(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.bg,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9999),
                  ),
                ),
                child: Text(
                  AgendaStrings.bookingConfirmCta,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
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
      // ignore save errors in this phase
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ── Block override form sheet ─────────────────────────────────────────────────

class _BlockOverrideFormSheet extends ConsumerStatefulWidget {
  const _BlockOverrideFormSheet({required this.trainerId});

  final String trainerId;

  @override
  ConsumerState<_BlockOverrideFormSheet> createState() =>
      _BlockOverrideFormSheetState();
}

class _BlockOverrideFormSheetState
    extends ConsumerState<_BlockOverrideFormSheet> {
  DateTime _date = DateTime.now().toUtc().add(const Duration(days: 1));
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              AgendaStrings.blockDayCta,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            _FormLabel('Fecha a bloquear', palette),
            const SizedBox(height: 6),
            InkWell(
              onTap: () => _pickDate(context),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: palette.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 18, color: palette.textMuted),
                    const SizedBox(width: 8),
                    Text(
                      AgendaFormatters.formatDate(_date),
                      style: GoogleFonts.barlow(
                        fontSize: 14,
                        color: palette.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : () => _save(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.bg,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9999),
                  ),
                ),
                child: Text(
                  AgendaStrings.bookingConfirmCta,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.toLocal(),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _date = DateTime.utc(picked.year, picked.month, picked.day);
      });
    }
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
      // ignore
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
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
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Text(
        message,
        style: GoogleFonts.barlow(
          fontWeight: FontWeight.w400,
          fontSize: 13,
          color: palette.textMuted,
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(Icons.add, size: 18, color: palette.accent),
        label: Text(
          label,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            letterSpacing: 0.8,
            color: palette.accent,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: palette.accent),
          minimumSize: const Size.fromHeight(44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999),
          ),
        ),
      ),
    );
  }
}

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
          side: BorderSide(color: selected ? palette.accent : palette.border),
          onSelected: (_) => onChanged(entry.key),
        );
      }).toList(),
    );
  }
}

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

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.palette,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
  });

  final AppPalette palette;
  final String body;
  final String confirmLabel;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: palette.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Text(
        body,
        style: GoogleFonts.barlow(fontSize: 14, color: palette.textPrimary),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            cancelLabel,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: palette.textPrimary,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: palette.accent,
            foregroundColor: palette.bg,
          ),
          child: Text(
            confirmLabel,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _generateId() {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final rand = math.Random();
  return List.generate(20, (_) => chars[rand.nextInt(chars.length)]).join();
}
