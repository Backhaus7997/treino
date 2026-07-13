import 'trainer_link.dart';
import 'trainer_link_entitlement.dart';
import 'trainer_link_status.dart';

/// Peso ponderado de un vínculo hacia el límite del tier (paywall Fase 7).
///
/// Espejo client-side de `functions/src/subscriptions/weighted-load.ts` — el
/// servidor es la autoridad (el gate transaccional de PR4 corre allá), pero la
/// UI necesita mostrar "N/límite" con la MISMA lógica sin un round-trip.
///
/// - active     → 1.0
/// - paused     → 0.5  (cuesta la mitad; cierra el abuso pause-to-dodge)
/// - pending    → 0.0  (una solicitud aún no sigue)
/// - terminated → 0.0
double _statusWeight(TrainerLinkStatus status) => switch (status) {
      TrainerLinkStatus.active => 1.0,
      TrainerLinkStatus.paused => 0.5,
      TrainerLinkStatus.pending => 0.0,
      TrainerLinkStatus.terminated => 0.0,
    };

/// Redondea a la mitad más cercana para evitar drift de float al sumar muchas
/// mitades. Los pesos son mitades exactas → nunca cambia un valor legítimo.
double roundToHalf(double n) => (n * 2).round() / 2;

/// Carga ponderada de los vínculos de un PF. Excluye los `blocked` (excedente
/// estacionado — nunca cuenta, ADR-5) y deduplica por `athleteId` quedándose
/// con el estado de mayor peso (un par puede tener un terminated histórico + un
/// active vivo → cuenta el vivo).
double computeWeightedLoad(Iterable<TrainerLink> links) {
  final bestByAthlete = <String, TrainerLink>{};
  for (final link in links) {
    if (link.entitlement == TrainerLinkEntitlement.blocked) continue;
    final cur = bestByAthlete[link.athleteId];
    if (cur == null || _statusWeight(link.status) > _statusWeight(cur.status)) {
      bestByAthlete[link.athleteId] = link;
    }
  }
  var sum = 0.0;
  for (final link in bestByAthlete.values) {
    sum += _statusWeight(link.status);
  }
  return roundToHalf(sum);
}
