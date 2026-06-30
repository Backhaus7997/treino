// NOTE: el Scaffold y el SafeArea los provee CoachHubScaffold (el shell).
// NO los agregues acá (ADR-CHW-005).
//
// PR1 — Ver turnos (read-only agenda viewer).
// Todas las strings están en español hardcodeado + comentario // i18n.
// NO se usa AppL10n en este archivo (constraint C-6).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../../core/widgets/treino_icon.dart';
import '../../../../coach/application/agenda_providers.dart';
import '../../../../coach/domain/appointment.dart';
import '../../../../coach/presentation/agenda_formatters.dart';
import '../../../../profile/application/user_public_profile_providers.dart';
import '../../../../workout/application/session_providers.dart'
    show currentUidProvider;

// ─── AgendaWebScreen ──────────────────────────────────────────────────────────

/// Sección Agenda del Coach Hub web — visualización de turnos.
///
/// Sigue el contrato de sección del Coach Hub (ADR-CHW-005): sin Scaffold
/// propio, sin SafeArea. El shell [CoachHubScaffold] provee el chrome.
/// trainerId derivado de [currentUidProvider] (ADR-AGW-2).
///
/// REQ-AGW-101/102/103.
class AgendaWebScreen extends ConsumerStatefulWidget {
  const AgendaWebScreen({super.key});

  @override
  ConsumerState<AgendaWebScreen> createState() => _AgendaWebScreenState();
}

class _AgendaWebScreenState extends ConsumerState<AgendaWebScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  // Default: week view compacta para que la lista de día tenga más espacio.
  // Mes por defecto: en el panel ancho de desktop llena mejor que la tira
  // semanal (el PF puede togglear a Semana). // i18n
  CalendarFormat _calendarFormat = CalendarFormat.month;

  // Ventana deslizante: 1 mes antes → 1 año después (UTC, ADR-7).
  late final DateTime _rangeFrom;
  late final DateTime _rangeTo;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc();
    _rangeFrom = DateTime.utc(
      now.year,
      now.month - 1 < 1 ? 1 : now.month - 1,
      1,
    );
    _rangeTo = DateTime.utc(now.year + 1, now.month, 1);
  }

  @override
  Widget build(BuildContext context) {
    final trainerId = ref.watch(currentUidProvider) ?? '';
    final selectedDay = _selectedDay ?? DateTime.now();

    final calendar = _AgendaWebCalendar(
      focusedDay: _focusedDay,
      selectedDay: _selectedDay,
      trainerId: trainerId,
      rangeFrom: _rangeFrom,
      rangeTo: _rangeTo,
      calendarFormat: _calendarFormat,
      onFormatChanged: (f) => setState(() => _calendarFormat = f),
      onDaySelected: (selected, focused) => setState(() {
        _selectedDay = selected;
        _focusedDay = focused;
      }),
      onPageChanged: (focused) => setState(() => _focusedDay = focused),
    );

    // PR1 omite botones Nueva Sesión / Mis horarios (ADR-AGW-9):
    // llegan en PR2 y PR3 respectivamente.
    return LayoutBuilder(
      builder: (context, constraints) {
        // Solo usamos el layout que llena el alto cuando hay alto acotado;
        // si no, caemos al stacked scrolleable (robusto ante alturas infinitas).
        final wide =
            constraints.maxWidth >= 900 && constraints.maxHeight.isFinite;

        if (wide) {
          // Desktop: calendario (izq) + turnos del día (der, llena el alto).
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Calendario: alto de su contenido (card compacta arriba).
                      SizedBox(
                        width: 420,
                        child: _Panel(child: calendar),
                      ),
                      const SizedBox(width: 20),
                      // Turnos del día: llena el alto disponible.
                      Expanded(
                        child: SizedBox(
                          height: double.infinity,
                          child: _Panel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _DayHeader(day: selectedDay),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: _AgendaWebDayList(
                                    trainerId: trainerId,
                                    selectedDay: selectedDay,
                                    rangeFrom: _rangeFrom,
                                    rangeTo: _rangeTo,
                                    fillHeight: true,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        // Angosto / alto no acotado: una sola columna scrolleable.
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Panel(child: calendar),
                  const SizedBox(height: 16),
                  _Panel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _DayHeader(day: selectedDay),
                        const SizedBox(height: 12),
                        _AgendaWebDayList(
                          trainerId: trainerId,
                          selectedDay: selectedDay,
                          rangeFrom: _rangeFrom,
                          rangeTo: _rangeTo,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Tarjeta contenedora estándar del Coach Hub web.
class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

/// Encabezado del panel de turnos: la fecha seleccionada en español.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Text(
      _spanishDayLabel(day).toUpperCase(), // i18n
      style: GoogleFonts.barlowCondensed(
        fontWeight: FontWeight.w700,
        fontSize: 14,
        letterSpacing: 0.8,
        color: palette.textMuted,
      ),
    );
  }
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Devuelve true si [day] es estrictamente antes de hoy (nivel de fecha, TZ local).
bool _isDayPast(DateTime day) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return DateTime(day.year, day.month, day.day).isBefore(today);
}

/// True si [name] parece un UID raw (≥20 chars, sin espacios, alfanumérico).
/// Mirror de la lógica en day_timeline.dart:323-327.
bool _isRawUid(String name) =>
    name.length >= 20 &&
    !name.contains(' ') &&
    RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(name);

/// Iniciales de [name] (máx 2 chars).
String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '?';
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
}

// Fechas en español sin depender de initializeDateFormatting. // i18n
const _spanishWeekdays = [
  'Lunes',
  'Martes',
  'Miércoles',
  'Jueves',
  'Viernes',
  'Sábado',
  'Domingo',
];
const _spanishMonths = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

/// "Martes 30 de junio". // i18n
String _spanishDayLabel(DateTime d) =>
    '${_spanishWeekdays[d.weekday - 1]} ${d.day} de ${_spanishMonths[d.month - 1]}';

// ─── _AgendaWebCalendar ───────────────────────────────────────────────────────

/// Calendario semanal/mensual con dots en días con turnos confirmados.
///
/// Port de _TrainerCalendar (trainer_agenda_tab.dart:191-341) adaptado al
/// idioma web. Sin AppL10n — strings hardcodeadas en español (C-6).
/// Dots: solo días confirmados Y no pasados (igual que mobile).
class _AgendaWebCalendar extends ConsumerWidget {
  const _AgendaWebCalendar({
    required this.focusedDay,
    required this.selectedDay,
    required this.trainerId,
    required this.rangeFrom,
    required this.rangeTo,
    required this.calendarFormat,
    required this.onFormatChanged,
    required this.onDaySelected,
    required this.onPageChanged,
  });

  final DateTime focusedDay;
  final DateTime? selectedDay;
  final String trainerId;
  final DateTime rangeFrom;
  final DateTime rangeTo;
  final CalendarFormat calendarFormat;
  final void Function(CalendarFormat) onFormatChanged;
  final void Function(DateTime, DateTime) onDaySelected;
  final void Function(DateTime) onPageChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final apptAsync = ref.watch(
      trainerAppointmentsStreamProvider(
        TrainerAppointmentsKey(
          trainerId: trainerId,
          fromDate: rangeFrom,
          toDate: rangeTo,
        ),
      ),
    );
    final appointments = apptAsync.valueOrNull ?? const <Appointment>[];

    // Días con turnos confirmados (sin pasados).
    final bookedDays = <DateTime>{};
    for (final appt in appointments) {
      if (appt.status == AppointmentStatus.confirmed &&
          !_isDayPast(appt.startsAt)) {
        final d = appt.startsAt;
        bookedDays.add(DateTime(d.year, d.month, d.day));
      }
    }

    bool hasActivity(DateTime day) =>
        bookedDays.contains(DateTime(day.year, day.month, day.day));

    return TableCalendar<dynamic>(
      locale: 'es', // i18n
      firstDay: DateTime.utc(2026, 1, 1),
      lastDay: DateTime.utc(2027, 12, 31),
      focusedDay: focusedDay,
      selectedDayPredicate: (d) =>
          selectedDay != null && isSameDay(selectedDay, d),
      onDaySelected: onDaySelected,
      onPageChanged: onPageChanged,
      calendarFormat: calendarFormat,
      onFormatChanged: onFormatChanged,
      availableCalendarFormats: const {
        CalendarFormat.month: 'Mes', // i18n
        CalendarFormat.week: 'Semana', // i18n
      },
      eventLoader: (day) =>
          (hasActivity(day) && !_isDayPast(day)) ? [null] : [],
      calendarBuilders: CalendarBuilders<dynamic>(
        markerBuilder: (context, day, events) {
          if (events.isEmpty) return null;
          return Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: palette.highlight,
              ),
            ),
          );
        },
      ),
      calendarStyle: CalendarStyle(
        outsideDaysVisible: false,
        todayDecoration: BoxDecoration(
          color: palette.accent.withAlpha(60),
          shape: BoxShape.circle,
        ),
        selectedDecoration: BoxDecoration(
          color: palette.accent,
          shape: BoxShape.circle,
        ),
        markerDecoration: BoxDecoration(
          color: palette.accent,
          shape: BoxShape.circle,
        ),
        defaultTextStyle: GoogleFonts.barlow(color: palette.textPrimary),
        weekendTextStyle: GoogleFonts.barlow(color: palette.textMuted),
        outsideTextStyle: GoogleFonts.barlow(color: palette.textMuted),
        todayTextStyle: GoogleFonts.barlow(
          color: palette.textPrimary,
          fontWeight: FontWeight.w600,
        ),
        selectedTextStyle: GoogleFonts.barlow(
          color: palette.bg,
          fontWeight: FontWeight.w700,
        ),
      ),
      headerStyle: HeaderStyle(
        formatButtonVisible: true,
        formatButtonShowsNext: true,
        titleCentered: false,
        formatButtonPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        formatButtonTextStyle: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 0.5,
          color: palette.accent,
        ),
        formatButtonDecoration: BoxDecoration(
          border: Border.all(color: palette.accent),
          borderRadius: BorderRadius.circular(9999),
        ),
        titleTextStyle: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 16,
          color: palette.textPrimary,
        ),
        leftChevronIcon: Icon(TreinoIcon.back, color: palette.textPrimary),
        rightChevronIcon: Icon(TreinoIcon.forward, color: palette.textPrimary),
      ),
      daysOfWeekStyle: DaysOfWeekStyle(
        weekdayStyle: GoogleFonts.barlowCondensed(
          color: palette.textMuted,
          fontSize: 12,
        ),
        weekendStyle: GoogleFonts.barlowCondensed(
          color: palette.textMuted,
          fontSize: 12,
        ),
      ),
    );
  }
}

// ─── _AgendaWebDayList ────────────────────────────────────────────────────────

/// Lista vertical de turnos del día seleccionado.
///
/// Reemplaza DayTimeline (hour-grid) con tarjetas simples (ADR-AGW-4).
/// Filtra: status==confirmed && mismo día. Ordena por startsAt asc.
class _AgendaWebDayList extends ConsumerWidget {
  const _AgendaWebDayList({
    required this.trainerId,
    required this.selectedDay,
    required this.rangeFrom,
    required this.rangeTo,
    this.fillHeight = false,
  });

  final String trainerId;
  final DateTime selectedDay;
  final DateTime rangeFrom;
  final DateTime rangeTo;

  /// true → ListView que llena el alto (panel desktop); false → Column
  /// shrink-wrap (dentro de la columna scrolleable del layout angosto).
  final bool fillHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final apptAsync = ref.watch(
      trainerAppointmentsStreamProvider(
        TrainerAppointmentsKey(
          trainerId: trainerId,
          fromDate: rangeFrom,
          toDate: rangeTo,
        ),
      ),
    );

    return apptAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: CircularProgressIndicator(color: palette.accent),
        ),
      ),
      error: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'Error al cargar los turnos.', // i18n
            style: TextStyle(color: palette.textMuted),
          ),
        ),
      ),
      data: (allAppts) {
        // Filtrar: confirmados del día seleccionado.
        final dayAppts = allAppts
            .where(
              (a) =>
                  a.status == AppointmentStatus.confirmed &&
                  a.startsAt.year == selectedDay.year &&
                  a.startsAt.month == selectedDay.month &&
                  a.startsAt.day == selectedDay.day,
            )
            .toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

        if (dayAppts.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No hay sesiones este día.', // i18n
                style: TextStyle(color: palette.textMuted),
              ),
            ),
          );
        }

        final cards = <Widget>[
          for (final appt in dayAppts)
            _AppointmentCard(appointment: appt, trainerId: trainerId),
        ];
        // Panel desktop: ListView que llena el alto y scrollea.
        // Layout angosto: Column shrink-wrap dentro del scroll de la página.
        if (fillHeight) {
          return ListView(children: cards);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: cards,
        );
      },
    );
  }
}

// ─── _AppointmentCard ────────────────────────────────────────────────────────

/// Tarjeta de turno: hora, nombre del alumno, duración.
/// onTap abre [_AppointmentDetailDialog] (ADR-AGW-3).
class _AppointmentCard extends ConsumerWidget {
  const _AppointmentCard({
    required this.appointment,
    required this.trainerId,
  });

  final Appointment appointment;
  final String trainerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final appt = appointment;

    // Nombre del alumno: profile stream → fallback a athleteDisplayName → Alumno.
    final profileAsync = ref.watch(userPublicProfileProvider(appt.athleteId));
    final rawName =
        profileAsync.valueOrNull?.displayName ?? appt.athleteDisplayName;
    final athleteName = (_isRawUid(rawName) || rawName.trim().isEmpty)
        ? 'Alumno'
        : rawName; // i18n

    final timeLabel = AgendaFormatters.formatTime(appt.startsAt);
    final durationLabel = '${appt.durationMin} min'; // i18n

    return GestureDetector(
      onTap: () => _openDetail(context, ref),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            Text(
              timeLabel,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: palette.accent,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                athleteName,
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: palette.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              durationLabel,
              style: GoogleFonts.barlow(
                fontSize: 13,
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, WidgetRef ref) {
    final now = DateTime.now().toUtc();
    final isPast = appointment.startsAt.isBefore(now);
    showDialog<void>(
      context: context,
      builder: (_) => _AppointmentDetailDialog(
        appointment: appointment,
        trainerId: trainerId,
        isPast: isPast,
      ),
    );
  }
}

// ─── _AppointmentDetailDialog ─────────────────────────────────────────────────

/// Dialog de detalle de turno — idioma web (AlertDialog, ADR-AGW-3).
///
/// Reemplaza SessionDetailSheet (bottom sheet mobile).
/// La fila del alumno es NO tappeable en PR1 (ADR-AGW-8): la navegación
/// /alumnos/{id} pertenece a la rama chat-web-v1.
///
/// Soporta: rango horario, badge SERIE RECURRENTE, notas (antes/después),
/// GUARDAR NOTAS, CANCELAR RESERVA (>24h), cancelar toda la serie, Cerrar.
class _AppointmentDetailDialog extends ConsumerStatefulWidget {
  const _AppointmentDetailDialog({
    required this.appointment,
    required this.trainerId,
    required this.isPast,
  });

  final Appointment appointment;
  final String trainerId;
  final bool isPast;

  @override
  ConsumerState<_AppointmentDetailDialog> createState() =>
      _AppointmentDetailDialogState();
}

class _AppointmentDetailDialogState
    extends ConsumerState<_AppointmentDetailDialog> {
  late final TextEditingController _beforeController;
  late final TextEditingController _afterController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _beforeController =
        TextEditingController(text: widget.appointment.noteBefore ?? '');
    _afterController =
        TextEditingController(text: widget.appointment.noteAfter ?? '');
  }

  @override
  void dispose() {
    _beforeController.dispose();
    _afterController.dispose();
    super.dispose();
  }

  Future<void> _saveNotes() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final before = _beforeController.text.trim();
      final after = _afterController.text.trim();
      await ref.read(appointmentRepositoryProvider).updateNotes(
            appointmentId: widget.appointment.id,
            noteBefore: before.isEmpty ? null : before,
            noteAfter: after.isEmpty ? null : after,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notas guardadas.')), // i18n
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No pudimos guardar. Probá de nuevo.')), // i18n
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancelAppointment() async {
    final palette = AppPalette.of(context);
    final confirmed = await _confirmActionDialog(
      context,
      palette: palette,
      title: 'Cancelar reserva', // i18n
      body: '¿Cancelar esta sesión? El alumno será notificado.', // i18n
      confirmLabel: 'Cancelar sesión', // i18n
      cancelLabel: 'Mantener', // i18n
    );
    if (!confirmed || !mounted) return;

    try {
      await ref.read(appointmentRepositoryProvider).cancel(
            appointment: widget.appointment,
            actorUid: widget.trainerId,
            reason: 'Cancelado por el coach', // i18n
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesión cancelada.')), // i18n
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos cancelar la sesión.')), // i18n
      );
    }
  }

  Future<void> _cancelSeries() async {
    final palette = AppPalette.of(context);
    final confirmed = await _confirmActionDialog(
      context,
      palette: palette,
      title: 'Cancelar toda la serie', // i18n
      body:
          'Se cancelan todas las sesiones futuras de esta serie recurrente (las que faltan más de 24h). No se puede deshacer.', // i18n
      confirmLabel: 'Cancelar serie', // i18n
      cancelLabel: 'No', // i18n
    );
    if (!confirmed || !mounted) return;

    try {
      final n =
          await ref.read(appointmentRepositoryProvider).cancelFutureSeries(
                recurringId: widget.appointment.recurringId!,
                trainerId: widget.trainerId,
                actorUid: widget.trainerId,
                reason: 'Cancelado por el coach', // i18n
              );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            n == 0
                ? 'No había sesiones futuras para cancelar.' // i18n
                : 'Se cancelaron $n sesiones de la serie.', // i18n
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos cancelar la serie.')), // i18n
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final appt = widget.appointment;

    final end = appt.startsAt.add(Duration(minutes: appt.durationMin));
    final timeLabel =
        '${AgendaFormatters.formatTime(appt.startsAt)} – ${AgendaFormatters.formatTime(end)} · ${appt.durationMin} min'; // i18n

    final profileAsync = ref.watch(userPublicProfileProvider(appt.athleteId));
    final rawName =
        profileAsync.valueOrNull?.displayName ?? appt.athleteDisplayName;
    final athleteName = (_isRawUid(rawName) || rawName.trim().isEmpty)
        ? 'Alumno'
        : rawName; // i18n

    final canCancel = !widget.isPast &&
        appt.startsAt.difference(DateTime.now().toUtc()) >
            const Duration(hours: 24);
    final isWithin24h = !widget.isPast && !canCancel;
    final isRecurring = appt.recurringId != null;

    return AlertDialog(
      backgroundColor: palette.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Rango horario
          Text(
            timeLabel,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: palette.textPrimary,
            ),
          ),
          if (isRecurring) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: palette.highlight.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9999),
                border: Border.all(color: palette.highlight),
              ),
              child: Text(
                'SERIE RECURRENTE', // i18n
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  letterSpacing: 1.2,
                  color: palette.highlight,
                ),
              ),
            ),
          ],
        ],
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Athlete row — NON-TAPPABLE (ADR-AGW-8) ──────────────────
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: palette.accent.withAlpha(40),
                      border: Border.all(color: palette.accent),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _initials(athleteName),
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: palette.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      athleteName,
                      style: GoogleFonts.barlow(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: palette.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Sin ícono de chevron — no es tappeable (ADR-AGW-8).
                ],
              ),
              const SizedBox(height: 16),

              // ── Antes de la sesión ────────────────────────────────────
              Text(
                'ANTES DE LA SESIÓN', // i18n
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _beforeController,
                maxLines: 3,
                style: TextStyle(color: palette.textPrimary),
                decoration: InputDecoration(
                  hintText:
                      'Ej: traer banda, viene de lesión de rodilla…', // i18n
                  hintStyle: TextStyle(color: palette.textMuted),
                  filled: true,
                  fillColor: palette.bg,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.accent, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Recordatorio (post) ───────────────────────────────────
              Text(
                'RECORDATORIO (POST)', // i18n
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _afterController,
                maxLines: 3,
                style: TextStyle(color: palette.textPrimary),
                decoration: InputDecoration(
                  hintText:
                      'Ej: subió a 80kg, la próxima bajar volumen…', // i18n
                  hintStyle: TextStyle(color: palette.textMuted),
                  filled: true,
                  fillColor: palette.bg,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: palette.accent, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // ── Guardar notas ─────────────────────────────────────────
              ElevatedButton(
                onPressed: _saving ? null : _saveNotes,
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.bg,
                  minimumSize: const Size.fromHeight(48),
                  shape: const StadiumBorder(),
                  disabledBackgroundColor:
                      palette.accent.withValues(alpha: 0.3),
                ),
                child: _saving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.bg,
                        ),
                      )
                    : Text(
                        'GUARDAR NOTAS', // i18n
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          letterSpacing: 1.4,
                        ),
                      ),
              ),

              // ── Cancelar ─────────────────────────────────────────────
              if (!widget.isPast) ...[
                const SizedBox(height: 12),
                if (canCancel)
                  OutlinedButton(
                    onPressed: _cancelAppointment,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: palette.highlight),
                      foregroundColor: palette.highlight,
                      minimumSize: const Size.fromHeight(48),
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      'CANCELAR RESERVA', // i18n
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        letterSpacing: 1.4,
                      ),
                    ),
                  )
                else if (isWithin24h)
                  Center(
                    child: Text(
                      'No se puede cancelar (menos de 24h).', // i18n
                      style: GoogleFonts.barlow(
                        fontSize: 13,
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                if (isRecurring) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _cancelSeries,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: palette.danger),
                      foregroundColor: palette.danger,
                      minimumSize: const Size.fromHeight(48),
                      shape: const StadiumBorder(),
                    ),
                    child: Text(
                      'CANCELAR TODA LA SERIE', // i18n
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(foregroundColor: palette.textMuted),
          child: Text(
            'Cerrar', // i18n
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

// ─── Confirm dialog (local helper) ───────────────────────────────────────────

/// Dialog de confirmación reutilizable — idioma web (AlertDialog).
/// Mirror del helper en session_detail_sheet.dart pero sin depender de AppL10n.
Future<bool> _confirmActionDialog(
  BuildContext context, {
  required AppPalette palette,
  required String title,
  required String body,
  required String confirmLabel,
  required String cancelLabel,
}) async {
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
            backgroundColor: palette.highlight,
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
