import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../../core/widgets/motion/treino_tappable.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../profile/application/user_public_profile_providers.dart';
import '../agenda_formatters.dart';
import '../../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../application/agenda_providers.dart';
import '../../application/trainer_link_providers.dart';
import '../../domain/compute_free_slots.dart'
    show blockedDatesAmong, isDayBlocked;
import '../../domain/trainer_link.dart';
import '../../domain/trainer_link_status.dart';

/// Modal bottom-sheet form for the TRAINER to register a new session with an
/// athlete. Supports single ("Una vez") and recurring ("Se repite") modes.
///
/// Optional [initialDate] and [initialTime] let the timeline "+" button prefill
/// (single mode only).
class NewSessionSheet extends ConsumerStatefulWidget {
  const NewSessionSheet({super.key, this.initialDate, this.initialTime});

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
  // Drives the button spinner — true SOLO durante la escritura real.
  bool _saving = false;
  // Guard de re-entrada (QA M7), independiente de [_saving]: cubre TODO el
  // submit —incluido el chequeo async de días bloqueados y el diálogo que
  // #607 dejó por delante del spinner— sin mostrar el spinner antes de tiempo.
  // Sin él, un doble tap durante ese chequeo creaba la sesión/serie dos veces.
  bool _submitting = false;

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
        SnackBar(
          content: Text(AppL10n.of(context).newSessionSheetDurationError),
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
                      AppL10n.of(context).newSessionSheetTitle,
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
                    _FieldLabel(
                      label: AppL10n.of(context).newSessionSheetAlumnoLabel,
                      palette: palette,
                    ),
                    const SizedBox(height: 8),
                    // A failed links read must NOT read as "no athletes": that
                    // false empty state blocks creating a session for a trainer
                    // who actually has athletes. Surface a retry instead; the
                    // genuine empty (data with no active links) keeps its copy.
                    if (linksAsync.hasError && !linksAsync.hasValue)
                      _AthletePickerError(
                        palette: palette,
                        onRetry: () =>
                            ref.invalidate(trainerLinksStreamProvider),
                      )
                    else if (activeLinks.isEmpty)
                      Text(
                        AppL10n.of(context).newSessionSheetNoActiveAthletes,
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
                    // AnimatedSize: el cross-fade interpola opacity entre dos
                    // Columns de alturas muy distintas. Sin envolverlo, el
                    // Stack del layoutBuilder mantiene la altura del hijo más
                    // alto durante los 240ms y la libera de golpe al remover
                    // el saliente — los campos de abajo quedan quietos
                    // durante el fade y saltan sin animación al terminar.
                    AnimatedSize(
                      duration: AppMotion.resolve(context, AppMotion.base),
                      curve: AppMotion.standard,
                      alignment: Alignment.topCenter,
                      child: TreinoStateSwitcher(
                        childKey: ValueKey(_recurring ? 'recurring' : 'single'),
                        child: !_recurring
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // SINGLE: date picker
                                  _FieldLabel(
                                    label: AppL10n.of(
                                      context,
                                    ).newSessionSheetFechaLabel,
                                    palette: palette,
                                  ),
                                  const SizedBox(height: 8),
                                  _TappableField(
                                    palette: palette,
                                    text: _formatDate(_date),
                                    icon: TreinoIcon.calendar,
                                    onTap: _pickDate,
                                  ),
                                  const SizedBox(height: 14),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
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
                                  _FieldLabel(
                                    label: 'REPETIR POR',
                                    palette: palette,
                                  ),
                                  const SizedBox(height: 8),
                                  _WeeksChips(
                                    selected: _weeks,
                                    palette: palette,
                                    onChanged: (w) =>
                                        setState(() => _weeks = w),
                                  ),
                                  const SizedBox(height: 14),
                                ],
                              ),
                      ),
                    ),

                    // ── Time ──────────────────────────────────────────────────────
                    _FieldLabel(
                      label: AppL10n.of(context).newSessionSheetHoraLabel,
                      palette: palette,
                    ),
                    const SizedBox(height: 8),
                    _TappableField(
                      palette: palette,
                      text: _time.format(context),
                      icon: TreinoIcon.clock,
                      onTap: _pickTime,
                    ),
                    const SizedBox(height: 14),

                    // ── Duration ─────────────────────────────────────────────────
                    _FieldLabel(
                      label: AppL10n.of(context).newSessionSheetDuracionLabel,
                      palette: palette,
                    ),
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
                      label: AppL10n.of(context).newSessionSheetNotaLabel,
                      palette: palette,
                    ),
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
                          borderSide: BorderSide(
                            color: palette.accent,
                            width: 1.5,
                          ),
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
                                    ? AppL10n.of(
                                        context,
                                      ).newSessionSheetSubmitRecurring
                                    : AppL10n.of(
                                        context,
                                      ).newSessionSheetSubmitSingle,
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
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null && mounted) {
      setState(() => _time = picked);
    }
  }

  // ── Blocked-day soft warning helpers ────────────────────────────────────

  /// Reads overrides covering [date] ± 1 day and checks [isDayBlocked].
  ///
  /// Reads the repository directly (`watchOverrides(...).first`) rather than
  /// `overridesStreamProvider(...).future` — the provider is `autoDispose`
  /// and nothing else keeps it alive from this one-shot pre-submit read, so
  /// going through the repo avoids relying on provider lifecycle for a value
  /// only needed once.
  ///
  /// Fail-open: this is a soft warning, not a hard stop. If the read throws
  /// (permission/offline/etc.) we must not let the exception escape the
  /// async onPressed handler — that would silently no-op the whole submit.
  /// On any error we treat the day as NOT blocked so submit proceeds
  /// normally, just without the warning.
  Future<bool> _isDateBlocked({
    required String trainerId,
    required DateTime date,
  }) async {
    try {
      final from = date.subtract(const Duration(days: 1));
      final to = date.add(const Duration(days: 1));
      final overrides = await ref
          .read(availabilityRepositoryProvider)
          .watchOverrides(trainerId, from, to)
          .first;
      return isDayBlocked(overrides, date);
    } catch (_) {
      return false;
    }
  }

  /// Reads overrides covering the full [candidateDates] span and returns
  /// which of those dates are blocked, via [blockedDatesAmong].
  ///
  /// Fail-open: same rationale as [_isDateBlocked] — on any error, treat no
  /// dates as blocked so the recurring submit proceeds without the warning
  /// instead of the exception escaping the async onPressed handler.
  Future<List<DateTime>> _blockedDatesAmongCandidates(
    String trainerId,
    List<DateTime> candidateDates,
  ) async {
    if (candidateDates.isEmpty) return const [];
    try {
      final sorted = [...candidateDates]..sort();
      final from = sorted.first.subtract(const Duration(days: 1));
      final to = sorted.last.add(const Duration(days: 1));
      final overrides = await ref
          .read(availabilityRepositoryProvider)
          .watchOverrides(trainerId, from, to)
          .first;
      return blockedDatesAmong(overrides, candidateDates);
    } catch (_) {
      return const <DateTime>[];
    }
  }

  /// Replicates createRecurringByTrainer's weekday-expansion algorithm
  /// (appointment_repository.dart:156-212) client-side, so the blocked-day
  /// check can be run BEFORE any write happens. Returns the calendar dates
  /// (date-only, UTC) of every future occurrence that will be created.
  List<DateTime> _materializeRecurringDates({
    required Set<int> weekdays,
    required DateTime fromDate,
    required DateTime untilDate,
    required int startHour,
    required int startMinute,
  }) {
    final now = DateTime.now();
    final nowWall = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );
    final dates = <DateTime>[];

    var cursor = DateTime.utc(fromDate.year, fromDate.month, fromDate.day);
    final end = DateTime.utc(untilDate.year, untilDate.month, untilDate.day);

    while (!cursor.isAfter(end)) {
      if (weekdays.contains(cursor.weekday)) {
        final startsAt = DateTime.utc(
          cursor.year,
          cursor.month,
          cursor.day,
          startHour,
          startMinute,
        );
        if (startsAt.isAfter(nowWall)) {
          dates.add(cursor);
        }
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    return dates;
  }

  /// Shows the single-session "Día bloqueado" confirm dialog. Returns true
  /// if the trainer chose to proceed anyway (soft warning — always offers a
  /// confirm path, never a hard stop).
  Future<bool> _confirmBlockedDaySingle(DateTime date) {
    final l10n = AppL10n.of(context);
    return _showBlockedDayDialog(
      title: l10n.agendaBlockedDayTitle,
      body: l10n.agendaBlockedDayBodySingle(AgendaFormatters.formatDate(date)),
      confirmLabel: l10n.agendaBlockedDayConfirm,
      cancelLabel: l10n.commonCancel,
    );
  }

  /// Shows the recurring-session "N fechas caen en días bloqueados" confirm
  /// dialog. Returns true if the trainer chose to proceed anyway — confirming
  /// creates ALL occurrences (soft warning only; blocked dates are never
  /// skipped, the trainer decides).
  Future<bool> _confirmBlockedDayRecurring(int blockedCount) {
    final l10n = AppL10n.of(context);
    return _showBlockedDayDialog(
      title: l10n.agendaBlockedDayTitle,
      body: l10n.agendaBlockedDayBodyRecurring(blockedCount),
      confirmLabel: l10n.agendaBlockedDayConfirm,
      cancelLabel: l10n.commonCancel,
    );
  }

  Future<bool> _showBlockedDayDialog({
    required String title,
    required String body,
    required String confirmLabel,
    required String cancelLabel,
  }) async {
    final palette = AppPalette.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: palette.textPrimary,
          ),
        ),
        content: Text(
          body,
          style: GoogleFonts.barlow(fontSize: 14, color: palette.textPrimary),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(false),
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
            onPressed: () => Navigator.of(ctx).pop(true),
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
      ),
    );
    return result ?? false;
  }

  // ── Single submit ─────────────────────────────────────────────────────────

  Future<void> _submitSingle() async {
    // Guard de re-entrada ANTES del primer await (QA M7): ver [_submitting].
    // El try/finally lo desbloquea en TODA salida (validación, cancelación,
    // éxito o error) sin tener que tocarlo en cada return.
    if (_submitting) return;
    _submitting = true;
    try {
      await _submitSingleInner();
    } finally {
      _submitting = false;
    }
  }

  Future<void> _submitSingleInner() async {
    final athleteId = _selectedAthleteId;
    if (athleteId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Elegí un alumno.')));
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
          content: Text('Error de autenticación. Intentá de nuevo.'),
        ),
      );
      return;
    }

    // Blocked-day soft warning: after cheap sync validations (athlete, date,
    // duration, auth), so an already-invalid form never triggers the extra
    // network round trip. El guard _submitting ya cubre esta ventana; el
    // spinner (_saving) sigue apareciendo recién en la escritura real.
    final blocked = await _isDateBlocked(trainerId: trainerId, date: _date);
    if (!mounted) return;
    if (blocked) {
      final proceed = await _confirmBlockedDaySingle(_date);
      if (!mounted || !proceed) return;
    }

    setState(() => _saving = true);

    try {
      final profile = await ref.read(
        userPublicProfileProvider(athleteId).future,
      );
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sesión registrada.')));
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
    // Guard de re-entrada (QA M7): mismo defecto que _submitSingle — #607 dejó
    // el chequeo async de días bloqueados arriba del spinner, así que un doble
    // tap creaba la SERIE completa dos veces. Ver [_submitting].
    if (_submitting) return;
    _submitting = true;
    try {
      await _submitRecurringInner();
    } finally {
      _submitting = false;
    }
  }

  Future<void> _submitRecurringInner() async {
    final athleteId = _selectedAthleteId;
    if (athleteId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Elegí un alumno.')));
      return;
    }

    if (_weekdays.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Elegí al menos un día.')));
      return;
    }

    final dur = _parsedDuration();
    if (dur == null) return;

    final trainerId = ref.read(currentUidProvider);
    if (trainerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error de autenticación. Intentá de nuevo.'),
        ),
      );
      return;
    }

    // Compute the same fromDate/untilDate window createRecurringByTrainer
    // uses, up front (pure sync — no await needed), so the blocked-day check
    // below and the actual creation call agree on the exact same window.
    final today = DateTime.now();
    final fromDate = DateTime(today.year, today.month, today.day);
    final untilDate = fromDate.add(Duration(days: _weeks * 7 - 1));

    // Blocked-day soft warning: replicate createRecurringByTrainer's weekday
    // expansion client-side (agenda_providers.dart / appointment_repository
    // .dart:156-212) so we can list which materialized dates are blocked
    // BEFORE writing anything. Comes after cheap sync validations (athlete,
    // weekdays, duration, auth) and before the async overrides read.
    final candidateDates = _materializeRecurringDates(
      weekdays: _weekdays,
      fromDate: fromDate,
      untilDate: untilDate,
      startHour: _time.hour,
      startMinute: _time.minute,
    );

    // El guard _submitting ya cubre esta ventana async; el spinner (_saving)
    // aparece recién en la escritura real, debajo.
    final blockedDates = await _blockedDatesAmongCandidates(
      trainerId,
      candidateDates,
    );
    if (!mounted) return;
    if (blockedDates.isNotEmpty) {
      final proceed = await _confirmBlockedDayRecurring(blockedDates.length);
      if (!mounted || !proceed) return;
    }

    setState(() => _saving = true);

    try {
      final profile = await ref.read(
        userPublicProfileProvider(athleteId).future,
      );
      final rawName = profile?.displayName?.trim() ?? '';
      final athleteDisplayName = rawName.isEmpty ? athleteId : rawName;

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
    // Semantics de botón + estado (QA H13): TreinoTappable es un
    // GestureDetector pelado, sin rol ni estado. `selected` le dice al lector
    // qué modo está activo; `excludeSemantics` evita que el Text interno
    // duplique el nodo.
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: TreinoTappable(
          onTap: onTap,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.emphasized,
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
      ),
    );
  }
}

// ── Weekday chips ─────────────────────────────────────────────────────────────

// `name` es el nombre completo para el lector de pantalla (QA H13): la 'L'/'M'
// sola no alcanza — hay DOS 'M' (martes y miércoles) imposibles de distinguir
// con VoiceOver. El `label` corto sigue siendo lo que se dibuja.
const _kWeekdays = [
  (label: 'L', wd: 1, name: 'Lunes'),
  (label: 'M', wd: 2, name: 'Martes'),
  (label: 'M', wd: 3, name: 'Miércoles'),
  (label: 'J', wd: 4, name: 'Jueves'),
  (label: 'V', wd: 5, name: 'Viernes'),
  (label: 'S', wd: 6, name: 'Sábado'),
  (label: 'D', wd: 7, name: 'Domingo'),
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
        // Semantics con el nombre COMPLETO del día + estado seleccionado
        // (QA H13). El círculo visible sigue midiendo 36px, pero el área
        // tocable se expande a 44 (mínimo accesible) con un SizedBox centrado.
        return Semantics(
          button: true,
          selected: isSelected,
          label: entry.name,
          excludeSemantics: true,
          child: TreinoTappable(
            onTap: () => onToggle(entry.wd),
            child: SizedBox(
              width: 44,
              height: 44,
              child: Center(
                child: AnimatedContainer(
                  duration: AppMotion.fast,
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
          side: BorderSide(color: isSelected ? palette.accent : palette.border),
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
              borderSide: BorderSide(color: palette.accent, width: 1.5),
            ),
            suffixText: 'min',
            suffixStyle: GoogleFonts.barlow(
              fontSize: 13,
              color: palette.textMuted,
            ),
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
    return TreinoTappable(
      onTap: onTap,
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

/// Shown in the athlete-picker slot when the trainer-links stream fails
/// outright (error with no cached value). Replaces the misleading "no active
/// athletes" copy with an honest, retryable error so a transient failure never
/// reads as "you have no athletes" and blocks creating a session.
class _AthletePickerError extends StatelessWidget {
  const _AthletePickerError({required this.palette, required this.onRetry});

  final AppPalette palette;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.agendaGenericError,
          style: GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: onRetry,
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 36),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            l10n.coachRetryLabel,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 0.8,
              color: palette.accent,
            ),
          ),
        ),
      ],
    );
  }
}

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
        final profileAsync = ref.watch(
          userPublicProfileProvider(link.athleteId),
        );
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
