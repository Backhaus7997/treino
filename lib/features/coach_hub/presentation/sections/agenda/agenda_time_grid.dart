// Grilla de tiempo de la agenda — el modelo de Google Calendar y Teams.
//
// ─── Por qué no alcanzaba `TableCalendar` ───────────────────────────────────
//
// La agenda mostraba un `TableCalendar`, que es un SELECTOR DE FECHAS: una
// cuadrícula donde cada día es una celda igual a las demás, y al lado la lista
// del día elegido. Ahí una sesión de 20 minutos y una de tres horas se ven
// idénticas, dos sesiones pegadas se ven igual que dos separadas por seis
// horas, y un hueco libre no se ve en absoluto.
//
// En una grilla de tiempo el eje vertical ES el reloj: la posición dice
// cuándo, y el alto dice cuánto. Eso es lo que permite mirar una semana y
// entender de un vistazo dónde entra alguien.
//
// ─── Lo que la hace de TREINO y no una copia ────────────────────────────────
//
// Google Calendar sombrea el horario laboral porque es un dato de contexto. En
// TREINO la disponibilidad del PF ES el producto: define cuándo se lo puede
// reservar. Por eso las bandas van de fondo, debajo de las sesiones — el PF
// abre la semana y lo primero que ve no es lo que ya tiene, sino DÓNDE LE
// ENTRA UNO MÁS.
import 'package:flutter/material.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../../app/theme/tokens/tokens.dart';

/// Una sesión ubicable en la grilla.
///
/// Deliberadamente NO es `Appointment`: la grilla no sabe de Firestore ni de
/// providers, y así se puede testear con datos armados a mano. Quien la usa
/// traduce su modelo a esto.
@immutable
class AgendaEvent {
  const AgendaEvent({
    required this.id,
    required this.startsAt,
    required this.durationMin,
    required this.title,
    this.subtitle,
    this.color,
  });

  final String id;
  final DateTime startsAt;
  final int durationMin;
  final String title;
  final String? subtitle;

  /// Color del bloque. `null` = accent de la paleta.
  final Color? color;

  DateTime get endsAt => startsAt.add(Duration(minutes: durationMin));
  int get _startMinute => startsAt.hour * 60 + startsAt.minute;
  int get _endMinute => _startMinute + durationMin;
}

/// Una franja de disponibilidad, en el día de la semana ISO (1 = lunes).
@immutable
class AgendaAvailabilityBand {
  const AgendaAvailabilityBand({
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
  });

  /// ISO: 1 = lunes … 7 = domingo. Mismo criterio que `AvailabilityRule`.
  final int weekday;
  final int startMinute;
  final int endMinute;
}

/// Alto de una hora en la grilla.
///
/// 56 px: una sesión de media hora queda en 28, que es el mínimo donde todavía
/// entra un nombre legible. Más chico y las sesiones cortas se vuelven barras
/// sin texto; más grande y una jornada completa no entra sin scroll.
const double _altoHora = 56.0;

/// Ancho de la columna de horas.
const double _anchoGutter = 56.0;

/// Granularidad al tocar un hueco. Google Calendar y Teams redondean al cuarto
/// de hora; un turno a las 10:07 no lo quiere nadie.
const int _granularidadMin = 15;

/// Rango visible cuando no hay ni sesiones ni disponibilidad de dónde
/// deducirlo.
const int _horaInicioDefault = 8;
const int _horaFinDefault = 20;

/// Calendario semanal (o diario) con las horas en el eje vertical.
class AgendaTimeGrid extends StatelessWidget {
  const AgendaTimeGrid({
    super.key,
    required this.firstDay,
    required this.events,
    this.dayCount = 7,
    this.availability = const [],
    this.now,
    this.onEmptySlotTap,
    this.onEventTap,
  });

  /// Primer día mostrado. La grilla no decide cuál es: se lo dice quien la usa.
  final DateTime firstDay;

  /// Cuántos días muestra. 7 = semana, 1 = día.
  final int dayCount;

  final List<AgendaEvent> events;
  final List<AgendaAvailabilityBand> availability;

  /// Instante actual, para la línea de "ahora". Inyectable para poder testearla
  /// sin congelar el reloj global.
  final DateTime? now;

  /// Tocar un espacio libre. Recibe el día y la hora, ya redondeados.
  final void Function(DateTime)? onEmptySlotTap;

  final void Function(AgendaEvent)? onEventTap;

  DateTime _dia(int i) =>
      DateTime(firstDay.year, firstDay.month, firstDay.day + i);

  bool _esDelDia(DateTime d, DateTime dia) =>
      d.year == dia.year && d.month == dia.month && d.day == dia.day;

  /// Rango de horas visible.
  ///
  /// Mostrar 24 horas siempre significa que el 70% de la pantalla son filas
  /// vacías de madrugada y todo lo que importa queda abajo del scroll. El
  /// rango se deduce de lo que hay —sesiones y disponibilidad— con una hora de
  /// aire a cada lado.
  (int, int) get _rango {
    final marcas = <int>[
      for (final e in events) e._startMinute,
      for (final e in events) e._endMinute,
      for (final b in availability) b.startMinute,
      for (final b in availability) b.endMinute,
    ];
    if (marcas.isEmpty) return (_horaInicioDefault, _horaFinDefault);

    final desde = (marcas.reduce((a, b) => a < b ? a : b) ~/ 60) - 1;
    final hasta = ((marcas.reduce((a, b) => a > b ? a : b) + 59) ~/ 60) + 1;
    return (desde.clamp(0, 23), hasta.clamp(1, 24));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final (horaDesde, horaHasta) = _rango;
    final alto = (horaHasta - horaDesde) * _altoHora;

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final anchoDia = (constraints.maxWidth - _anchoGutter) / dayCount;

        // El encabezado va FUERA del scroll: si se va con las horas, a los
        // cinco minutos de scrollear no sabés qué columna estás mirando. Es la
        // misma decisión de Google Calendar y de Teams.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Encabezado(
              dias: [for (var i = 0; i < dayCount; i++) _dia(i)],
              hoy: now,
              anchoDia: anchoDia,
              palette: palette,
            ),
            Expanded(
              child: SingleChildScrollView(
                child: SizedBox(
                  height: alto,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Gutter(horaDesde: horaDesde, horaHasta: horaHasta),
                      for (var i = 0; i < dayCount; i++)
                        SizedBox(
                          width: anchoDia,
                          child: _ColumnaDia(
                            indice: i,
                            dia: _dia(i),
                            horaDesde: horaDesde,
                            horaHasta: horaHasta,
                            eventos: events
                                .where((e) => _esDelDia(e.startsAt, _dia(i)))
                                .toList(),
                            bandas: availability
                                .where((b) => b.weekday == _dia(i).weekday)
                                .toList(),
                            now: now != null && _esDelDia(now!, _dia(i))
                                ? now
                                : null,
                            palette: palette,
                            onEmptySlotTap: onEmptySlotTap,
                            onEventTap: onEventTap,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Fila de días, fija arriba del scroll.
class _Encabezado extends StatelessWidget {
  const _Encabezado({
    required this.dias,
    required this.hoy,
    required this.anchoDia,
    required this.palette,
  });

  final List<DateTime> dias;
  final DateTime? hoy;
  final double anchoDia;
  final AppPalette palette;

  static const _nombres = ['LUN', 'MAR', 'MIÉ', 'JUE', 'VIE', 'SÁB', 'DOM'];

  bool _esHoy(DateTime d) =>
      hoy != null &&
      d.year == hoy!.year &&
      d.month == hoy!.month &&
      d.day == hoy!.day;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          const SizedBox(width: _anchoGutter),
          for (final d in dias)
            SizedBox(
              width: anchoDia,
              child: Column(
                key: _esHoy(d) ? const Key('agenda_header_today') : null,
                children: [
                  Text(
                    _nombres[d.weekday - 1],
                    style: TextStyle(
                      fontFamily: AppFonts.barlowCondensed,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      letterSpacing: 0.8,
                      color: _esHoy(d) ? palette.accent : palette.textMuted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.hairline),
                  // El número del día en un disco cuando es hoy: es la marca
                  // que usan Calendar y Teams, y se lee sin tener que comparar
                  // con las columnas de al lado.
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: _esHoy(d)
                        ? BoxDecoration(
                            color: palette.accent,
                            shape: BoxShape.circle,
                          )
                        : null,
                    child: Text(
                      '${d.day}',
                      style: TextStyle(
                        fontFamily: AppFonts.barlowCondensed,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: _esHoy(d)
                            ? TreinoButtonTokens.foreground(context)
                            : palette.textPrimary,
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
}

/// Columna de horas de la izquierda.
class _Gutter extends StatelessWidget {
  const _Gutter({required this.horaDesde, required this.horaHasta});

  final int horaDesde;
  final int horaHasta;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizedBox(
      width: _anchoGutter,
      child: Stack(
        children: [
          for (var h = horaDesde; h < horaHasta; h++)
            Positioned(
              top: (h - horaDesde) * _altoHora,
              right: AppSpacing.s8,
              child: Text(
                '${h.toString().padLeft(2, '0')}:00',
                style: TextStyle(
                  fontFamily: AppFonts.barlow,
                  fontSize: 11,
                  height: 1,
                  color: palette.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Una columna = un día.
class _ColumnaDia extends StatelessWidget {
  const _ColumnaDia({
    required this.indice,
    required this.dia,
    required this.horaDesde,
    required this.horaHasta,
    required this.eventos,
    required this.bandas,
    required this.now,
    required this.palette,
    required this.onEmptySlotTap,
    required this.onEventTap,
  });

  final int indice;
  final DateTime dia;
  final int horaDesde;
  final int horaHasta;
  final List<AgendaEvent> eventos;
  final List<AgendaAvailabilityBand> bandas;
  final DateTime? now;
  final AppPalette palette;
  final void Function(DateTime)? onEmptySlotTap;
  final void Function(AgendaEvent)? onEventTap;

  double _y(int minutoDelDia) =>
      (minutoDelDia - horaDesde * 60) / 60 * _altoHora;

  /// Reparte en carriles los eventos que se solapan.
  ///
  /// Sin esto, dos sesiones a la misma hora se dibujan una encima de la otra y
  /// la de abajo deja de existir para quien mira — que es justo el momento en
  /// que el PF más necesita verlas: cuando se pisó.
  ///
  /// Se agrupa por solapamiento transitivo (A pisa a B y B pisa a C entran al
  /// mismo grupo, aunque A y C no se toquen) y dentro del grupo cada uno toma
  /// el primer carril libre. Es el mismo criterio de Google Calendar.
  Map<String, (int carril, int total)> _carriles() {
    final orden = [...eventos]
      ..sort((a, b) => a._startMinute.compareTo(b._startMinute));
    final resultado = <String, (int, int)>{};

    var grupo = <AgendaEvent>[];
    var finGrupo = -1;

    void cerrarGrupo() {
      if (grupo.isEmpty) return;
      final finPorCarril = <int>[];
      final carrilDe = <String, int>{};
      for (final e in grupo) {
        var carril = finPorCarril.indexWhere((f) => f <= e._startMinute);
        if (carril == -1) {
          finPorCarril.add(e._endMinute);
          carril = finPorCarril.length - 1;
        } else {
          finPorCarril[carril] = e._endMinute;
        }
        carrilDe[e.id] = carril;
      }
      for (final e in grupo) {
        resultado[e.id] = (carrilDe[e.id]!, finPorCarril.length);
      }
      grupo = [];
      finGrupo = -1;
    }

    for (final e in orden) {
      if (grupo.isNotEmpty && e._startMinute >= finGrupo) cerrarGrupo();
      grupo.add(e);
      if (e._endMinute > finGrupo) finGrupo = e._endMinute;
    }
    cerrarGrupo();
    return resultado;
  }

  @override
  Widget build(BuildContext context) {
    final carriles = _carriles();

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final ancho = constraints.maxWidth;

        return Container(
          key: Key('agenda_day_column_$indice'),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: palette.border, width: 0.5),
            ),
          ),
          child: Stack(
            children: [
              // 1. Disponibilidad, al fondo de todo.
              for (final b in bandas)
                Positioned(
                  key: Key('agenda_band_${b.weekday}_${b.startMinute}'),
                  top: _y(b.startMinute),
                  height: (b.endMinute - b.startMinute) / 60 * _altoHora,
                  left: 0,
                  right: 0,
                  child: ColoredBox(
                    color: palette.accent.withValues(alpha: 0.07),
                  ),
                ),

              // 2. Las líneas de hora.
              for (var h = horaDesde; h < horaHasta; h++)
                Positioned(
                  top: (h - horaDesde) * _altoHora,
                  left: 0,
                  right: 0,
                  child: Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: palette.border,
                  ),
                ),

              // 3. El gesto de crear. Va DEBAJO de los bloques a propósito:
              //    tocar una sesión abre la sesión, tocar el vacío crea una.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapUp: onEmptySlotTap == null
                      ? null
                      : (detalle) {
                          final minuto = horaDesde * 60 +
                              (detalle.localPosition.dy / _altoHora * 60)
                                  .round();
                          final redondeado =
                              (minuto ~/ _granularidadMin) * _granularidadMin;
                          onEmptySlotTap!(DateTime(
                            dia.year,
                            dia.month,
                            dia.day,
                            redondeado ~/ 60,
                            redondeado % 60,
                          ));
                        },
                ),
              ),

              // 4. Las sesiones.
              for (final e in eventos)
                _BloqueEvento(
                  evento: e,
                  top: _y(e._startMinute),
                  alto: e.durationMin / 60 * _altoHora,
                  carril: carriles[e.id]!.$1,
                  carriles: carriles[e.id]!.$2,
                  anchoColumna: ancho,
                  palette: palette,
                  onTap: onEventTap,
                ),

              // 5. La línea de ahora, arriba de todo.
              if (now != null)
                Positioned(
                  key: const Key('agenda_now_line'),
                  top: _y(now!.hour * 60 + now!.minute),
                  left: 0,
                  right: 0,
                  child: Container(height: 2, color: palette.danger),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// El bloque de una sesión.
class _BloqueEvento extends StatelessWidget {
  const _BloqueEvento({
    required this.evento,
    required this.top,
    required this.alto,
    required this.carril,
    required this.carriles,
    required this.anchoColumna,
    required this.palette,
    required this.onTap,
  });

  final AgendaEvent evento;
  final double top;
  final double alto;
  final int carril;
  final int carriles;
  final double anchoColumna;
  final AppPalette palette;
  final void Function(AgendaEvent)? onTap;

  @override
  Widget build(BuildContext context) {
    final color = evento.color ?? palette.accent;
    final ancho = anchoColumna / carriles;

    return Positioned(
      key: Key('agenda_event_${evento.id}'),
      top: top,
      height: alto,
      left: carril * ancho,
      width: ancho,
      child: Padding(
        // El aire va acá y no en el cálculo del ancho: así los carriles
        // reparten el ancho exacto y la separación no se acumula.
        padding: const EdgeInsets.only(right: 2, bottom: 1),
        child: GestureDetector(
          onTap: onTap == null ? null : () => onTap!(evento),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s8,
              vertical: AppSpacing.hairline,
            ),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border(left: BorderSide(color: color, width: 3)),
            ),
            // `ClipRect` y no overflow visible: una sesión de 15 minutos mide
            // 14 px y su texto no puede derramarse sobre la de abajo.
            child: ClipRect(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    evento.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppFonts.barlow,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      height: 1.2,
                      color: palette.textPrimary,
                    ),
                  ),
                  if (evento.subtitle != null)
                    Text(
                      evento.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppFonts.barlow,
                        fontSize: 11,
                        height: 1.2,
                        color: palette.textMuted,
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
