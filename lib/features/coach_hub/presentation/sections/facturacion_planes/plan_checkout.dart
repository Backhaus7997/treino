import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../../../coach/domain/subscription_tier.dart';

/// Dónde puede el entrenador CONTRATAR su suscripción a TREINO.
///
/// TREINO le cobra la suscripción al ENTRENADOR, no al alumno. Las App Store
/// Review Guidelines 3.1.3(c) exigen que toda venta «consumer, single user or
/// family» que ocurra DENTRO de la app pase por in-app purchase, y un
/// entrenador comprando su propia licencia es exactamente single user; Google
/// Play pide lo equivalente con Play Billing. Eso es 15-30% de comisión contra
/// el ~2% de una pasarela: sobre un Plan 2 de $22.000 son $3.300-$6.600 por
/// mes POR ENTRENADOR.
///
/// Por eso el alta vive SOLO en el Coach Hub web — que además es donde el
/// entrenador ya arma rutinas, gestiona alumnos y mira su facturación. La app
/// móvil informa (planes, precios, cupo propio) pero no vende.
///
/// ─── Por qué un tipo sellado y no un `if (kIsWeb)` ───
///
/// Hoy el CTA de la pricing page todavía no cobra: abre un aviso. El día que
/// alguien cablee la pasarela va a buscar ese punto y va a reemplazar el aviso
/// por la llamada real. Con un `if` alrededor del botón ese reemplazo habilita
/// la compra en móvil sin que nada se queje: el `if` sigue ahí, verdadero en
/// las dos ramas, porque lo único que cambió es lo que hay adentro.
///
/// Acá la compra no es un booleano: es una CAPACIDAD que sólo tiene
/// [PlanCheckoutAvailable]. [PlanCheckoutOnWebOnly] no expone `start` — no es
/// la compra apagada, es un tipo que no sabe comprar. Y los constructores son
/// privados a ESTA librería, así que desde `lib/` la única forma de conseguir
/// un [PlanCheckoutAvailable] es [resolvePlanCheckout]. Copiar el botón de
/// compra a la rama móvil no compila.
///
/// Lo que el tipo NO ataja —y conviene tenerlo presente antes de confiarse—:
/// escribir un camino de cobro AL LADO del cartel, adentro de la rama móvil
/// (un `launchUrl` a la pasarela, un `showDialog` con el checkout). Eso no
/// toca `start` ni rompe el sellado, y ya pasó: una auditoría colgó un
/// `showDialog` de checkout del cartel del pie y la suite entera siguió verde.
///
/// Contra eso hay TRES tests, y hacen falta los tres:
///   - ningún texto que hable de dónde se contrata puede quedar tappable
///     (cubre los dos carteles, no sólo el del CTA — ése fue el agujero);
///   - disparar todos los taps de la pantalla no puede navegar, abrir un
///     SnackBar ni abrir una ruta modal;
///   - en la carpeta del paywall no puede aparecer un `url_launcher`.
sealed class PlanCheckout {
  const PlanCheckout._();
}

/// Superficie que SÍ puede cobrar: el Coach Hub web.
final class PlanCheckoutAvailable extends PlanCheckout {
  const PlanCheckoutAvailable._() : super._();

  /// Arranca el alta o el cambio de plan. ÚNICO camino a un cobro en toda la
  /// app: no hay otro método en esta jerarquía que inicie nada.
  ///
  /// Recibe [tier] y [annual] aunque el aviso de hoy no los use. Son los datos
  /// que un checkout real necesita, y tenerlos ya en la firma hace que cablear
  /// la pasarela sea cambiar ESTE cuerpo y nada más — ningún call-site tiene
  /// que enterarse.
  void start(
    BuildContext context, {
    required SubscriptionTier tier,
    required bool annual,
  }) {
    // MOCK: la pasarela todavía no está cableada. Cuando lo esté, el checkout
    // se abre desde acá. En web «muy pronto» es cierto — lo que falta es la
    // cuenta de cobro, no una decisión de plataforma.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'El pago con Mercado Pago se habilita muy pronto.', // i18n: Fase W3
        ),
      ),
    );
  }
}

/// Superficie que NO cobra: la app móvil. El alta se hace en TREINO web.
///
/// No tiene `start`, ni un `enabled`, ni un callback nullable: no hay nada que
/// encender. Si algún día TREINO vendiera dentro de la app —vía in-app
/// purchase de verdad, no una pasarela— eso sería OTRA capacidad y otro tipo,
/// no un campo más acá.
final class PlanCheckoutOnWebOnly extends PlanCheckout {
  const PlanCheckoutOnWebOnly._() : super._();
}

/// Fuerza la superficie de compra. SÓLO para tests.
///
/// `kIsWeb` es una constante de COMPILACIÓN: bajo `flutter test` (que corre en
/// la VM de Dart, no en un browser) vale `false` SIEMPRE y no hay forma de
/// moverlo. Sin este seam ningún widget test podría RENDERIZAR la pantalla del
/// Coach Hub. Mismo patrón que `debugPlanLimitPaywallForm`.
///
/// OJO — este override NO cubre la decisión: el `??` corta antes de llegar a
/// `kIsWeb`, así que un test que lo fija está probando la UI, no la regla. La
/// regla la pinea [planCheckoutFor]. Por eso los tests fijan
/// `planCheckoutFor(isWeb: true)` y no una constante escrita a mano: si la
/// rama web se rompe, se caen también los tests que dibujan el botón.
///
/// Nadie en `lib/` lo lee ni lo escribe: el default `null` deja mandar a la
/// plataforma. Los tests lo fijan y lo devuelven a `null` con `addTearDown`.
@visibleForTesting
PlanCheckout? debugPlanCheckout;

/// La regla, sin la plataforma: qué superficie puede cobrar dado [isWeb].
///
/// Está separada de [resolvePlanCheckout] porque el `??` del override cortaba
/// ANTES de llegar a `kIsWeb`, y eso dejaba la rama web literalmente sin
/// ejecutar: se podía cambiar el `true` por «nadie puede comprar en ninguna
/// superficie» —o sea, dejar a TREINO sin poder vender— y la suite entera
/// quedaba verde. Medido: 6522 tests, cero rojos. Acá las DOS ramas son
/// llamables desde un test, así que la superficie no testeable se reduce al
/// token `kIsWeb`.
///
/// `@visibleForTesting`: llamarla desde `lib/` con `isWeb` a mano sería
/// fabricar la capacidad de cobrar salteándose la plataforma. El analyzer lo
/// marca, y eso rompe el gate de 0 issues.
@visibleForTesting
PlanCheckout planCheckoutFor({required bool isWeb}) =>
    isWeb ? const PlanCheckoutAvailable._() : const PlanCheckoutOnWebOnly._();

/// ÚNICO lugar de la app que decide si una superficie puede cobrar.
///
/// Si esto llegara a devolver [PlanCheckoutAvailable] en móvil, TREINO estaría
/// vendiendo dentro de la app: 3.1.3(c) en iOS y Play Billing en Android. No
/// es un detalle de UI, es la diferencia entre ~2% y 15-30% de cada
/// suscripción. El test «la app móvil no ofrece comprar» de
/// `pricing_screen_test.dart` pinea esta función.
PlanCheckout resolvePlanCheckout() =>
    debugPlanCheckout ?? planCheckoutFor(isWeb: kIsWeb);
