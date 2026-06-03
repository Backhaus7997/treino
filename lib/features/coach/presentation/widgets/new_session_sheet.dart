import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../profile/application/user_public_profile_providers.dart';
import '../../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../application/agenda_providers.dart';
import '../../application/trainer_link_providers.dart';
import '../../domain/trainer_link.dart';
import '../../domain/trainer_link_status.dart';

/// Modal bottom-sheet form for the TRAINER to register a new session with an
/// athlete. Supports single ("Una vez") and recurring ("Se repite") modes.
///
/// Optional [initialDate] and [initialTime] let the timeline "+" button prefill
/// (single mode only).
class NewSessionSheet extends ConsumerStatefulWidget {
  const NewSessionSheet({
    super.key,
    this.initialDate,
    this.initialTime,
  });

  final DateTime? initialDate;
  final TimeOfDay? initialTime;

  @override
  ConsumerState<NewSessionSheet> createState() => _NewSessionSheetState();
}

class _NewSessionSheetState extends ConsumerState<NewSessionSheet> {
  // ── Mode ──────────────────────────────────────────────────────────────────
  bool _recurring = false;

  // ── Common fields ─────────────────────────────────────────────────────────
  String? _selectedAthleteId;
  late TimeOfDay _time;
  final _durationController = TextEditingController(text: '60');
  final _noteController = TextEditingController();
  bool _saving = false;

  // ── Single-mode fields ────────────────────────────────────────────────────
  late DateTime _date;

  // ── Recurring-mode fields ─────────────────────────────────────────────────
  Set<int> _weekdays = {};
  int _weeks = 4;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = widget.initialDate ?? DateTime(now.year, now.month, now.day);
    _time = widget.initialTime ?? const TimeOfDay(hour: 9, minute: 0);
  }

  @override
  void dispose() {
    _durationController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Parses duration from controller and validates 5–480. Returns null and
  /// shows a SnackBar if invalid.
  int? _parsedDuration() {
    final val = int.tryParse(_durationController.text.trim());
    if (val == null || val < 5 || val > 480) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresá una duración válida (5–480 min).'),
        ),
      );
      return null;
    }
    return val;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final linksAsync = ref.watch(trainerLinksStreamProvider);
    final activeLinks = (linksAsync.valueOrNull ?? const <TrainerLink>[])
        .where((l) => l.status == TrainerLinkStatus.active)
        .toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle bar (fixed, OUTSIDE the scroll view so dragging it
            //    down dismisses the sheet instead of scrolling the form) ───
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(9999),
                  ),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Title ─────────────────────────────────────────────
                    Text(
                      'NUEVA SESIÓN',
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        letterSpacing: 1.2,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Mode toggle ───────────────────────────────────────────────
                    _ModeToggle(
                      recurring: _recurring,
                      palette: palette,
                      onChanged: (val) => setState(() => _recurring = val),
                    ),
                    const SizedBox(height: 18),

                    // ── Athlete picker ────────────────────────────────────────────
                    _FieldLabel(label: 'ALUMNO', palette: palette),
                    const SizedBox(height: 8),
                    if (activeLinks.isEmpty)
                      Text(
                        'No tenés alumnos activos.',
                        style: GoogleFonts.barlow(
                          fontSize: 13,
                          color: palette.textMuted,
                        ),
                      )
                    else
                      _AthleteDropdown(
                        links: activeLinks,
                        selectedId: _selectedAthleteId,
                        palette: palette,
                        onChanged: (id) =>
                            setState(() => _selectedAthleteId = id),
                      ),
                    const SizedBox(height: 14),

                    // ── Per-mode fields ───────────────────────────────────────────
                    if (!_recurring) ...[
                      // SINGLE: date picker
                      _FieldLabel(label: 'FECHA', palette: palette),
                      const SizedBox(height: 8),
                      _TappableField(
                        palette: palette,
                        text: _formatDate(_date),
                        icon: TreinoIcon.calendar,
                        onTap: _pickDate,
                      ),
                      const SizedBox(height: 14),
                    ] else ...[
                      // RECURRING: weekday chips
                      _FieldLabel(label: 'DÍAS', palette: palette),
                      const SizedBox(height: 8),
                      _WeekdayChips(
                        selected: _weekdays,
                        palette: palette,
                        onToggle: (wd) => setState(() {
                          if (_weekdays.contains(wd)) {
                            _weekdays = {..._weekdays}..remove(wd);
                          } else {
                            _weekdays = {..._weekdays, wd};
                          }
                        }),
                      ),
                      const SizedBox(height: 14),

                      // RECURRING: repeat-for chips
                      _FieldLabel(label: 'REPETIR POR', palette: palette),
                      const SizedBox(height: 8),
                      _WeeksChips(
                        selected: _weeks,
                        palette: palette,
                        onChanged: (w) => setState(() => _weeks = w),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // ── Time ──────────────────────────────────────────────────────
                    _FieldLabel(label: 'HORA DE INICIO', palette: palette),
                    const SizedBox(height: 8),
                    _TappableField(
                      palette: palette,
                      text: _time.format(context),
                      icon: TreinoIcon.clock,
                      onTap: _pickTime,
                    ),
                    const SizedBox(height: 14),

                    // ── Duration ─────────────────────────────────────────────────
                    _FieldLabel(label: 'DURACIÓN (MIN)', palette: palette),
                    const SizedBox(height: 8),
                    _DurationSection(
                      controller: _durationController,
                      palette: palette,
                      onChipTap: (val) => setState(() {
                        _durationController.text = val.toString();
                      }),
                    ),
                    const SizedBox(height: 14),

                    // ── Note ──────────────────────────────────────────────────────
                    _FieldLabel(
                        label: 'NOTA PREVIA (OPCIONAL)', palette: palette),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _noteController,
                      maxLines: 2,
                      style: GoogleFonts.barlow(
                        fontSize: 14,
                        color: palette.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Ej: traer banda, primera sesión…',
                        hintStyle: GoogleFonts.barlow(
                          fontSize: 14,
                          color: palette.textMuted,
                        ),
                        filled: true,
                        fillColor: palette.bg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: palette.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: palette.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: palette.accent, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Submit button ─────────────────────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: (_saving ||
                                activeLinks.isEmpty ||
                                _selectedAthleteId == null)
                            ? null
                            : (_recurring ? _submitRecurring : _submitSingle),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: palette.accent,
                          foregroundColor: palette.bg,
                          disabledBackgroundColor: palette.border,
                          minimumSize: const Size.fromHeight(48),
                          shape: const StadiumBorder(),
                        ),
                        child: _saving
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: palette.bg,
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(
                                _recurring
                                    ? 'REGISTRAR SERIE'
                                    : 'REGISTRAR SESIÓN',
                                style: GoogleFonts.barlowCondensed(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  letterSpacing: 0.8,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _date = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
    );
    if (picked != null && mounted) {
      setState(() => _time = picked);
    }
  }

  // ── Single submit ─────────────────────────────────────────────────────────

  Future<void> _submitSingle() async {
    final athleteId = _selectedAthleteId;
    if (athleteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Elegí un alumno.')),
      );
      return;
    }

    // Past date+time guard (date picker blocks past dates but not past times today).
    final now = DateTime.now();
    final startsAt = DateTime.utc(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );
    final nowWall = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );
    if (!startsAt.isAfter(nowWall)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No podés registrar una sesión en el pasado.'),
        ),
      );
      return;
    }

    final dur = _parsedDuration();
    if (dur == null) return;

    final trainerId = ref.read(currentUidProvider);
    if (trainerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Error de autenticación. Intentá de nuevo.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final profile =
          await ref.read(userPublicProfileProvider(athleteId).future);
      final rawName = profile?.displayName?.trim() ?? '';
      final athleteDisplayName = rawName.isEmpty ? athleteId : rawName;

      final note = _noteController.text.trim();

      await ref.read(appointmentRepositoryProvider).createByTrainer(
            trainerId: trainerId,
            athleteId: athleteId,
            athleteDisplayName: athleteDisplayName,
            startsAt: startsAt,
            durationMin: dur,
            noteBefore: note.isEmpty ? null : note,
          );

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesión registrada.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pudimos registrar la sesión. Probá de nuevo.'),
        ),
      );
    }
  }

  // ── Recurring submit ──────────────────────────────────────────────────────

  Future<void> _submitRecurring() async {
    final athleteId = _selectedAthleteId;
    if (athleteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Elegí un alumno.')),
      );
      return;
    }

    if (_weekdays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Elegí al menos un día.')),
      );
      return;
    }

    final dur = _parsedDuration();
    if (dur == null) return;

    final trainerId = ref.read(currentUidProvider);
    if (trainerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Error de autenticación. Intentá de nuevo.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final profile =
          await ref.read(userPublicProfileProvider(athleteId).future);
      final rawName = profile?.displayName?.trim() ?? '';
      final athleteDisplayName = rawName.isEmpty ? athleteId : rawName;

      final today = DateTime.now();
      final fromDate = DateTime(today.year, today.month, today.day);
      final untilDate = fromDate.add(Duration(days: _weeks * 7 - 1));

      final note = _noteController.text.trim();

      final count = await ref
          .read(appointmentRepositoryProvider)
          .createRecurringByTrainer(
            trainerId: trainerId,
            athleteId: athleteId,
            athleteDisplayName: athleteDisplayName,
            weekdays: _weekdays,
            startHour: _time.hour,
            startMinute: _time.minute,
            durationMin: dur,
            fromDate: fromDate,
            untilDate: untilDate,
            noteBefore: note.isEmpty ? null : note,
          );

      if (!mounted) return;

      if (count == 0) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se creó ninguna sesión (todas caían en el pasado). '
              'Revisá los días y la hora.',
            ),
          ),
        );
        return;
      }

      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$count ${count == 1 ? "sesión registrada" : "sesiones registradas"}.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pudimos registrar la serie. Probá de nuevo.'),
        ),
      );
    }
  }
}

// ── Mode toggle ────────────────────────────────────────────────────────────────

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({
    required this.recurring,
    required this.palette,
    required this.onChanged,
  });

  final bool recurring;
  final AppPalette palette;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.border),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          _Pill(
            label: 'Una vez',
            selected: !recurring,
            palette: palette,
            onTap: () => onChanged(false),
          ),
          _Pill(
            label: 'Se repite',
            selected: recurring,
            palette: palette,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? palette.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(21),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 0.6,
              color: selected ? palette.bg : palette.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Weekday chips ─────────────────────────────────────────────────────────────

const _kWeekdays = [
  (label: 'L', wd: 1),
  (label: 'M', wd: 2),
  (label: 'M', wd: 3),
  (label: 'J', wd: 4),
  (label: 'V', wd: 5),
  (label: 'S', wd: 6),
  (label: 'D', wd: 7),
];

class _WeekdayChips extends StatelessWidget {
  const _WeekdayChips({
    required this.selected,
    required this.palette,
    required this.onToggle,
  });

  final Set<int> selected;
  final AppPalette palette;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _kWeekdays.map((entry) {
        final isSelected = selected.contains(entry.wd);
        return GestureDetector(
          onTap: () => onToggle(entry.wd),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isSelected ? palette.accent : palette.bg,
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? palette.accent : palette.border,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              entry.label,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: isSelected ? palette.bg : palette.textPrimary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Weeks chips ───────────────────────────────────────────────────────────────

const _kWeekOptions = [2, 4, 8, 12];

class _WeeksChips extends StatelessWidget {
  const _WeeksChips({
    required this.selected,
    required this.palette,
    required this.onChanged,
  });

  final int selected;
  final AppPalette palette;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _kWeekOptions.map((w) {
        final isSelected = w == selected;
        return ChoiceChip(
          label: Text(
            '$w semanas',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 0.5,
              color: isSelected ? palette.bg : palette.textPrimary,
            ),
          ),
          selected: isSelected,
          selectedColor: palette.accent,
          backgroundColor: palette.bg,
          side: BorderSide(
            color: isSelected ? palette.accent : palette.border,
          ),
          onSelected: (_) => onChanged(w),
          showCheckmark: false,
        );
      }).toList(),
    );
  }
}

// ── Duration section ──────────────────────────────────────────────────────────

const _kDurations = [30, 45, 60, 90, 120];

class _DurationSection extends StatefulWidget {
  const _DurationSection({
    required this.controller,
    required this.palette,
    required this.onChipTap,
  });

  final TextEditingController controller;
  final AppPalette palette;
  final ValueChanged<int> onChipTap;

  @override
  State<_DurationSection> createState() => _DurationSectionState();
}

class _DurationSectionState extends State<_DurationSection> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final parsed = int.tryParse(widget.controller.text.trim());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Free-text input
        TextField(
          controller: widget.controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: GoogleFonts.barlow(fontSize: 14, color: palette.textPrimary),
          decoration: InputDecoration(
            hintText: '60',
            hintStyle:
                GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
            filled: true,
            fillColor: palette.bg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: palette.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: palette.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: palette.accent, width: 1.5),
            ),
            suffixText: 'min',
            suffixStyle:
                GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
          ),
        ),
        const SizedBox(height: 8),
        // Preset shortcut chips
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _kDurations.map((min) {
            final isSelected = parsed == min;
            return ChoiceChip(
              label: Text(
                '$min',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 0.5,
                  color: isSelected ? palette.bg : palette.textPrimary,
                ),
              ),
              selected: isSelected,
              selectedColor: palette.accent,
              backgroundColor: palette.bg,
              side: BorderSide(
                color: isSelected ? palette.accent : palette.border,
              ),
              onSelected: (_) => widget.onChipTap(min),
              showCheckmark: false,
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ── Tappable field row (date / time) ──────────────────────────────────────────

class _TappableField extends StatelessWidget {
  const _TappableField({
    required this.palette,
    required this.text,
    required this.icon,
    required this.onTap,
  });

  final AppPalette palette;
  final String text;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: palette.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: palette.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.barlow(
                  fontSize: 14,
                  color: palette.textPrimary,
                ),
              ),
            ),
            Icon(TreinoIcon.chevronDown, size: 14, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}

// ── Field label ───────────────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, required this.palette});
  final String label;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.barlowCondensed(
        fontWeight: FontWeight.w700,
        fontSize: 11,
        letterSpacing: 1.2,
        color: palette.textMuted,
      ),
    );
  }
}

// ── Athlete dropdown ──────────────────────────────────────────────────────────

class _AthleteDropdown extends ConsumerWidget {
  const _AthleteDropdown({
    required this.links,
    required this.selectedId,
    required this.palette,
    required this.onChanged,
  });

  final List<TrainerLink> links;
  final String? selectedId;
  final AppPalette palette;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DropdownButtonFormField<String>(
      initialValue: selectedId,
      hint: Text(
        'Seleccioná un alumno',
        style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
      ),
      dropdownColor: palette.bgCard,
      style: GoogleFonts.barlow(fontSize: 14, color: palette.textPrimary),
      decoration: InputDecoration(
        filled: true,
        fillColor: palette.bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.accent, width: 1.5),
        ),
      ),
      items: links.map((link) {
        final profileAsync =
            ref.watch(userPublicProfileProvider(link.athleteId));
        final rawName = profileAsync.valueOrNull?.displayName ?? '';
        final showName = rawName.isEmpty || _looksLikeUid(rawName)
            ? 'Alumno (${link.athleteId.substring(0, 6)})'
            : rawName;
        return DropdownMenuItem<String>(
          value: link.athleteId,
          child: Text(showName),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _formatDate(DateTime dt) {
  final dd = dt.day.toString().padLeft(2, '0');
  final mm = dt.month.toString().padLeft(2, '0');
  final yyyy = dt.year;
  return '$dd/$mm/$yyyy';
}

bool _looksLikeUid(String s) {
  if (s.length < 20) return false;
  if (s.contains(' ')) return false;
  return RegExp(r'^[a-zA-Z0-9]+$').hasMatch(s);
}
