/// Fecha y hora con las que arranca "Nueva sesión" cuando nadie las eligió.
///
/// ## Por qué existe (#1490)
///
/// El sheet arrancaba siempre en 9:00. Abierto un día a las 9:51, proponía
/// una hora que ya había pasado, y REGISTRAR SESIÓN rebotaba con "No podés
/// registrar una sesión en el pasado.": el PF veía un formulario prolijo que
/// no se podía enviar sin tocar nada.
///
/// ## Regla
///
/// - Otro día, o hoy antes de las 9:00 → 9:00, como siempre.
/// - Hoy con las 9:00 ya pasadas → la próxima media hora ESTRICTAMENTE
///   posterior a [now] (9:51 → 10:00; 10:00 → 10:30). Estrictamente porque el
///   submit exige `startsAt.isAfter(nowWall)`.
/// - Hoy a las 23:30 o más ya no queda ninguna media hora → mañana a las
///   9:00, en vez de proponer otra hora del pasado.
///
/// Sólo mira la hora de PARED de [now] (año, mes, día, hora, minuto), igual
/// que el chequeo del submit: un `DateTime` UTC o local con los mismos campos
/// da el mismo resultado.
library;

/// Hora de arranque cuando la fecha no es hoy o las 9:00 todavía no pasaron.
const int kDefaultSessionHour = 9;

const int _kPasoMinutos = 30;

typedef DefaultSessionStart = ({DateTime date, int hour, int minute});

DefaultSessionStart defaultSessionStart({
  required DateTime now,
  required DateTime date,
}) {
  final esHoy =
      date.year == now.year && date.month == now.month && date.day == now.day;
  final hoy = DateTime(date.year, date.month, date.day);
  if (!esHoy) return (date: hoy, hour: kDefaultSessionHour, minute: 0);

  final minutoActual = now.hour * 60 + now.minute;
  // A las 9:00 en punto las 9:00 ya no son futuras: `>=`, no `>`.
  if (minutoActual < kDefaultSessionHour * 60) {
    return (date: hoy, hour: kDefaultSessionHour, minute: 0);
  }

  // Próximo múltiplo de 30 ESTRICTAMENTE mayor: en 14:00 o 14:00:59 ya es
  // tarde para 14:00, así que va 14:30.
  final siguiente = (minutoActual ~/ _kPasoMinutos + 1) * _kPasoMinutos;
  if (siguiente >= 24 * 60) {
    return (
      date: DateTime(date.year, date.month, date.day + 1),
      hour: kDefaultSessionHour,
      minute: 0,
    );
  }
  return (date: hoy, hour: siguiente ~/ 60, minute: siguiente % 60);
}
