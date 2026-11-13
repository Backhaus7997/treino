// Filters disponibles en la vista de Discovery del Coach, además del
// specialty filter que ya existía en Etapa 2. Cada filtro tiene una
// opción `any` que significa "sin restricción" — simplifica state
// management y rendering del chip (siempre tiene label).

/// Filtro de distancia máxima desde la ubicación del athlete.
///
/// Solo se aplica cuando `athleteLocationProvider` tiene una `Position`
/// válida (permission granted). Sin location, este filtro es no-op.
enum DistanceFilter {
  any,
  km2,
  km5,
  km10;

  /// Label para mostrar en el chip / bottom sheet.
  String get label => switch (this) {
        DistanceFilter.any => 'Cualquier distancia',
        DistanceFilter.km2 => '< 2 km',
        DistanceFilter.km5 => '< 5 km',
        DistanceFilter.km10 => '< 10 km',
      };

  /// Label corto para el chip (no incluye "Cualquier distancia").
  String get chipLabel => switch (this) {
        DistanceFilter.any => 'Distancia',
        DistanceFilter.km2 => '< 2 km',
        DistanceFilter.km5 => '< 5 km',
        DistanceFilter.km10 => '< 10 km',
      };

  /// Distancia máxima en km, o null si es `any`.
  double? get maxKm => switch (this) {
        DistanceFilter.any => null,
        DistanceFilter.km2 => 2,
        DistanceFilter.km5 => 5,
        DistanceFilter.km10 => 10,
      };
}

/// Techos de las bandas del filtro de precio, en **pesos ARS enteros por mes**:
/// la misma unidad que `trainerMonthlyRate` (el onboarding lo valida entre
/// `kPrecioMinimo` y `kPrecioMaximo`, 500 a 999.999, y la app lo muestra con
/// `fmtArs`). Con estos dos números alcanza para definir las tres bandas, y las
/// etiquetas de [PriceFilter] salen de ellos: no hay un segundo lugar donde
/// escribirlos a mano y desincronizarlos.
///
/// Las bandas viejas (`< $5.000`, `$5.000-$10.000`, `> $10.000`, #1753) se
/// escribieron cuando una tarifa típica eran unos miles de pesos, y con las
/// tarifas de hoy —decenas de miles— sólo la de arriba tenía resultados. Estos
/// valores salen de los únicos datos de precio que hay en el repo: planes online
/// de 20.000-40.000, mensual presencial de 90.000-155.000
/// (`docs/paywall-alumno-suelto.md`, abril 2026), el hint de 28.000 del Hub y el
/// seed del emulador (38.000 / 45.000 / 52.000).
///
/// **Los precios en pesos se pudren con la inflación** —es exactamente lo que
/// pasó—: revisalos cuando las tarifas se muevan. Lo que NO puede romperse es
/// que las tres bandas cubran todo el rango válido sin huecos ni solapes, y eso
/// lo fija `discovery_filters_test.dart`.
///
/// Banda baja: estrictamente menor que este valor.
const int kPrecioBandaBajaHasta = 40000;

/// Banda media: de [kPrecioBandaBajaHasta] a este valor, AMBOS incluidos. La
/// alta es todo lo que lo supera.
const int kPrecioBandaMediaHasta = 100000;

/// Filtro de rango de precio mensual del PF (`trainerMonthlyRate`).
///
/// Trainers sin `trainerMonthlyRate` set son siempre incluidos (no se
/// filtran out) — el filtro solo excluye trainers cuyo rate cae fuera del
/// rango especificado.
///
/// Los nombres son relativos (`low` / `mid` / `high`) y no llevan el número
/// adentro, a propósito: el valor vive en [kPrecioBandaBajaHasta] y
/// [kPrecioBandaMediaHasta], y un nombre como `under5k` seguía mintiendo
/// después de reescalar.
enum PriceFilter {
  any,
  low,
  mid,
  high;

  /// Label para mostrar en el chip / bottom sheet.
  String get label => switch (this) {
        PriceFilter.any => 'Cualquier precio',
        PriceFilter.low => 'Menos de ${_pesos(kPrecioBandaBajaHasta)}',
        PriceFilter.mid =>
          '${_pesos(kPrecioBandaBajaHasta)} - ${_pesos(kPrecioBandaMediaHasta)}',
        PriceFilter.high => 'Más de ${_pesos(kPrecioBandaMediaHasta)}',
      };

  /// Label corto para el chip.
  String get chipLabel => switch (this) {
        PriceFilter.any => 'Precio',
        PriceFilter.low => '< \$${_miles(kPrecioBandaBajaHasta)}k',
        PriceFilter.mid =>
          '\$${_miles(kPrecioBandaBajaHasta)}-${_miles(kPrecioBandaMediaHasta)}k',
        PriceFilter.high => '> \$${_miles(kPrecioBandaMediaHasta)}k',
      };

  /// Verifica si un rate dado cae dentro del rango.
  /// Si rate es null, retorna true (no se filtra).
  ///
  /// Las tres bandas son una PARTICIÓN de los enteros: cada tarifa cae en
  /// exactamente una.
  bool matches(int? rate) {
    if (rate == null) return true;
    return switch (this) {
      PriceFilter.any => true,
      PriceFilter.low => rate < kPrecioBandaBajaHasta,
      PriceFilter.mid =>
        rate >= kPrecioBandaBajaHasta && rate <= kPrecioBandaMediaHasta,
      PriceFilter.high => rate > kPrecioBandaMediaHasta,
    };
  }
}

/// `40000` → `$40.000` (es-AR, punto de miles).
String _pesos(int n) {
  final digitos = n.toString();
  final out = StringBuffer();
  for (var i = 0; i < digitos.length; i++) {
    if (i > 0 && (digitos.length - i) % 3 == 0) out.write('.');
    out.write(digitos[i]);
  }
  return '\$$out';
}

/// `40000` → `40`. Los techos son múltiplos de mil.
int _miles(int n) => n ~/ 1000;
