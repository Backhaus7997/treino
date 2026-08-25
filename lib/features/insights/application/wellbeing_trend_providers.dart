import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/argentina_time.dart';
import '../../checkins/application/check_in_providers.dart';
import '../../checkins/domain/check_in.dart';
import '../domain/chart_period.dart';
import '../domain/wellbeing_trend.dart';
import 'wellbeing_trend_aggregator.dart';

/// Clave de [wellbeingTrendProvider]: dueño + ventana.
///
/// [uid] explícito y no [currentUidProvider], misma convención de los demás
/// providers del hub. Ojo: acá el uid explícito NO habilita la vista del PF
/// sobre su alumno como en los otros — este dato es owner-only por reglas y
/// #643 deja compartirlo fuera de alcance. La firma es por consistencia, no
/// una puerta.
typedef WellbeingTrendKey = ({String uid, ChartPeriod period});

/// Serie de bienestar del usuario para (uid, período).
///
/// Una sola consulta cubre las DOS ventanas: se pide el rango completo
/// `previousStart..currentEnd` y el agregador lo parte. Dos lecturas serían dos
/// viajes para el mismo documento en el borde.
///
/// autoDispose: se re-evalúa al volver a montar la pantalla, igual que el resto
/// de los providers del hub.
final wellbeingTrendProvider =
    FutureProvider.autoDispose.family<WellbeingTrend, WellbeingTrendKey>(
  (ref, key) async {
    if (key.uid.isEmpty) return emptyWellbeingTrend;

    final window = key.period.windowFor(argentinaNow());
    // Los bordes de la ventana ya vienen como días de calendario ART envueltos
    // en DateTime.utc, así que sus componentes y/m/d SON el día del usuario:
    // checkInDateKey los formatea sin volver a convertir de zona.
    final checkIns = await ref.read(checkInRepositoryProvider).getRange(
          key.uid,
          fromDate: checkInDateKey(window.previousStart),
          toDate: checkInDateKey(window.currentEnd),
        );

    return aggregateWellbeingTrend(
      checkIns,
      currentStart: checkInDateKey(window.currentStart),
    );
  },
);
