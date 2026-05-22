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

/// Filtro de rango de precio mensual del PF (`trainerMonthlyRate`).
///
/// Trainers sin `trainerMonthlyRate` set son siempre incluidos (no se
/// filtran out) — el filtro solo excluye trainers cuyo rate cae fuera del
/// rango especificado.
enum PriceFilter {
  any,
  under5k,
  k5to10k,
  over10k;

  /// Label para mostrar en el chip / bottom sheet.
  String get label => switch (this) {
        PriceFilter.any => 'Cualquier precio',
        PriceFilter.under5k => 'Menos de \$5.000',
        PriceFilter.k5to10k => '\$5.000 - \$10.000',
        PriceFilter.over10k => 'Más de \$10.000',
      };

  /// Label corto para el chip.
  String get chipLabel => switch (this) {
        PriceFilter.any => 'Precio',
        PriceFilter.under5k => '< \$5k',
        PriceFilter.k5to10k => '\$5-10k',
        PriceFilter.over10k => '> \$10k',
      };

  /// Verifica si un rate dado cae dentro del rango.
  /// Si rate es null, retorna true (no se filtra).
  bool matches(int? rate) {
    if (rate == null) return true;
    return switch (this) {
      PriceFilter.any => true,
      PriceFilter.under5k => rate < 5000,
      PriceFilter.k5to10k => rate >= 5000 && rate <= 10000,
      PriceFilter.over10k => rate > 10000,
    };
  }
}
