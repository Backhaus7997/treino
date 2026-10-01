import 'package:treino/core/utils/app_clock.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach/domain/trainer_subscription.dart';

/// Qué plan rige HOY para el PF y qué le quedó de una baja.
///
/// «El tier que dice el doc» y «el plan que el PF tiene» dejan de ser lo mismo
/// en un solo caso, y las pantallas de Facturación los leían como si lo
/// fueran: la suscripción `cancelled`. El servidor le respeta el tier pago
/// HASTA `currentPeriodEnd` y recién después lo baja a Free (`limiteDelStatus`
/// en `functions/src/subscriptions/effective-limit.ts`: rige mientras
/// `nowMs < currentPeriodEndMs`, estricto, y sin fecha no rige nunca).
///
/// Una pantalla que marcaba el tier del doc como «TU PLAN ACTUAL» sin mirar
/// eso hacía dos cosas mal a la vez. Con la fecha ya vencida, le mostraba un
/// plan que ya no tiene. Y con días todavía pagos, lo dejaba sin botón para
/// volver a contratarlo: el plan actual no se vende.
///
/// ## Qué espeja y qué NO
///
/// Esto espeja SÓLO la rama `cancelled`. `pending` y `paused` también caen a
/// Free en el servidor, pero las pantallas de plan siguen mostrando el tier
/// del doc para ellos y este helper no lo cambia a propósito: no es «el límite
/// efectivo» de la cuenta, es lo que decide qué tarjeta lleva la etiqueta de
/// plan actual y si hay algo que re-contratar.
///
/// ## El reloj
///
/// "Ahora" sale de [AppClock] —el seam que un test puede congelar— y no de un
/// reloj crudo: `no_raw_clock_scan_test.dart` lo prohíbe en `coach_hub/`, y con
/// motivo, porque una pantalla que lee la hora real no se puede fotografiar dos
/// veces igual. La comparación es entre INSTANTES (`isBefore` compara
/// `microsecondsSinceEpoch`, sin importar el flag UTC), así que no hace falta
/// pasar nada a calendario argentino; eso sólo se necesita para MOSTRAR la
/// fecha, y ya lo resuelve `fechaDiaMesArg`.
final class VigenciaDelPlan {
  const VigenciaDelPlan._({
    required this.tierEfectivo,
    required this.cancelada,
    required this.pagadoHasta,
  });

  /// Calcula la vigencia de [suscripcion] (`null` = PF sin suscripción, Free
  /// por definición, sin backfill).
  ///
  /// [now] se inyecta para tests puntuales; sin él se lee [AppClock.now]. El
  /// reloj sólo se consulta cuando hay una baja: para cualquier otro estado la
  /// respuesta no depende de la hora.
  factory VigenciaDelPlan.de(TrainerSubscription? suscripcion,
      {DateTime? now}) {
    final tier = suscripcion?.tier ?? SubscriptionTier.free;

    if (suscripcion == null ||
        suscripcion.status != SubscriptionStatus.cancelled) {
      return VigenciaDelPlan._(
        tierEfectivo: tier,
        cancelada: false,
        pagadoHasta: null,
      );
    }

    final fin = suscripcion.currentPeriodEnd;
    final corre = fin != null && (now ?? AppClock.now()).isBefore(fin);
    return VigenciaDelPlan._(
      // Un período que ya no corre es Free, igual que en el servidor.
      tierEfectivo: corre ? tier : SubscriptionTier.free,
      cancelada: true,
      pagadoHasta: corre ? fin : null,
    );
  }

  /// El tier que cuenta como «el actual»: el del doc, salvo una baja cuyo
  /// período pagado ya venció (o nunca tuvo fecha), que es Free.
  final SubscriptionTier tierEfectivo;

  /// El PF pidió la baja (`status == cancelled`), corra o no todavía su
  /// período. Alcanza para saber que no queda nada más que dar de baja.
  final bool cancelada;

  /// Hasta cuándo le dura lo que ya pagó: `currentPeriodEnd`, y SÓLO si la baja
  /// está pedida y esa fecha todavía no llegó. `null` en cualquier otro caso —
  /// incluida una baja sin fecha, que el servidor trata como ya vencida—.
  ///
  /// Que sea no-nulo es exactamente «cancelada con días pagos»: el único
  /// estado en que el PF puede volver a contratar el MISMO plan.
  final DateTime? pagadoHasta;
}
