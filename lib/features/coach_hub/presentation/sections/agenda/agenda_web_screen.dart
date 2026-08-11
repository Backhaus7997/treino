// NOTE: el Scaffold y el SafeArea los provee CoachHubScaffold (el shell).
// NO los agregues acá (ADR-CHW-005).
//
// PR1 — Ver turnos (read-only agenda viewer).
// PR2 — Nueva Sesión (create).
// PR3a — Mis horarios (availability rules editor).
// PR-D — Vista SEMANA (grilla horaria), opt-in y sólo en el layout ancho.
// Todas las strings están en español hardcodeado + comentario // i18n.
// NO se usa AppL10n en este archivo (constraint C-6).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../../core/utils/appointment_window.dart';
import '../../../../../core/widgets/treino_icon.dart';
import '../../../../workout/application/session_providers.dart'
    show currentUidProvider;
import 'agenda_web_calendar.dart';
import 'agenda_web_day_list.dart';
import 'agenda_web_helpers.dart';
import 'agenda_web_week_grid.dart';
import 'availability_editor_panel.dart';
import 'new_session_dialog.dart';
import 'week_grid_geometry.dart';

// ─── Modo de vista ────────────────────────────────────────────────────────────

/// Vista activa del panel de turnos.
///
/// Es un enum PROPIO y no el `CalendarFormat` de table_calendar: ese enum es
/// del calendario mensual/semanal de la izquierda, su `availableCalendarFormats`
/// está clavado en `{month: 'Mes', week: 'Semana'}` y hay tests que asertan esas
/// etiquetas exactas. Son dos ejes independientes.
enum AgendaViewMode { day, week }

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

  // Vista del panel de turnos. DÍA es el default; SEMANA es opt-in y sólo
  // existe en el layout ancho.
  //
  // El cobro por LOTE (selección múltiple + BatchCobrarDialog) vive dentro de
  // AgendaWebDayList: la vista SEMANA la desmonta, así que en semana no hay
  // cobro por lote. Es una decisión tomada, no una regresión — el flujo sigue
  // disponible volviendo a DÍA.
  AgendaViewMode _viewMode = AgendaViewMode.day;

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

  /// Corre la semana visible [deltaDays] días, moviendo AMBOS `_selectedDay` y
  /// `_focusedDay`.
  ///
  /// El clamp a `[_rangeFrom, _rangeTo]` no es cosmético: fuera de esa ventana
  /// el stream de turnos no trae nada, así que el PF vería una grilla vacía
  /// indistinguible de una semana sin sesiones.
  void _shiftWeek(int deltaDays) {
    var next = (_selectedDay ?? DateTime.now()).add(Duration(days: deltaDays));
    if (next.isBefore(_rangeFrom)) next = _rangeFrom;
    if (next.isAfter(_rangeTo)) next = _rangeTo;
    setState(() {
      _selectedDay = next;
      _focusedDay = next;
    });
  }

  void _selectDayFromWeek(DateTime day) {
    setState(() {
      _selectedDay = day;
      _focusedDay = day;
      // Tocar el encabezado de una columna es "volver al día".
      _viewMode = AgendaViewMode.day;
    });
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

        // Achicar la ventana tira la vista SEMANA (no existe en el layout
        // angosto). Sin este reset el modo quedaría latente y al ensanchar de
        // nuevo aparecería una grilla que el PF no volvió a pedir.
        if (!wide && _viewMode != AgendaViewMode.day) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _viewMode == AgendaViewMode.day) return;
            setState(() => _viewMode = AgendaViewMode.day);
          });
        }

        if (wide && _viewMode == AgendaViewMode.week) {
          // Desktop + SEMANA: un solo panel a todo el ancho con la grilla.
          // El mini-calendario de 420px se esconde: dejarlo daría columnas de
          // ~86px a 1440px de viewport.
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: SizedBox.expand(
              child: _Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _DayPanelHeader(
                      day: selectedDay,
                      title: weekRangeLabel(selectedDay),
                      onPrev: () => _shiftWeek(-7),
                      onNext: () => _shiftWeek(7),
                      viewMode: _viewMode,
                      onViewModeChanged: (m) => setState(() => _viewMode = m),
                      onNewSession: () => _openNewSessionDialog(context),
                      onMisHorarios: () =>
                          _openAvailabilityEditor(context, trainerId),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: AgendaWebWeekGrid(
                        trainerId: trainerId,
                        anchorDay: selectedDay,
                        rangeFrom: _rangeFrom,
                        rangeTo: _rangeTo,
                        onDaySelected: _selectDayFromWeek,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

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
                                  viewMode: _viewMode,
                                  onViewModeChanged: (m) =>
                                      setState(() => _viewMode = m),
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

/// "Semana del 4 al 10 de agosto" — rótulo del rango semanal que contiene
/// [anchor]. // i18n
///
/// Reusa `spanishWeekdays`/`spanishMonths` (agenda_web_helpers.dart) en vez de
/// `DateFormat`: `intl` pediría `initializeDateFormatting` en los tests.
String weekRangeLabel(DateTime anchor) {
  final start = weekStartFor(anchor);
  final end = start.add(const Duration(days: 6));
  final endMonth = spanishMonths[end.month - 1];
  if (start.month == end.month) {
    return 'Semana del ${start.day} al ${end.day} de $endMonth'; // i18n
  }
  final startMonth = spanishMonths[start.month - 1];
  return 'Semana del ${start.day} de $startMonth '
      'al ${end.day} de $endMonth'; // i18n
}

/// Encabezado del panel de turnos: fecha en español + botón NUEVA SESIÓN +
/// botón MIS HORARIOS (PR3a).
///
/// PR2: agrega el botón que abre [NewSessionDialog] (ADR-AGW-3).
/// PR3a: agrega el botón que abre [AvailabilityEditorPanel] (ADR-AGW-3).
/// PR-D: agrega, TODOS opcionales, [title] / [onPrev] / [onNext] /
/// [viewMode] + [onViewModeChanged]. Sólo los pasa el branch ancho: en null
/// el encabezado renderiza exactamente el de siempre.
class _DayPanelHeader extends StatelessWidget {
  const _DayPanelHeader({
    required this.day,
    required this.onNewSession,
    required this.onMisHorarios,
    this.title,
    this.onPrev,
    this.onNext,
    this.viewMode,
    this.onViewModeChanged,
  });

  final DateTime day;
  final VoidCallback onNewSession;
  final VoidCallback onMisHorarios;

  /// Título alternativo (el rango semanal). Null ⇒ la fecha de [day].
  final String? title;

  /// Navegación ‹ › de semana. Null ⇒ no se dibujan los chevrones.
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  /// Toggle DÍA / SEMANA. Null (cualquiera de los dos) ⇒ no se dibuja.
  final AgendaViewMode? viewMode;
  final ValueChanged<AgendaViewMode>? onViewModeChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final mode = viewMode;
    final onModeChanged = onViewModeChanged;
    final prev = onPrev;
    final next = onNext;
    final showsToggle = mode != null && onModeChanged != null;
    final showsNav = prev != null || next != null;

    final titleText = Text(
      (title ?? spanishDayLabel(day)).toUpperCase(), // i18n
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.barlowCondensed(
        fontWeight: FontWeight.w700,
        fontSize: 14,
        letterSpacing: 0.8,
        color: palette.textMuted,
      ),
    );

    final misHorariosButton = OutlinedButton(
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
    );

    final nuevaSesionButton = ElevatedButton.icon(
      onPressed: onNewSession,
      style: ElevatedButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: palette.bg,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
        shape: const StadiumBorder(),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: const Icon(TreinoIcon.plus, size: 16),
      label: Text(
        'NUEVA SESIÓN', // i18n
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 13,
          letterSpacing: 0.8,
        ),
      ),
    );

    // Sin toggle ni navegación (branch angosto): EXACTAMENTE el encabezado de
    // siempre, un Row con el título flexible.
    if (!showsToggle && !showsNav) {
      return Row(
        children: [
          Expanded(child: titleText),
          misHorariosButton,
          const SizedBox(width: 8),
          nuevaSesionButton,
        ],
      );
    }

    // Branch ancho: `Wrap` y no `Row`. Con el toggle sumado, en el umbral de
    // 900px el panel del día deja ~378px y los controles no entran — un Row
    // desborda (ya lo hacía por 37px sin el toggle). `Wrap` los baja de renglón
    // en vez de recortarlos, y a anchos de escritorio queda en un solo renglón,
    // visualmente idéntico al Row.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (prev != null)
              _NavChevron(
                icon: TreinoIcon.back,
                tooltip: 'Semana anterior', // i18n
                onPressed: prev,
              ),
            if (next != null)
              _NavChevron(
                icon: TreinoIcon.forward,
                tooltip: 'Semana siguiente', // i18n
                onPressed: next,
              ),
            if (showsNav) const SizedBox(width: 8),
            Flexible(child: titleText),
          ],
        ),
        Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (showsToggle)
              _ViewModeToggle(mode: mode, onChanged: onModeChanged),
            misHorariosButton,
            nuevaSesionButton,
          ],
        ),
      ],
    );
  }
}

// ─── Navegación de semana ─────────────────────────────────────────────────────

/// Chevron ‹ / › de la navegación semanal.
///
/// `IconButton` y no un `GestureDetector` a mano: trae solo el target de 48pt
/// y el nodo de semántica (botón + etiqueta del tooltip).
class _NavChevron extends StatelessWidget {
  const _NavChevron({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      iconSize: 18,
      color: palette.textPrimary,
      icon: Icon(icon),
    );
  }
}

// ─── Toggle DÍA / SEMANA ──────────────────────────────────────────────────────

/// Selector segmentado de la vista del panel de turnos.
class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({required this.mode, required this.onChanged});

  final AgendaViewMode mode;
  final ValueChanged<AgendaViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ViewModeChip(
            label: 'DÍA', // i18n
            semanticsLabel: 'Vista día', // i18n
            selected: mode == AgendaViewMode.day,
            onTap: () => onChanged(AgendaViewMode.day),
          ),
          _ViewModeChip(
            label: 'SEMANA', // i18n
            semanticsLabel: 'Vista semana', // i18n
            selected: mode == AgendaViewMode.week,
            onTap: () => onChanged(AgendaViewMode.week),
          ),
        ],
      ),
    );
  }
}

/// Un segmento del toggle.
///
/// `container: true` evita que el nodo se funda con el vecino; el `onTap` de la
/// semántica es lo que hace `hasTapAction` true (la regresión del issue #618),
/// y `selected` es lo que le dice al lector de pantalla cuál vista está activa.
/// El alto fijo de 44 es el target mínimo.
class _ViewModeChip extends StatelessWidget {
  const _ViewModeChip({
    required this.label,
    required this.semanticsLabel,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String semanticsLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: semanticsLabel,
      onTap: onTap,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              height: 44,
              constraints: const BoxConstraints(minWidth: 44),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: selected ? palette.accent.withAlpha(38) : null,
                borderRadius: BorderRadius.circular(9999),
              ),
              child: Text(
                label,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.8,
                  color: selected ? palette.accent : palette.textMuted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
