import 'package:treino/core/utils/app_clock.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach/domain/trainer_subscription.dart';

/// Cuánto periodo pagado tiene que quedar para que el servidor DIFIERA el
/// primer cobro de un checkout nuevo: un día.
///
/// Espeja `MIN_DIFERIMIENTO_MS` de
/// `functions/src/subscriptions/mp/diferir-primer-cobro.ts` (24 h, `DIA_MS`).
/// Si el servidor cambia ese número, cambia acá también: el aviso de la
/// pricing page se esconde con este borde.
const Duration _kMinDiferimiento = Duration(days: 1);

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
/// Tampoco espeja el PISO PREPAGO del servidor (`prepaidTier`/`prepaidUntil`,
/// `conPisoPrepago` en `functions/src/subscriptions/effective-limit.ts`): el
/// tier que el PF ya pagó y que sigue valiendo aunque su suscripción actual sea
/// otra. `TrainerSubscription` no tiene esos campos, así que acá no hay de
/// dónde leerlo. Un piso sólo SUBE el límite, nunca lo baja, y por eso un PF
/// con un piso vigente puede tener en el servidor un límite MAYOR que el que
/// sale de este helper.
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
///
/// ## El primer cobro
///
/// La pricing page le avisa al PF qué pasa con su primer cobro si vuelve a
/// suscribirse, y eso lo decide el servidor con una regla que tiene un borde
/// visible desde acá: un día. [primerCobroDiferible] lo expone, con el mismo
/// "ahora" que [pagadoHasta] para que las dos cosas no se contradigan.
///
/// ## Una foto, no un reloj
///
/// La vigencia se calcula una vez y no se entera sola de que pasó un borde: en
/// ese instante no tiene por qué emitir nadie, porque el servidor no reescribe
/// el tier al vencer y [AppClock] no avisa. [proximoCambio] dice cuándo deja
/// de valer, y `vigenciaDelPlanProvider` (`vigencia_del_plan_provider.dart`,
/// al lado) la recalcula ahí. Lo leen el chip del sidebar, que está montado
/// toda la sesión, el banner de upsell, el medidor de cupo del tab Coach
/// móvil y la pantalla de alumnos en solo lectura. La pricing page
/// (`pricing_screen.dart`) y Facturación (`facturacion_tab.dart`) todavía la
/// calculan en su build: abiertas al cruzar el borde, muestran la foto vieja
/// hasta el próximo rebuild. No son las únicas que miran el reloj: otras
/// pantallas comparan `currentPeriodEnd` contra su propio `now` sin pasar por
/// esta clase.
///
/// Los `.dart` de `lib/` nombrados entre backticks en esta sección son
/// EXACTAMENTE los que llaman a [VigenciaDelPlan.de], y lo verifica
/// `vigencia_en_el_build_scan_test.dart`: quien sume una pantalla que la
/// calcule en su build la tiene que nombrar acá, y quien la pase al provider,
/// sacarla.
final class VigenciaDelPlan {
  const VigenciaDelPlan._({
    required this.tierEfectivo,
    required this.cancelada,
    required this.pagadoHasta,
    required this.primerCobroDiferible,
    required this.proximoCambio,
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
        primerCobroDiferible: false,
        // Sin baja no hay borde: nada de esto depende de la hora.
        proximoCambio: null,
      );
    }

    final fin = suscripcion.currentPeriodEnd;
    final ahora = now ?? AppClock.now();
    final corre = fin != null && ahora.isBefore(fin);
    return VigenciaDelPlan._(
      // Un período que ya no corre es Free, igual que en el servidor.
      tierEfectivo: corre ? tier : SubscriptionTier.free,
      cancelada: true,
      pagadoHasta: corre ? fin : null,
      // `>=` y no `>`: el servidor descarta con `finMs - nowMs <
      // MIN_DIFERIMIENTO_MS`, o sea que con EXACTAMENTE un día todavía
      // difiere.
      primerCobroDiferible:
          fin != null && fin.difference(ahora) >= _kMinDiferimiento,
      proximoCambio: fin == null ? null : _proximoCambio(fin, ahora),
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

  /// La baja está pedida y el período pagado ya no corre (o nunca tuvo fecha):
  /// lo que rige es Free, aunque el doc siga diciendo otro tier. Es [cancelada]
  /// sin [pagadoHasta].
  ///
  /// El servidor nunca reescribe el tier del doc cuando esto pasa (el límite
  /// cae «sin que se escriba un solo documento», `entitlement-triggers.ts`),
  /// así que el tier del doc sigue siendo el del plan viejo, y también un
  /// `weightLimit` que el doc trajera. Quien muestre el tope tiene que tomarlo
  /// del [tierEfectivo].
  bool get vencida => cancelada && pagadoHasta == null;

  /// El servidor PUEDE diferir el primer cobro de un checkout nuevo de este
  /// plan hasta [pagadoHasta]: la baja está pedida y falta al menos un día
  /// para esa fecha. Es lo único de la decisión que el cliente alcanza a ver.
  ///
  /// Es una condición NECESARIA y no suficiente. Que MP muestre un cobro real
  /// que respalde esos días lo decide el servidor, y desde acá no se ve: `true`
  /// no promete que el cobro se difiera, y por eso el texto que lo usa es un
  /// «si». `false` en cambio es definitivo: con menos de un día el servidor
  /// cobra en el acto, pase lo que pase con MP.
  ///
  /// Espeja `decidirDiferimiento` (`queda-menos-de-un-dia`) en
  /// `functions/src/subscriptions/mp/diferir-primer-cobro.ts`.
  ///
  /// Se calcula al construir, como todo en esta clase (ver «Una foto, no un
  /// reloj»). La pricing page, que es quien lo usa, lo calcula en su build, y
  /// abierta al cruzar el borde lo conserva hasta el próximo rebuild.
  final bool primerCobroDiferible;

  /// Cuándo deja de valer esta foto sin que cambie el doc: el próximo borde
  /// de la baja, a lo sumo un milisegundo después de cruzarlo. Primero deja de
  /// poder diferirse (un día antes de [pagadoHasta]) y después deja de correr
  /// (en [pagadoHasta]). `null` si no queda ninguno por delante: sin baja, o
  /// con la baja vencida o sin fecha.
  ///
  /// Es lo que espera `vigenciaDelPlanProvider` para recalcularla sola.
  final DateTime? proximoCambio;
}

/// El próximo borde de una baja que vence en [fin], visto desde [ahora]: un
/// instante en que [VigenciaDelPlan.de] ya devuelve otra cosa. `null` si no
/// queda ninguno.
DateTime? _proximoCambio(DateTime fin, DateTime ahora) {
  // 1. Deja de poder diferirse. Este borde es inclusivo (con EXACTAMENTE un día
  //    todavía difiere), así que el cambio llega después de él. Un milisegundo
  //    y no un microsegundo: el `Timer` de web cuenta en milisegundos
  //    (`inMilliseconds`), y un microsegundo de espera sería un `setTimeout`
  //    de 0 que podría disparar antes de que el borde pase.
  final umbral = fin.subtract(_kMinDiferimiento);
  if (!ahora.isAfter(umbral)) {
    return umbral.add(const Duration(milliseconds: 1));
  }
  // 2. Deja de correr. Este borde es estricto (`isBefore`): en `fin` ya venció.
  if (ahora.isBefore(fin)) return fin;
  return null;
}
