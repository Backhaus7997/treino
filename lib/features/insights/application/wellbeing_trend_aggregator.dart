import '../../checkins/domain/check_in.dart';
import '../../workout/domain/muscle_group.dart';
import '../domain/wellbeing_trend.dart';

/// Arma la serie de bienestar a partir de los check-ins crudos.
///
/// Función pura y sin Firestore a propósito: la agregación es donde están las
/// decisiones discutibles (promediar el día, ORear el dolor, contar registros y
/// no días para el ratio), y todas se testean sin emulador ni fake.
///
/// [checkIns] puede venir en cualquier orden y abarcar las DOS ventanas: se
/// parte acá según [currentStart], que es una clave de fecha `YYYY-MM-DD`. Se
/// resuelve con comparación de strings porque el formato es de ancho fijo y
/// lexicográficamente ordenado — comparar fechas ya formateadas evita
/// reintroducir una conversión de zona horaria en el medio del rollup (#379).
///
/// ⚠️ Cuenta. No interpreta. Nada de lo que devuelve puede leerse como un
/// juicio sobre la salud del usuario.
WellbeingTrend aggregateWellbeingTrend(
  List<CheckIn> checkIns, {
  required String currentStart,
}) {
  if (checkIns.isEmpty) return emptyWellbeingTrend;

  final current = <CheckIn>[];
  var previousRecordCount = 0;
  var previousPainCount = 0;

  for (final c in checkIns) {
    if (c.date.compareTo(currentStart) >= 0) {
      current.add(c);
    } else {
      previousRecordCount++;
      if (c.hasPain) previousPainCount++;
    }
  }

  // Un punto por DÍA: los registros del mismo día se promedian.
  final levelsByDay = <String, List<int>>{};
  final painByDay = <String, bool>{};
  final areaCounts = <MuscleGroup, int>{};
  var painCount = 0;

  for (final c in current) {
    levelsByDay.putIfAbsent(c.date, () => <int>[]).add(c.feeling.index);
    painByDay[c.date] = (painByDay[c.date] ?? false) || c.hasPain;
    if (c.hasPain) {
      painCount++;
      // `toSet()` por si un registro trae la misma zona dos veces: cuenta
      // registros que nombran la zona, no apariciones del string.
      for (final area in c.painAreas.toSet()) {
        areaCounts[area] = (areaCounts[area] ?? 0) + 1;
      }
    }
  }

  final days = levelsByDay.keys.toList()..sort();
  final points = <WellbeingTrendPoint>[
    for (final day in days)
      (
        date: day,
        feelingLevel: levelsByDay[day]!.reduce((a, b) => a + b) /
            levelsByDay[day]!.length,
        hadPain: painByDay[day] ?? false,
      ),
  ];

  final painByArea = areaCounts.entries
      .map((e) => (area: e.key, count: e.value))
      .toList()
    // Desempate por el orden canónico de MuscleGroup: dos zonas con el mismo
    // conteo tienen que salir SIEMPRE en el mismo orden, o la lista baila entre
    // renders sin que haya cambiado ningún dato.
    ..sort((a, b) {
      final byCount = b.count.compareTo(a.count);
      if (byCount != 0) return byCount;
      return MuscleGroup.displayOrder
          .indexOf(a.area)
          .compareTo(MuscleGroup.displayOrder.indexOf(b.area));
    });

  return (
    points: points,
    recordCount: current.length,
    painCount: painCount,
    previousRecordCount: previousRecordCount,
    previousPainCount: previousPainCount,
    painByArea: painByArea,
  );
}
