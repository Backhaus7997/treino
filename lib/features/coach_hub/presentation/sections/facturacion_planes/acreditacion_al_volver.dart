import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/widgets/motion/treino_tappable.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/application/cf_providers.dart';

/// Lo que sabemos del pago del PF cuando aterriza en la pantalla de planes.
///
/// Espeja el contrato del callable `reconcileMyCheckout` — y espeja ese y no el
/// `ReconcileOutcome` del reconciliador a propósito. La condición de éxito son
/// DOS cosas juntas (el outcome Y el estado que devolvió Mercado Pago): un
/// `written` con status `pending` es justo el caso de alguien a quien no se le
/// acreditó nada, y un cliente que tratara `written` como «listo» le diría que
/// ya tiene el plan a quien no lo tiene. La traducción vive en el servidor, que
/// es el único lugar donde están las dos mitades.
enum EstadoAcreditacion {
  /// Mercado Pago confirmó y el plan ya está escrito.
  acreditado,

  /// Hay un alta en curso que MP todavía no autorizó. Volver a preguntar sirve.
  pendiente,

  /// No hay ningún plan que reconciliar. Es el caso normal de quien entró a
  /// mirar precios.
  sinCheckout,

  /// No pudimos preguntarle a MP. Reintentar sirve.
  noDisponible,
}

EstadoAcreditacion _parsear(Object? crudo) => switch (crudo) {
      'acreditado' => EstadoAcreditacion.acreditado,
      'pendiente' => EstadoAcreditacion.pendiente,
      'sin-checkout' => EstadoAcreditacion.sinCheckout,
      // Cualquier cosa que no reconozcamos cae en «no pudimos preguntar», que
      // es lo único honesto: no sabemos si pagó. Nunca en `acreditado`, que
      // sería afirmar sobre plata algo que el servidor no dijo.
      _ => EstadoAcreditacion.noDisponible,
    };

/// Le pregunta al servidor si el pago ya está acreditado.
///
/// No recibe NADA. El callable no tiene body: la entrada es el uid del token,
/// y los planes salen de consultar `mp_plans` filtrado por ese uid. Que la
/// firma no tenga parámetros no es una simplificación — es la superficie de
/// seguridad, y por eso se refleja acá.
typedef AcreditacionChecker = Future<EstadoAcreditacion> Function();

/// Cartel que aparece SOLO cuando hay algo que decir.
///
/// ─── Por qué se dispara al aterrizar y no con un parámetro de la URL ───
///
/// El camino obvio sería que el `back_url` de Mercado Pago trajera un
/// `from=mp` y disparar con eso. Se descartó: el mismo PF llega acá desde el
/// CTA de un mail de facturación, desde «CAMBIAR PLAN», y volviendo a mirar
/// al rato porque no vio el cambio — y en todos esos casos preguntar es tan
/// útil como al volver del pago. Atarlo a un parámetro habría cubierto un
/// camino y dejado los otros tres con el dato viejo.
///
/// Preguntar siempre es barato porque el costo real —la llamada a Mercado
/// Pago— ya está acotado en el servidor: un PF sin planes no genera ninguna, y
/// el cooldown corta las repetidas antes de salir a la red.
///
/// ─── Por qué NO hay cartel de éxito ───
///
/// Porque `acreditado` no significa «se acreditó recién»: un PF que ya tenía
/// plan y entra a mirar precios también resuelve `acreditado` (el
/// reconciliador devuelve `unchanged` con status `active`). Un «¡Listo, ya
/// tenés tu plan!» en esa visita sería una felicitación por algo que no acaba
/// de pasar.
///
/// La confirmación real la da la grilla, sin que este widget haga nada:
/// `pricing_screen` marca el plan vigente con `isCurrent` leyendo
/// `userProfileProvider`, que es un stream sobre `snapshots()`. Cuando la
/// Cloud Function escriba `subscription`, la tarjeta se ilumina sola.
///
/// Este cartel existe para el caso en que la grilla se quedaría muda: el pago
/// que MP todavía no confirmó.
///
/// ─── Por qué un fallo de la consulta AUTOMÁTICA no dice nada ───
///
/// Porque nadie la pidió. El PF entró a mirar planes; que no hayamos podido
/// hablar con Mercado Pago es un problema NUESTRO, no suyo, y no puede hacer
/// nada al respecto — el barrido nocturno lo cubre igual. Un «no pudimos
/// consultar a Mercado Pago» sin que haya preguntado nada es alarmar por algo
/// que se arregla solo.
///
/// El fallo SÍ se muestra cuando el PF tocó «consultar de nuevo»: ahí sí
/// preguntó, y no contestarle sería peor.
///
/// Tiene un efecto de borde que conviene entender antes de tocarlo: en
/// cualquier test o golden sin Firebase la llamada real falla, cae en
/// `noDisponible`, y el cartel queda invisible. O sea que este widget NO mueve
/// ninguna captura del visual gate — no por suerte, sino porque el silencio
/// ante un fallo no pedido es la conducta correcta y además la conveniente.
class AcreditacionAlVolverBanner extends ConsumerStatefulWidget {
  const AcreditacionAlVolverBanner({super.key, this.checker});

  /// Seam de test. La frontera se pone en «¿en qué estado está el pago?» y no
  /// en `HttpsCallable`, por el mismo motivo que documenta `plan_checkout.dart`
  /// para su propio seam: doblar `HttpsCallableResult` para probar un cartel es
  /// más frágil que el cartel.
  final AcreditacionChecker? checker;

  @override
  ConsumerState<AcreditacionAlVolverBanner> createState() =>
      _AcreditacionAlVolverBannerState();
}

class _AcreditacionAlVolverBannerState
    extends ConsumerState<AcreditacionAlVolverBanner> {
  EstadoAcreditacion? _estado;
  bool _consultando = true;

  /// Latch de instancia. `initState` corre una vez por montaje, pero el
  /// `setState` de la respuesta reconstruye, y sin esto cualquier refactor que
  /// mueva la llamada a `build` —o un `didChangeDependencies` -- dispararía en
  /// cada rebuild. Es el mismo latch que usa `CoachHubTourGate` y por el mismo
  /// motivo.
  bool _pidiendo = false;

  /// Si el PF pidió la consulta con el botón. Decide si un fallo se cuenta o
  /// se calla — ver el docstring de la clase.
  bool _loPidioElPf = false;

  @override
  void initState() {
    super.initState();
    // Post-frame: `initState` no puede leer providers con seguridad, y además
    // deja que la pantalla pinte antes de salir a la red.
    WidgetsBinding.instance.addPostFrameCallback((_) => _consultar());
  }

  Future<void> _consultarAPedido() => _consultar(aPedido: true);

  Future<void> _consultar({bool aPedido = false}) async {
    if (_pidiendo) return;
    _pidiendo = true;
    if (aPedido) _loPidioElPf = true;
    if (mounted) setState(() => _consultando = true);

    final checker = widget.checker ?? _checkerReal;
    EstadoAcreditacion resultado;
    try {
      resultado = await checker();
    } catch (_) {
      // Cualquier fallo —red, Firebase sin inicializar, un payload raro— es lo
      // mismo para el PF: no pudimos preguntar. Nunca se degrada a
      // `acreditado`.
      resultado = EstadoAcreditacion.noDisponible;
    }

    _pidiendo = false;
    if (!mounted) return;
    setState(() {
      _estado = resultado;
      _consultando = false;
    });
  }

  Future<EstadoAcreditacion> _checkerReal() async {
    final fn =
        ref.read(cloudFunctionsProvider).httpsCallable('reconcileMyCheckout');
    final res = await fn.call<Object?>();
    final data = res.data;
    return _parsear(data is Map ? data['estado'] : null);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    // Mientras se consulta por primera vez no se muestra NADA. El caso
    // abrumadoramente más común es `sinCheckout`, y un cartel de «consultando»
    // que aparece y desaparece en todas las visitas es peor que el silencio.
    if (_consultando && _estado == null) return const SizedBox.shrink();

    final estado = _estado;
    final pendiente = estado == EstadoAcreditacion.pendiente;
    // `acreditado` y `sinCheckout` no dicen nada: el primero lo cuenta la
    // grilla sola, el segundo no es noticia. Y un fallo que nadie pidió
    // tampoco — ver el docstring de la clase.
    final mostrar = pendiente ||
        (estado == EstadoAcreditacion.noDisponible && _loPidioElPf);
    if (!mostrar) return const SizedBox.shrink();

    return Container(
      key: const Key('acreditacion_al_volver_banner'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.s20),
      padding: const EdgeInsets.all(AppSpacing.s20),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.accent),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            pendiente ? TreinoIcon.clock : TreinoIcon.warning,
            size: 20,
            color: palette.accent,
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pendiente
                      ? 'ESTAMOS CONFIRMANDO TU PAGO' // i18n: Fase W3
                      : 'NO PUDIMOS CONSULTAR A MERCADO PAGO', // i18n: Fase W3
                  style: GoogleFonts.barlowCondensed(
                    color: palette.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.s8),
                Text(
                  pendiente
                      // Se promete lo que el barrido garantiza, no una hora:
                      // no tenemos medida de cuánto tarda MP en autorizar.
                      ? 'Mercado Pago todavía no nos confirmó la suscripción. '
                          'Se acredita sola apenas la confirme; si querés, '
                          'consultá de nuevo.' // i18n: Fase W3
                      : 'Si ya pagaste, no perdiste nada: lo acreditamos '
                          'igual apenas podamos consultarlo.', // i18n: Fase W3
                  style: TextStyle(color: palette.textMuted, fontSize: 13),
                ),
                const SizedBox(height: AppSpacing.s12),
                TreinoTappable(
                  onTap: _consultando ? null : _consultarAPedido,
                  child: Text(
                    _consultando
                        ? 'CONSULTANDO…' // i18n: Fase W3
                        : 'CONSULTAR DE NUEVO', // i18n: Fase W3
                    style: GoogleFonts.barlowCondensed(
                      color: palette.accent,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
