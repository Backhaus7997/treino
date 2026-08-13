import '../../../../payments/domain/athlete_billing.dart';

/// Un grupo de alumnos que comparten la misma tarifa comercial
/// (monto + cadencia). Deriva de [AthleteBilling] — ver [agruparTarifas].
class TarifaGroup {
  const TarifaGroup({
    required this.amountArs,
    required this.cadence,
    required this.alumnosCount,
  });

  final int amountArs;
  final BillingCadence cadence;
  final int alumnosCount;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TarifaGroup &&
          runtimeType == other.runtimeType &&
          amountArs == other.amountArs &&
          cadence == other.cadence &&
          alumnosCount == other.alumnosCount;

  @override
  int get hashCode => Object.hash(amountArs, cadence, alumnosCount);

  @override
  String toString() => 'TarifaGroup(amountArs: $amountArs, '
      'cadence: $cadence, alumnosCount: $alumnosCount)';
}

/// Resumen agregado de las tarifas comerciales configuradas por el PF sobre
/// sus alumnos, derivado de todos sus [AthleteBilling] vía [agruparTarifas].
class TarifasResumen {
  const TarifasResumen({
    required this.grupos,
    required this.precioPromedio,
    required this.alumnosConTarifa,
    required this.tarifasDistintas,
    required this.masUsada,
  });

  /// Grupos por (amountArs, cadence), ordenados por [TarifaGroup.alumnosCount]
  /// descendente (desempate por [TarifaGroup.amountArs] descendente).
  final List<TarifaGroup> grupos;

  /// Media entera de `amountArs` sobre TODOS los billings (división entera,
  /// trunca hacia abajo). Mezcla cadencias distintas (mensual/semanal/
  /// porSesion/suelto) — es una métrica aproximada de "ticket medio", no
  /// comparable entre cadencias. La UI debe aclarar este caveat en su
  /// sublabel.
  final int precioPromedio;

  /// Cantidad total de alumnos con una tarifa configurada (== cantidad de
  /// billings, no de grupos).
  final int alumnosConTarifa;

  /// Cantidad de grupos distintos (== `grupos.length`).
  final int tarifasDistintas;

  /// El grupo con más alumnos (la moda), o `null` si no hay billings.
  final TarifaGroup? masUsada;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TarifasResumen &&
          runtimeType == other.runtimeType &&
          _gruposEquals(grupos, other.grupos) &&
          precioPromedio == other.precioPromedio &&
          alumnosConTarifa == other.alumnosConTarifa &&
          tarifasDistintas == other.tarifasDistintas &&
          masUsada == other.masUsada;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(grupos),
        precioPromedio,
        alumnosConTarifa,
        tarifasDistintas,
        masUsada,
      );
}

/// Pluraliza una palabra es-AR según [count]: singular solo cuando
/// `count == 1`, plural en cualquier otro caso (incluido 0). Helper puro
/// reusado por `TarifaCard` y `PlanesScreen` para evitar "1 alumnos"/
/// "1 tarifas" (WARNING de verify Fase 10).
String pluralizarEs(int count, String singular, String plural) =>
    count == 1 ? singular : plural;

bool _gruposEquals(List<TarifaGroup> a, List<TarifaGroup> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Agrupa [billings] por (amountArs, cadence) y arma el resumen de tarifas
/// comerciales del PF. Función pura — sin dependencias de Firestore/Riverpod
/// (ver [tarifasResumenProvider] en `tarifas_provider.dart`).
TarifasResumen agruparTarifas(List<AthleteBilling> billings) {
  if (billings.isEmpty) {
    return const TarifasResumen(
      grupos: [],
      precioPromedio: 0,
      alumnosConTarifa: 0,
      tarifasDistintas: 0,
      masUsada: null,
    );
  }

  final counts = <({int amountArs, BillingCadence cadence}), int>{};
  for (final billing in billings) {
    final key = (amountArs: billing.amountArs, cadence: billing.cadence);
    counts[key] = (counts[key] ?? 0) + 1;
  }

  final grupos = [
    for (final entry in counts.entries)
      TarifaGroup(
        amountArs: entry.key.amountArs,
        cadence: entry.key.cadence,
        alumnosCount: entry.value,
      ),
  ]..sort((a, b) {
      final byCount = b.alumnosCount.compareTo(a.alumnosCount);
      if (byCount != 0) return byCount;
      return b.amountArs.compareTo(a.amountArs);
    });

  final totalAmount = billings.fold<int>(0, (sum, b) => sum + b.amountArs);
  final precioPromedio = totalAmount ~/ billings.length;

  return TarifasResumen(
    grupos: grupos,
    precioPromedio: precioPromedio,
    alumnosConTarifa: billings.length,
    tarifasDistintas: grupos.length,
    masUsada: grupos.first,
  );
}
