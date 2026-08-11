// NOTE: el Scaffold y el SafeArea los provee CoachHubScaffold (el shell).
// NO los agregues acá (ADR-CHW-005).
//
// PR-C — Grilla semanal (time-grid) de la Agenda web.
// Todas las strings están en español hardcodeado + comentario // i18n.
// NO se usa AppL10n en este archivo (constraint C-6).
//
// El cobro por LOTE (selección múltiple + BatchCobrarDialog) vive en
// AgendaWebDayList y NO existe acá: la vista semana desmonta la lista de día,
// así que en modo semana no hay cobro por lote. Es una decisión tomada, no una
// regresión — el flujo sigue disponible volviendo a la vista DÍA.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../../core/utils/argentina_time.dart';
import '../../../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../../coach/application/agenda_providers.dart';
import '../../../../coach/domain/appointment.dart';
import '../../../../coach/domain/wall_clock.dart';
import '../../../../coach/presentation/agenda_formatters.dart';
import '../../../../coach/presentation/session_layout.dart';
import '../../../../profile/application/user_public_profile_providers.dart';
import 'agenda_web_helpers.dart';
import 'appointment_detail_dialog.dart';
import 'new_session_dialog.dart';
import 'week_grid_geometry.dart';

// ─── Constantes locales de composición ────────────────────────────────────────

/// Alto MÍNIMO de la fila de encabezados (nombre del día + número).
///
/// Es un piso, no una altura clavada, y son 44 y no 39 por dos razones que se
/// pisan entre sí:
///   - 44pt es el target táctil mínimo del proyecto (issue #619). El encabezado
///     es tappeable (vuelve a la vista DÍA), así que tiene que cumplirlo.
///   - los dos `Text` de la celda escalan con el `textScaler`. En web el factor
///     sale del tamaño de fuente raíz del navegador (Chrome "Grande" = 1.25,
///     "Muy grande" = 1.5), y a partir de 1.2 el contenido NO entra en 44: con
///     una altura clavada eso era un RenderFlex overflow en las siete columnas.
const double _kHeaderHeight = 44.0;

/// Ancho útil mínimo del contenido de un bloque para mostrar el layout
/// completo (hora + alumno + fin).
///
/// Por debajo de este umbral el bloque muestra SÓLO la hora, en un `Flexible`
/// con ellipsis: con tres sesiones superpuestas en un viewport de 900px el
/// carril queda en ~35px y un `Text` no flexible desborda (RenderFlex
/// overflow, que en widget tests es una excepción).
const double _kMinContentW = 56.0;

/// Padding horizontal del contenido del bloque en el layout completo.
const double _kBlockPadH = 6.0;

/// Ancho de la franja de acento izquierda del bloque.
const double _kStripeW = 3.0;

/// Alto a partir del cual el contenido del bloque se apila en vertical.
const double _kStackedContentH = 52.0;

/// Alto a partir del cual además entra la hora de fin.
const double _kEndTimeH = 68.0;

// ─── AgendaWebWeekGrid ────────────────────────────────────────────────────────

/// Grilla semanal estilo time-grid para la Agenda del Coach Hub web.
///
/// Muestra las siete columnas de la semana que contiene [anchorDay] (lunes a
/// domingo, ver `weekStartFor`) sobre una grilla horaria compartida: el rango
/// horario se calcula UNA vez para toda la semana (`weekHourRange`) para que
/// las filas de las siete columnas alineen.
///
/// ADR-7: `Appointment.startsAt` es wall-clock UTC flotante. La ubicación de
/// los bloques y el bucketing por día leen `hour`/`minute`/`year`/`month`/`day`
/// en CRUDO — un `.toLocal()` correría todo 3 horas en ART. Las comparaciones
/// pasado/futuro usan [nowWall]; los conceptos de calendario ("hoy", la columna
/// resaltada) derivan de [argentinaNow] para que un navegador fuera de ART no
/// corra la columna de hoy respecto de los bloques.
///
/// No hay drag-to-reschedule: `firestore.rules` deja `startsAt` inmutable en el
/// único update path del trainer.
class AgendaWebWeekGrid extends ConsumerStatefulWidget {
  const AgendaWebWeekGrid({
    super.key,
    required this.trainerId,
    required this.anchorDay,
    required this.rangeFrom,
    required this.rangeTo,
    required this.onDaySelected,
  });

  /// Trainer dueño de los turnos.
  final String trainerId;

  /// Cualquier día de la semana a mostrar. Sólo se usan y/m/d.
  final DateTime anchorDay;

  /// Inicio de la ventana del stream — la MISMA que usa la lista de día, para
  /// no abrir una suscripción nueva ni pedir otro índice.
  final DateTime rangeFrom;

  /// Fin de la ventana del stream.
  final DateTime rangeTo;

  /// Se dispara al tocar el encabezado de una columna (volver al día).
  final ValueChanged<DateTime> onDaySelected;

  @override
  ConsumerState<AgendaWebWeekGrid> createState() => _AgendaWebWeekGridState();
}

class _AgendaWebWeekGridState extends ConsumerState<AgendaWebWeekGrid> {
  final ScrollController _controller = ScrollController();

  /// Auto-scroll una sola vez por semana mostrada (se resetea al cambiar de
  /// semana), y recién cuando los datos llegaron: una sesión temprana baja
  /// `startHour` y corre todos los offsets.
  bool _didAutoScroll = false;

  @override
  void didUpdateWidget(covariant AgendaWebWeekGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (weekStartFor(oldWidget.anchorDay) != weekStartFor(widget.anchorDay)) {
      _didAutoScroll = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final apptAsync = ref.watch(
      trainerAppointmentsStreamProvider(
        TrainerAppointmentsKey(
          trainerId: widget.trainerId,
          fromDate: widget.rangeFrom,
          toDate: widget.rangeTo,
        ),
      ),
    );

    final weekStart = weekStartFor(widget.anchorDay);
    final days = List<DateTime>.generate(
      7,
      (i) => weekStart.add(Duration(days: i)),
    );

    // ── Partición por día calendario ────────────────────────────────────────
    // Se filtra por campos de fecha (no por rango) para no depender de los
    // bordes inclusivos de `watchForTrainer`. Una sola pasada O(N).
    final byDay = List<List<Appointment>>.generate(7, (_) => <Appointment>[]);
    for (final a in apptAsync.valueOrNull ?? const <Appointment>[]) {
      if (a.status != AppointmentStatus.confirmed) continue;
      final idx =
          DateTime.utc(a.startsAt.year, a.startsAt.month, a.startsAt.day)
              .difference(weekStart)
              .inDays;
      if (idx < 0 || idx > 6) continue;
      byDay[idx].add(a);
    }
    final weekAppts = <Appointment>[for (final day in byDay) ...day];

    // ── Nombres: UNA resolución por athleteId distinto de la semana ─────────
    // Un ref.watch por bloque (como hacen la lista de día y el day timeline)
    // es razonable para 5 tarjetas y desperdicio para ~35 bloques.
    final names = <String, String>{};
    for (final a in weekAppts) {
      if (names.containsKey(a.athleteId)) continue;
      final profile =
          ref.watch(userPublicProfileProvider(a.athleteId)).valueOrNull;
      final raw = profile?.displayName ?? a.athleteDisplayName;
      names[a.athleteId] =
          (isRawUid(raw) || raw.trim().isEmpty) ? 'Alumno' : raw; // i18n
    }

    // ── Rango horario compartido por las siete columnas ─────────────────────
    final range = weekHourRange(weekAppts);

    // ── "Hoy" y línea de ahora (calendario ⇒ argentinaNow) ─────────────────
    final nowArt = argentinaNow();
    final todayUtc = DateTime.utc(nowArt.year, nowArt.month, nowArt.day);
    final todayIdx = days.indexWhere((d) => d == todayUtc);
    final nowMinutes = nowArt.hour * 60 + nowArt.minute;
    final showNowLine = todayIdx >= 0 &&
        nowMinutes >= range.startHour * 60 &&
        nowMinutes <= range.endHour * 60;

    // Comparación pasado/futuro contra startsAt ⇒ wall-clock (ADR-7).
    final now = nowWall();

    // ── Auto-scroll (una vez por semana, con los datos ya en mano) ──────────
    if (!_didAutoScroll && apptAsync.hasValue) {
      _didAutoScroll = true;
      double target = 0;
      if (showNowLine) {
        target = (nowMinutes - range.startHour * 60) * kWeekPxPerMin - 100;
      } else if (weekAppts.isNotEmpty) {
        final firstStart = weekAppts
            .map((a) => a.startsAt.hour * 60 + a.startsAt.minute)
            .reduce(math.min);
        target = (firstStart - range.startHour * 60) * kWeekPxPerMin - 40;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_controller.hasClients) return;
        final maxExtent = _controller.position.maxScrollExtent;
        _controller.jumpTo(target.clamp(0.0, maxExtent));
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // El ancho de columna se calcula UNA vez y se enhebra tanto al
        // encabezado como al cuerpo — nunca se delega a un Expanded, o las
        // celdas del header dejarían de alinear con las columnas.
        final colWidth = (constraints.maxWidth - kWeekGutter) / 7;
        final geo = WeekGridGeometry(
          startHour: range.startHour,
          endHour: range.endHour,
          colWidth: colWidth,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _WeekHeaderRow(
              days: days,
              colWidth: colWidth,
              todayIdx: todayIdx,
              onDayTap: widget.onDaySelected,
            ),
            Container(height: 1, color: palette.border),
            Expanded(
              // TreinoStateSwitcher es obligatorio para cambios async visibles
              // (docs/design-system.md). El branch `error` NO puede colapsar a
              // la misma pinta que `data: []`: un trainer con el listener
              // rechazado vería una semana vacía perfectamente plausible.
              child: TreinoStateSwitcher(
                childKey: ValueKey(
                  apptAsync.when(
                    loading: () => 'loading',
                    error: (_, __) => 'error',
                    data: (_) => 'data',
                  ),
                ),
                child: apptAsync.when(
                  loading: () => Center(
                    child: CircularProgressIndicator(color: palette.accent),
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
                  data: (_) => SizedBox.expand(
                    child: _buildCanvas(
                      palette: palette,
                      geo: geo,
                      days: days,
                      byDay: byDay,
                      names: names,
                      todayIdx: todayIdx,
                      todayUtc: todayUtc,
                      nowMinutes: nowMinutes,
                      showNowLine: showNowLine,
                      now: now,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Lienzo scrolleable ──────────────────────────────────────────────────────

  Widget _buildCanvas({
    required AppPalette palette,
    required WeekGridGeometry geo,
    required List<DateTime> days,
    required List<List<Appointment>> byDay,
    required Map<String, String> names,
    required int todayIdx,
    required DateTime todayUtc,
    required int nowMinutes,
    required bool showNowLine,
    required DateTime now,
  }) {
    // Scrollbar explícita: el lienzo pasa los 1000px de alto dentro de un panel
    // de ~700 en una superficie de mouse; day_timeline es táctil y no la
    // necesita, una grilla web sí.
    return Scrollbar(
      controller: _controller,
      child: SingleChildScrollView(
        controller: _controller,
        child: SizedBox(
          height: geo.contentHeight,
          child: Stack(
            children: [
              // ORDEN DE CAPAS (Stack pinta los hijos posteriores ENCIMA):
              // 1) grilla, 2) columnas con sus bloques, 3) línea de ahora.
              // Invertido, cada bloque quedaría tachado por las reglas horarias.
              // Las reglas son Containers sin hijos (hitTestSelf false), así
              // que los taps de fondo igual llegan al onTapUp de la columna.
              ..._buildGrid(
                palette: palette,
                geo: geo,
                days: days,
                todayIdx: todayIdx,
                todayUtc: todayUtc,
              ),
              Positioned.fill(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(width: kWeekGutter),
                    for (int i = 0; i < 7; i++)
                      _DayColumn(
                        day: days[i],
                        appointments: byDay[i],
                        names: names,
                        geo: geo,
                        trainerId: widget.trainerId,
                        now: now,
                      ),
                  ],
                ),
              ),
              if (showNowLine)
                _NowLine(
                  palette: palette,
                  geo: geo,
                  nowMinutes: nowMinutes,
                  columnIndex: todayIdx,
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Reglas horarias, etiquetas y divisores ──────────────────────────────────

  List<Widget> _buildGrid({
    required AppPalette palette,
    required WeekGridGeometry geo,
    required List<DateTime> days,
    required int todayIdx,
    required DateTime todayUtc,
  }) {
    final widgets = <Widget>[];

    // Tintes de columna — primero de todo, debajo de las reglas.
    for (int i = 0; i < 7; i++) {
      final isPastDay = days[i].isBefore(todayUtc);
      if (!isPastDay && i != todayIdx) continue;
      widgets.add(
        Positioned(
          left: kWeekGutter + i * geo.colWidth,
          width: geo.colWidth,
          top: 0,
          bottom: 0,
          child: ColoredBox(
            color: i == todayIdx
                ? palette.accent.withValues(alpha: 0.04)
                : palette.border.withAlpha(30),
          ),
        ),
      );
    }

    for (int h = geo.startHour; h <= geo.endHour; h++) {
      final top = (h - geo.startHour) * kWeekHourHeight;

      widgets.add(
        Positioned(
          top: top,
          left: kWeekGutter,
          right: 0,
          child: Container(height: 1, color: palette.border),
        ),
      );

      if (h < geo.endHour || h == geo.startHour) {
        widgets.add(
          Positioned(
            top: top - 8,
            left: 0,
            width: kWeekGutter - 8,
            child: Text(
              '${h.toString().padLeft(2, '0')}:00',
              textAlign: TextAlign.right,
              style: GoogleFonts.barlowCondensed(
                fontSize: 11,
                color: palette.textMuted,
              ),
            ),
          ),
        );
      }

      if (h < geo.endHour) {
        widgets.add(
          Positioned(
            top: top + kWeekHourHeight / 2,
            left: kWeekGutter,
            right: 0,
            child: Container(height: 1, color: palette.border.withAlpha(60)),
          ),
        );
      }
    }

    // Divisores verticales (borde izquierdo de cada columna).
    for (int i = 0; i < 7; i++) {
      widgets.add(
        Positioned(
          left: kWeekGutter + i * geo.colWidth,
          top: 0,
          bottom: 0,
          child: Container(width: 1, color: palette.border.withAlpha(60)),
        ),
      );
    }

    return widgets;
  }
}

// ─── Encabezado de la semana ──────────────────────────────────────────────────

/// Fila fija con el nombre y el número de cada uno de los siete días.
///
/// Usa el MISMO `colWidth` que el cuerpo (nunca `Expanded`), así las celdas
/// alinean exactamente con las columnas.
class _WeekHeaderRow extends StatelessWidget {
  const _WeekHeaderRow({
    required this.days,
    required this.colWidth,
    required this.todayIdx,
    required this.onDayTap,
  });

  final List<DateTime> days;
  final double colWidth;
  final int todayIdx;
  final ValueChanged<DateTime> onDayTap;

  @override
  Widget build(BuildContext context) {
    // `ConstrainedBox` y no `SizedBox`: [_kHeaderHeight] es un PISO. Clavar la
    // altura recortaba las celdas apenas el navegador escalaba el texto.
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _kHeaderHeight),
      child: Row(
        children: [
          const SizedBox(width: kWeekGutter),
          for (int i = 0; i < 7; i++)
            SizedBox(
              width: colWidth,
              child: _WeekHeaderCell(
                day: days[i],
                isToday: i == todayIdx,
                onTap: () => onDayTap(days[i]),
              ),
            ),
        ],
      ),
    );
  }
}

/// Celda de un día en el encabezado — es un BOTÓN: vuelve a la vista DÍA.
class _WeekHeaderCell extends StatelessWidget {
  const _WeekHeaderCell({
    required this.day,
    required this.isToday,
    required this.onTap,
  });

  final DateTime day;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = isToday ? palette.accent : palette.textMuted;

    // container: true evita que el nodo se funda con las celdas vecinas; el
    // onTap acá es lo que hace hasTapAction true (la regresión del issue #618).
    // La etiqueta es una frase autocontenida: el texto fusionado de los hijos
    // ("Lunes\n3") no dice nada sobre lo que pasa al activar la celda, y ésta
    // es el único camino DENTRO de la grilla para volver al día.
    return Semantics(
      container: true,
      button: true,
      label: 'Ver el ${spanishWeekdays[day.weekday - 1]} ${day.day}', // i18n
      onTap: onTap,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: ConstrainedBox(
              // El target real vive ACÁ: el Row del encabezado centra sus
              // hijos, así que sin este piso el Column (mainAxisSize.min)
              // colapsa a sus ~39pt intrínsecos y el botón queda por debajo
              // del mínimo de 44 (issue #619).
              constraints: const BoxConstraints(minHeight: _kHeaderHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    spanishWeekdays[day.weekday - 1], // i18n
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      letterSpacing: 0.6,
                      color: color,
                    ),
                  ),
                  Text(
                    '${day.day}',
                    maxLines: 1,
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: isToday ? palette.accent : palette.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Columna de un día ────────────────────────────────────────────────────────

/// Una columna-día: superficie de tap para crear + los bloques de ese día.
///
/// La columna es dueña de SU [day], así que no hay que despejar el día a
/// partir de `(dx - gutter) / colWidth` (y no hay fencepost que errar).
///
/// NUNCA se anidan GestureDetectors: la superficie de fondo usa `onTapUp`
/// (sólo tap) para que un drag vertical caiga al scrollable en vez de pelear
/// la arena de gestos.
class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.day,
    required this.appointments,
    required this.names,
    required this.geo,
    required this.trainerId,
    required this.now,
  });

  final DateTime day;
  final List<Appointment> appointments;
  final Map<String, String> names;
  final WeekGridGeometry geo;
  final String trainerId;
  final DateTime now;

  void _openNewSession(BuildContext context, double localDy) {
    // El snapping garantiza la precisión de minuto que asertea
    // Appointment.create, y el tope de `snap` evita un TimeOfDay(hour: 24).
    final minute = geo.snap(geo.minuteAtY(localDy));
    showDialog<bool>(
      context: context,
      builder: (_) => NewSessionDialog(
        initialDate: day,
        initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // computeSessionLayout es DAY-BLIND (keyea sólo en hour*60+minute), por eso
    // se llama una vez por columna, ya particionado.
    final layouts = computeSessionLayout(appointments);

    return SizedBox(
      width: geo.colWidth,
      child: Stack(
        children: [
          Positioned.fill(
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              // Siete superficies "tocar para crear" no aportan nada a un
              // lector de pantalla y ensucian el recorrido.
              child: ExcludeSemantics(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) =>
                      _openNewSession(context, details.localPosition.dy),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          for (final layout in layouts)
            _WeekBlock(
              appointment: layout.appointment,
              athleteName:
                  names[layout.appointment.athleteId] ?? 'Alumno', // i18n
              trainerId: trainerId,
              geo: geo,
              laneIndex: layout.columnIndex,
              laneCount: layout.columnCount,
              isPast: layout.appointment.startsAt.isBefore(now),
            ),
        ],
      ),
    );
  }
}

// ─── Bloque de sesión ─────────────────────────────────────────────────────────

/// Un turno posicionado dentro de su columna-día.
///
/// El contenido es adaptativo en ALTO (apilado vs. en línea) y en ANCHO (por
/// debajo de [_kMinContentW] sólo la hora, siempre `Flexible` + ellipsis).
class _WeekBlock extends StatelessWidget {
  const _WeekBlock({
    required this.appointment,
    required this.athleteName,
    required this.trainerId,
    required this.geo,
    required this.laneIndex,
    required this.laneCount,
    required this.isPast,
  });

  final Appointment appointment;
  final String athleteName;
  final String trainerId;
  final WeekGridGeometry geo;
  final int laneIndex;
  final int laneCount;
  final bool isPast;

  void _openDetail(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AppointmentDetailDialog(
        appointment: appointment,
        trainerId: trainerId,
        isPast: isPast,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final appt = appointment;

    // ADR-7: campos CRUDOS de un wall-clock UTC.
    final startMin = appt.startsAt.hour * 60 + appt.startsAt.minute;
    final endsAt = appt.startsAt.add(Duration(minutes: appt.durationMin));
    final top = geo.yForMinute(startMin);

    // Alto: primero el piso de legibilidad, DESPUÉS el techo del lienzo. Al
    // revés, el piso volvería a meter el desborde que el clip saca (una sesión
    // 23:55 + 10' deja ~5px de lienzo y pediría un bloque de 30). El techo
    // también contiene un durationMin absurdo: el campo es un int sin
    // validación ni en el modelo ni en las rules.
    final maxH = math.max(geo.contentHeight - top, 1.0);
    final desiredH = math.max(appt.durationMin * kWeekPxPerMin, kWeekMinBlockH);
    final clipped = desiredH > maxH;
    final height = math.min(desiredH, maxH);

    final innerW = geo.colWidth - 2 * kWeekColInset;
    final laneW = innerW / laneCount;
    final left = kWeekColInset + laneIndex * laneW;
    // El piso es 4 y no 1: el Row interno tiene una franja fija de 3px, así que
    // por debajo de 4 el propio bloque desbordaría.
    final width = math.max(laneW - kWeekLaneGap, 4.0);

    final radius = clipped
        ? const BorderRadius.only(
            topLeft: Radius.circular(8),
            topRight: Radius.circular(8),
          )
        : BorderRadius.circular(8);

    final timeLabel = AgendaFormatters.formatTime(appt.startsAt);
    final endLabel = AgendaFormatters.formatTime(endsAt);

    final visual = Opacity(
      opacity: isPast ? 0.55 : 1.0,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => _openDetail(context),
          child: Container(
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: palette.highlight.withAlpha(30),
              borderRadius: radius,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: _kStripeW,
                  decoration: BoxDecoration(
                    color: palette.highlight,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(8),
                      bottomLeft: Radius.circular(clipped ? 0 : 8),
                    ),
                  ),
                ),
                Expanded(
                  child: _BlockContent(
                    palette: palette,
                    width: width,
                    height: height,
                    timeLabel: timeLabel,
                    endLabel: endLabel,
                    athleteName: athleteName,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Positioned(
      top: top,
      left: left,
      width: width,
      height: height,
      // container: true evita que el nodo se funda con los vecinos; el onTap
      // acá es lo que hace hasTapAction true (la regresión del issue #618).
      // La etiqueta es una frase autocontenida: el recorrido por orden de
      // pintado hace inútil un "09:00" suelto.
      child: Semantics(
        container: true,
        button: true,
        label: 'Sesión con $athleteName, $timeLabel a $endLabel', // i18n
        onTap: () => _openDetail(context),
        child: ExcludeSemantics(child: visual),
      ),
    );
  }
}

/// Contenido interno del bloque, adaptativo en alto y en ancho.
class _BlockContent extends StatelessWidget {
  const _BlockContent({
    required this.palette,
    required this.width,
    required this.height,
    required this.timeLabel,
    required this.endLabel,
    required this.athleteName,
  });

  final AppPalette palette;
  final double width;
  final double height;
  final String timeLabel;
  final String endLabel;
  final String athleteName;

  @override
  Widget build(BuildContext context) {
    final timeStyle = GoogleFonts.barlowCondensed(
      fontWeight: FontWeight.w700,
      fontSize: 12,
      color: palette.highlight,
    );
    final nameStyle = GoogleFonts.barlow(
      fontSize: 11,
      color: palette.textPrimary,
    );

    final contentW = width - _kStripeW - 2 * _kBlockPadH;

    // Carril angosto: sólo la hora, y flexible para que jamás desborde.
    if (contentW < _kMinContentW) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            Flexible(
              child: Text(
                timeLabel,
                style: timeStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    // Bloque bajo: hora + alumno en línea, ambos flexibles.
    if (height < _kStackedContentH) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _kBlockPadH,
          vertical: 2,
        ),
        child: Row(
          children: [
            Flexible(
              child: Text(
                timeLabel,
                style: timeStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                athleteName,
                style: nameStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    // Bloque alto: apilado, con la hora de fin sólo si hay lugar de sobra.
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _kBlockPadH,
        vertical: 4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            timeLabel,
            style: timeStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            athleteName,
            style: nameStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (height >= _kEndTimeH) ...[
            const SizedBox(height: 1),
            Text(
              endLabel,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w500,
                fontSize: 11,
                color: palette.highlight.withAlpha(180),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Línea de "ahora" ─────────────────────────────────────────────────────────

/// Marca la hora actual SÓLO sobre la columna de hoy, más un punto en la
/// canaleta a la misma altura.
///
/// Sin `Timer`: la posición se calcula en cada build, igual que day_timeline.
/// Un timer periódico es un riesgo conocido en esta suite de tests.
class _NowLine extends StatelessWidget {
  const _NowLine({
    required this.palette,
    required this.geo,
    required this.nowMinutes,
    required this.columnIndex,
  });

  final AppPalette palette;
  final WeekGridGeometry geo;
  final int nowMinutes;
  final int columnIndex;

  @override
  Widget build(BuildContext context) {
    const dotSize = 8.0;
    final top = geo.yForMinute(nowMinutes) - 1;

    return Positioned(
      top: top,
      left: 0,
      right: 0,
      child: SizedBox(
        height: 2,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: kWeekGutter + columnIndex * geo.colWidth,
              width: geo.colWidth,
              top: 0,
              child: Container(height: 2, color: palette.accent),
            ),
            Positioned(
              left: kWeekGutter - dotSize / 2 - 6,
              top: -(dotSize / 2) + 1,
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
