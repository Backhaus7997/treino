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

import '../../../../../app/theme/app_palette.dart';
import '../../../../../core/utils/appointment_window.dart';
import '../../../../workout/application/session_providers.dart'
    show currentUidProvider;
import 'agenda_web_calendar.dart';
import 'agenda_web_day_list.dart';
import 'agenda_web_helpers.dart';
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

  Future<void> _openNewSessionDialog(BuildContext context) async {
    await showDialog<bool>(
      context: context,
      builder: (_) => NewSessionDialog(
        initialDate: _selectedDay,
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
                                _DayPanelHeader(
                                  day: selectedDay,
                                  onNewSession: () =>
                                      _openNewSessionDialog(context),
                                  onMisHorarios: () => _openAvailabilityEditor(
                                      context, trainerId),
                                ),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: AgendaWebDayList(
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
        borderRadius: BorderRadius.circular(16),
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
            foregroundColor: palette.bg,
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
