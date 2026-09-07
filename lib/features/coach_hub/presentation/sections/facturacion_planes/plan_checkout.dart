import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
///   - en la carpeta del paywall no puede aparecer una forma de abrir algo
///     afuera, con UNA excepción: el `launchUrl` de ESTE archivo, que es el
///     que abre el checkout. `WebViewController`, `InAppBrowser` y
///     `LaunchMode.inAppBrowserView` siguen prohibidos en toda la carpeta,
///     acá incluido — un checkout en un WebView es una venta ADENTRO de la
///     app para 3.1.3(c), que es justo lo que esto evita.
sealed class PlanCheckout {
  const PlanCheckout._();
}

/// Superficie que SÍ puede cobrar: el Coach Hub web.
final class PlanCheckoutAvailable extends PlanCheckout {
  const PlanCheckoutAvailable._() : super._();

  /// Arranca el alta o el cambio de plan. ÚNICO camino a un cobro en toda la
  /// app: no hay otro método en esta jerarquía que inicie nada.
  ///
  /// Llama a `createPreapproval`, que abre la suscripción en Mercado Pago y
  /// devuelve el `initPoint`, y navega ahí.
  ///
  /// La firma ya recibía [tier] y [annual] desde antes de que existiera la
  /// pasarela, apostando a que cablearla iba a ser cambiar este cuerpo y nada
  /// más. Se cumplió a medias: el único call-site no tuvo que cambiar sus
  /// argumentos, pero `start` pasó de sincrónico a `Future`. Un método que
  /// habla por red no puede no serlo, y eso no se puede esconder detrás de una
  /// firma.
  ///
  /// ─── Por qué esto SACA al usuario de la app, y no puede no hacerlo ───
  ///
  /// El checkout se abre con una navegación de PÁGINA COMPLETA en la misma
  /// pestaña (`webOnlyWindowName: '_self'`). No es una preferencia estética:
  ///
  ///   1. Un WebView o un browser in-app sigue siendo, para la App Store
  ///      Review Guideline 3.1.3(c), una venta ADENTRO de la app. Abrirlo así
  ///      reintroduciría exactamente el problema que este archivo existe para
  ///      evitar, y encima de una forma que el tipo sellado no ve.
  ///   2. El `back_url` que le mandamos a Mercado Pago trae al PF de vuelta a
  ///      `/ajustes`. Con una pestaña nueva volvería a una pestaña huérfana y
  ///      la original quedaría mostrando el plan viejo.
  ///
  /// Por eso el guard de la carpeta sigue prohibiendo `WebViewController`,
  /// `InAppBrowser` y `LaunchMode.inAppBrowserView` — también en ESTE archivo.
  /// Lo único que se habilitó es el `launchUrl` de acá.
  ///
  /// ─── El mail del pagador ───
  ///
  /// [payerEmail] es el mail de la cuenta de Mercado Pago del PF, si configuró
  /// uno distinto al de TREINO (`users/{uid}.mpPayerEmail`). `null` —el caso
  /// normal— deja que el servidor use el del token.
  ///
  /// Viene por parámetro y NO se pregunta en el momento: una versión anterior
  /// abría un diálogo acá y era el diseño equivocado. MP exige el dato, pero
  /// eso es un detalle de la pasarela, y filtrarlo a la cara del usuario le
  /// cobra fricción al 90% que tiene los dos mails iguales. El que necesita
  /// otro lo configura una vez en Ajustes → Facturación.
  Future<void> start(
    BuildContext context, {
    required SubscriptionTier tier,
    required bool annual,
    String? payerEmail,
  }) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      final initPoint = await (debugPlanCheckoutCreator ?? _crearPreapproval)(
        tier: tier,
        annual: annual,
        payerEmail: payerEmail,
      );
      if (initPoint == null) {
        _avisar(messenger, 'No pudimos abrir el pago. Probá de nuevo.');
        return;
      }

      final abrio = await (debugPlanCheckoutLauncher ?? _abrirCheckout)(
        Uri.parse(initPoint),
      );
      if (!abrio) {
        _avisar(messenger, 'No pudimos abrir Mercado Pago. Probá de nuevo.');
      }
    } on FirebaseFunctionsException catch (e) {
      // `unavailable` es el único donde reintentar sirve — el servidor lo
      // reserva para fallos de MP que se arreglan solos. Prometer «probá de
      // nuevo» en un 401 nuestro sería mandar al PF a golpear una puerta que
      // no se va a abrir.
      _avisar(
        messenger,
        e.code == 'unavailable'
            ? 'Mercado Pago no responde en este momento. Probá en unos minutos.'
            : 'No pudimos iniciar el pago. Escribinos y lo resolvemos.',
      );
    } catch (_) {
      _avisar(messenger, 'No pudimos iniciar el pago. Probá de nuevo.');
    }
  }

  void _avisar(ScaffoldMessengerState messenger, String texto) {
    messenger.showSnackBar(
      SnackBar(content: Text(texto)), // i18n: Fase W3
    );
  }
}

const String _kRegion = 'southamerica-east1';

/// Abre la suscripción en Mercado Pago y devuelve la URL del checkout, o `null`
/// si el servidor no la mandó.
///
/// Manda SÓLO el plan y el ciclo. El monto lo pone el servidor desde
/// `TIER_PRICES_ARS`: mandarlo desde acá sería dejar que el cliente elija
/// cuánto paga, y no hay validación que arregle eso.
Future<String?> _crearPreapproval({
  required SubscriptionTier tier,
  required bool annual,
  String? payerEmail,
}) async {
  final res = await FirebaseFunctions.instanceFor(region: _kRegion)
      .httpsCallable('createPreapproval')
      .call<Map<String, dynamic>>({
    'tier': tier.name,
    'cycle': annual ? 'annual' : 'monthly',
    // Sólo viaja si el PF configuró uno. Mandar `null` haría que el
    // servidor lo viera como un payerEmail inválido y cayera al default —
    // mismo resultado, pero por accidente en vez de por diseño.
    if (payerEmail != null && payerEmail.isNotEmpty) 'payerEmail': payerEmail,
  });
  final initPoint = res.data['initPoint'];
  return initPoint is String && initPoint.isNotEmpty ? initPoint : null;
}

/// Navega a la URL del checkout SACANDO al usuario de la app.
///
/// `_self` y no una pestaña nueva: ver el dartdoc de [PlanCheckoutAvailable.start].
Future<bool> _abrirCheckout(Uri url) =>
    launchUrl(url, webOnlyWindowName: '_self');

/// Inyecta la creación del preapproval. SÓLO para tests.
///
/// El seam va ACÁ y no sobre `FirebaseFunctions` a propósito: un doble del
/// cliente de Cloud Functions obliga a fingir `HttpsCallable` y
/// `HttpsCallableResult` para probar UI. Lo que a la pantalla le importa es
/// «conseguí una URL de checkout, o no», y esa es la frontera que conviene
/// mover — la de la red, no la del SDK.
@visibleForTesting
Future<String?> Function({
  required SubscriptionTier tier,
  required bool annual,
  String? payerEmail,
})? debugPlanCheckoutCreator;


/// Inyecta el navegador. SÓLO para tests: sin esto, probar el punto de compra
/// abriría Mercado Pago de verdad desde la suite.
@visibleForTesting
Future<bool> Function(Uri)? debugPlanCheckoutLauncher;

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
