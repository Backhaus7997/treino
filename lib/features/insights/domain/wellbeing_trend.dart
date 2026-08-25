import '../../workout/domain/muscle_group.dart';

/// Un punto de la curva: UN día con registro.
///
/// [feelingLevel] es el promedio de los niveles registrados ese día, en la
/// escala 0..4 de `CheckInFeeling.index` (0 = muy mal, 4 = muy bien). Se
/// promedia porque un día puede tener varios registros —el del entreno de la
/// mañana y el diario, por ejemplo— desde que el id del documento dejó de ser
/// la fecha (#643).
///
/// [hadPain] es un OR, no un promedio: "hubo dolor ese día" es la pregunta que
/// se hace el usuario, y un día con dolor no deja de tenerlo porque el otro
/// registro del día no lo reportara.
typedef WellbeingTrendPoint = ({
  String date,
  double feelingLevel,
  bool hadPain,
});

/// Una zona y cuántos registros la nombraron en la ventana actual.
typedef WellbeingPainArea = ({MuscleGroup area, int count});

/// Serie de bienestar del usuario en una ventana, con su ventana anterior.
///
/// ⚠️ Es un CONTEO, nunca una lectura. La app registra lo que el usuario
/// reporta y le muestra su propia serie: no diagnostica, no recomienda, no
/// dice si un número es bueno o malo, y no deriva ninguna conducta de la app
/// de estos campos. [previousRecordCount] y [previousPainCount] existen para
/// que el usuario compare SU dato con SU dato —que es literalmente lo que pidió
/// el hallazgo de #643 ("hace un mes me dolía casi siempre, ahora no")— y no
/// para que la app emita un juicio sobre la diferencia.
typedef WellbeingTrend = ({
  /// Días con registro, del más viejo al más nuevo.
  List<WellbeingTrendPoint> points,

  /// Registros (no días) en la ventana actual.
  int recordCount,

  /// Registros de la ventana actual que reportaron dolor.
  int painCount,

  /// Ídem para la ventana inmediatamente anterior, del mismo largo.
  int previousRecordCount,
  int previousPainCount,

  /// Zonas nombradas en la ventana actual, de la más registrada a la menos.
  List<WellbeingPainArea> painByArea,
});

const WellbeingTrend emptyWellbeingTrend = (
  points: <WellbeingTrendPoint>[],
  recordCount: 0,
  painCount: 0,
  previousRecordCount: 0,
  previousPainCount: 0,
  painByArea: <WellbeingPainArea>[],
);

/// El chart necesita al menos dos puntos para dibujar una tendencia. Con uno
/// solo hay un dato, no una curva — y son dos situaciones distintas para el
/// usuario, con mensajes distintos (mismo contrato que
/// `MeasurementProgressChart`).
const int kWellbeingTrendMinPoints = 2;
