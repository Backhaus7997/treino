// NOTE: el Scaffold y el SafeArea los provee CoachHubScaffold (el shell).
// NO los agregues acá (ADR-CHW-005).
//
// PR1 — Ver turnos (read-only agenda viewer).
// PR2 — Nueva Sesión (create).
// PR3a — Mis horarios (availability rules editor).
// Todas las strings están en español hardcodeado + comentario // i18n.
// NO se usa AppL10n en este archivo (constraint C-6).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../../core/utils/appointment_window.dart';
import '../../../../workout/application/session_providers.dart'
    show currentUidProvider;
import 'agenda_web_calendar.dart';
import 'agenda_web_day_list.dart';
import 'agenda_web_helpers.dart';
import '../../../../../core/widgets/treino_icon.dart';
import '../../../../coach/domain/wall_clock.dart';
import '../../widgets/coach_hub_widgets.dart' show TreinoFilterChips;
import 'agenda_week_view.dart';
import 'appointment_detail_dialog.dart';
import 'availability_editor_panel.dart';
import 'new_session_dialog.dart';

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

  /// Primer día de la semana visible en la grilla (desktop). Se mueve con las
  /// flechas; el `TableCalendar` del layout angosto no lo usa.
  DateTime _weekStart = _lunesDe(DateTime.now());

  /// 7 = semana, 1 = día. Sólo aplica a la grilla.
  int _gridDays = 7;

  static DateTime _lunesDe(DateTime d) =>
      DateTime(d.year, d.month, d.day - (d.weekday - 1));

  // Ventana deslizante: 1 mes antes → 1 año después (UTC, ADR-7).
  late final DateTime _rangeFrom;
  late final DateTime _rangeTo;

  @override
  void initState() {
    super.initState();
    // QA-COA-007: ventana rodante compartida, sin el clamp de enero roto.
    final window = rollingAppointmentWindow(DateTime.now().toUtc());
    _rangeFrom = window.from;
    _rangeTo = window.to;
  }

  Future<void> _openNewSessionDialog(
    BuildContext context, {
    DateTime? initialDate,
  }) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => NewSessionDialog(
        initialDate: initialDate ?? _selectedDay,
      ),
    );
  }

  Future<void> _openAvailabilityEditor(
    BuildContext context,
    String trainerId,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AvailabilityEditorPanel(trainerId: trainerId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trainerId = ref.watch(currentUidProvider) ?? '';
    final selectedDay = _selectedDay ?? DateTime.now();

    final calendar = AgendaWebCalendar(
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

    return LayoutBuilder(
      builder: (context, constraints) {
        // Solo usamos el layout que llena el alto cuando hay alto acotado;
        // si no, caemos al stacked scrolleable (robusto ante alturas infinitas).
        final wide =
            constraints.maxWidth >= 900 && constraints.maxHeight.isFinite;

        if (wide) {
          // Desktop: grilla de tiempo a ancho completo.
          //
          // El layout de "selector de fechas (izq) + lista del día (der)"
          // sobrevive en la rama ANGOSTA, y no por inercia: una grilla de
          // tiempo necesita ancho para que las columnas de día se lean, y
          // abajo de 900 px no lo hay. Es la misma división que hacen Google
          // Calendar y Teams entre escritorio y teléfono.
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _GridHeader(
                  weekStart: _weekStart,
                  dayCount: _gridDays,
                  onPrev: () => setState(() => _weekStart = _weekStart
                      .subtract(Duration(days: _gridDays))),
                  onNext: () => setState(() =>
                      _weekStart = _weekStart.add(Duration(days: _gridDays))),
                  onToday: () => setState(() => _weekStart = _gridDays == 7
                      ? _lunesDe(DateTime.now())
                      : DateTime.now()),
                  onDayCount: (n) => setState(() {
                    _gridDays = n;
                    _weekStart =
                        n == 7 ? _lunesDe(_weekStart) : _weekStart;
                  }),
                  onNewSession: () => _openNewSessionDialog(context),
                  onMisHorarios: () =>
                      _openAvailabilityEditor(context, trainerId),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _Panel(
                    child: AgendaWeekView(
                      trainerId: trainerId,
                      firstDay: _weekStart,
                      dayCount: _gridDays,
                      // Tocar un hueco abre el alta con esa fecha y hora ya
                      // puesta: es el gesto de Calendar y de Teams, y evita
                      // que el PF tenga que volver a tipear lo que acaba de
                      // señalar con el dedo.
                      onEmptySlotTap: (cuando) => _openNewSessionDialog(
                        context,
                        initialDate: cuando,
                      ),
                      // Mismo diálogo que abre la lista del día: tocar una
                      // sesión tiene que llevar al mismo lugar, la mires
                      // donde la mires.
                      onEventTap: (appt) => showDialog<void>(
                        context: context,
                        builder: (_) => AppointmentDetailDialog(
                          appointment: appt,
                          trainerId: trainerId,
                          // Wall-clock contra wall-clock (#671): con el
                          // instante UTC real, un turno que empieza en menos
                          // de 3 h se marcaba pasado y perdía el botón de
                          // cancelar.
                          isPast: appt.startsAt.isBefore(nowWall()),
                        ),
                      ),
                    ),
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
                        _DayPanelHeader(
                          day: selectedDay,
                          onNewSession: () => _openNewSessionDialog(context),
                          onMisHorarios: () =>
                              _openAvailabilityEditor(context, trainerId),
                        ),
                        const SizedBox(height: 12),
                        AgendaWebDayList(
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
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: child,
    );
  }
}

/// Encabezado del panel de turnos: fecha en español + botón NUEVA SESIÓN +
/// botón MIS HORARIOS (PR3a).
///
/// PR2: agrega el botón que abre [NewSessionDialog] (ADR-AGW-3).
/// PR3a: agrega el botón que abre [AvailabilityEditorPanel] (ADR-AGW-3).
class _DayPanelHeader extends StatelessWidget {
  const _DayPanelHeader({
    required this.day,
    required this.onNewSession,
    required this.onMisHorarios,
  });

  final DateTime day;
  final VoidCallback onNewSession;
  final VoidCallback onMisHorarios;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            spanishDayLabel(day).toUpperCase(), // i18n
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              letterSpacing: 0.8,
              color: palette.textMuted,
            ),
          ),
        ),
        OutlinedButton(
          onPressed: onMisHorarios,
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: palette.accent),
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            shape: const StadiumBorder(),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            'MIS HORARIOS', // i18n
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 0.8,
              color: palette.accent,
            ),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: onNewSession,
          style: ElevatedButton.styleFrom(
            backgroundColor: palette.accent,
            foregroundColor: TreinoButtonTokens.foreground(context),
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
            shape: const StadiumBorder(),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const Icon(Icons.add, size: 16),
          label: Text(
            'NUEVA SESIÓN', // i18n
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ],
    );
  }
}

/// Barra de control de la grilla: navegación, rango de días y acciones.
///
/// Va FUERA del panel de la grilla y no adentro: la grilla scrollea en
/// vertical, y unos controles que se van con el scroll obligan a subir hasta
/// arriba cada vez que querés cambiar de semana.
class _GridHeader extends StatelessWidget {
  const _GridHeader({
    required this.weekStart,
    required this.dayCount,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    required this.onDayCount,
    required this.onNewSession,
    required this.onMisHorarios,
  });

  final DateTime weekStart;
  final int dayCount;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final void Function(int) onDayCount;
  final VoidCallback onNewSession;
  final VoidCallback onMisHorarios;

  static const _meses = [
    'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
    'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
  ];

  /// "7 – 13 de septiembre" o "29 de septiembre – 5 de octubre".
  ///
  /// El mes se repite sólo cuando la semana lo cruza: escribirlo siempre en
  /// las dos puntas es ruido en el 90% de los casos.
  String get _titulo {
    if (dayCount == 1) {
      return '${weekStart.day} de ${_meses[weekStart.month - 1]}';
    }
    final fin = weekStart.add(Duration(days: dayCount - 1));
    if (fin.month == weekStart.month) {
      return '${weekStart.day} – ${fin.day} de ${_meses[weekStart.month - 1]}';
    }
    return '${weekStart.day} de ${_meses[weekStart.month - 1]} – '
        '${fin.day} de ${_meses[fin.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Row(
      children: [
        IconButton(
          key: const Key('agenda_prev'),
          onPressed: onPrev,
          icon: Icon(TreinoIcon.arrowLeft, color: palette.textPrimary),
          tooltip: 'Anterior', // i18n
        ),
        IconButton(
          key: const Key('agenda_next'),
          onPressed: onNext,
          icon: Icon(TreinoIcon.arrowRight, color: palette.textPrimary),
          tooltip: 'Siguiente', // i18n
        ),
        const SizedBox(width: AppSpacing.s8),
        OutlinedButton(
          key: const Key('agenda_today'),
          onPressed: onToday,
          style: OutlinedButton.styleFrom(
            foregroundColor: palette.textPrimary,
            side: BorderSide(color: palette.border),
            shape: const StadiumBorder(),
          ),
          child: const Text('Hoy'), // i18n
        ),
        const SizedBox(width: AppSpacing.s14),
        Text(
          _titulo,
          style: TextStyle(
            fontFamily: AppFonts.barlowCondensed,
            fontWeight: FontWeight.w700,
            fontSize: 20,
            letterSpacing: 0.5,
            color: palette.textPrimary,
          ),
        ),
        const Spacer(),
        TreinoFilterChips(
          options: const ['Día', 'Semana'], // i18n
          // Single-select: el kit toma un Set porque también sirve de
          // multi-select, pero acá los dos rangos se excluyen.
          selected: {dayCount == 1 ? 'Día' : 'Semana'}, // i18n
          onChanged: (sel) =>
              onDayCount(sel.contains('Día') ? 1 : 7), // i18n
        ),
        const SizedBox(width: AppSpacing.s14),
        OutlinedButton(
          onPressed: onMisHorarios,
          style: OutlinedButton.styleFrom(
            foregroundColor: palette.textPrimary,
            side: BorderSide(color: palette.border),
            shape: const StadiumBorder(),
          ),
          child: const Text('Mis horarios'), // i18n
        ),
        const SizedBox(width: AppSpacing.s8),
        ElevatedButton.icon(
          onPressed: onNewSession,
          icon: const Icon(TreinoIcon.plus, size: 16),
          style: ElevatedButton.styleFrom(
            backgroundColor: palette.accent,
            foregroundColor: TreinoButtonTokens.foreground(context),
            shape: const StadiumBorder(),
          ),
          label: const Text('Nueva sesión'), // i18n
        ),
      ],
    );
  }
}
