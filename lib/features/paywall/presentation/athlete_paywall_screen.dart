import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/tokens/primitives.dart';
import '../../../l10n/app_l10n.dart';
import '../../auth/presentation/widgets/terms_notice_text.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../application/athlete_checkout.dart';

/// El paywall del ALUMNO: donde elige plan y compra por IAP.
///
/// ═══════════════════════════════════════════════════════════════════════════
///  POR QUÉ ACÁ NO HAY NINGÚN PRECIO ESCRITO A MANO
/// ═══════════════════════════════════════════════════════════════════════════
///
/// Todos los números que se ven salen de [AthletePlanOferta.precio], que es el
/// `priceString` que devuelve la tienda. Ninguno se arma acá, ni se convierte,
/// ni se formatea.
///
/// No es prolijidad. Apple lo pide con estas palabras:
///
///   «In the purchase flow, the amount that will be billed must be the most
///   prominent pricing element in the layout. [...] these additional elements
///   should be displayed in a subordinate position and size».
///
/// Y armar el número por nuestra cuenta abre la puerta a que la pantalla diga
/// algo distinto de lo que cobra la hoja de pago del sistema, que es el peor
/// lugar posible para una discrepancia.
///
/// ═══════════════════════════════════════════════════════════════════════════
///  POR QUÉ EL AVISO DE IMPUESTOS NO LLEVA NINGÚN MONTO
/// ═══════════════════════════════════════════════════════════════════════════
///
/// El alumno argentino ve «USD 2,99» y en el resumen le llega bastante más:
/// el emisor de su tarjeta le suma IVA (RG 4240) y una percepción (RG 5617).
/// Avisarle es lo correcto —y además la obligación de informar el precio final
/// es del vendedor, que frente al consumidor argentino somos nosotros y no
/// Apple—.
///
/// Pero el MONTO no se puede publicar, por tres razones que se acumulan:
///
///   1. **No lo sabemos.** La conversión la hace el emisor de la tarjeta, con
///      su tipo de cambio, el día que cierra el resumen. No es un dato que la
///      app pueda leer ni predecir.
///   2. **El porcentaje tampoco es fijo.** La RG 4240 art. 4 acota la
///      percepción de IVA a pagos de hasta USD 10 para una parte de los
///      prestadores, y en el listado de ARCA la línea de APPLE tiene
///      justamente ese tope mientras la de GOOGLE PLAY no. O sea que el mismo
///      «+51%» sería falso en el plan anual de iOS.
///   3. **Publicar un número que puede salir mal tiene nombre**: guideline
///      2.3.1(a), *"promoting a false price"*, cuya pena escrita es la baja de
///      la app y la terminación de la cuenta de developer.
///
/// Y del lado de Google hay una cláusula que Apple no tiene, literal:
/// *«In-app pricing must match the pricing displayed in the user-facing Play
/// billing interface»*. Un total en pesos presentado como precio no matchea.
///
/// Por eso: el precio de la tienda como único número, y debajo —subordinado—
/// una advertencia cualitativa. Es el mismo patrón que usa Spotify Argentina,
/// el único precedente de primera parte que se pudo verificar textual.
///
/// Si algún día se quiere mostrar el estimado en pesos, va detrás de un tap y
/// DESPUÉS de que esta versión pase review, no antes.
class AthletePaywallScreen extends ConsumerStatefulWidget {
  const AthletePaywallScreen({super.key, this.checkout});

  /// Sólo para los tests. En producción lo resuelve [resolveAthleteCheckout].
  final AthleteCheckout? checkout;

  @override
  ConsumerState<AthletePaywallScreen> createState() =>
      _AthletePaywallScreenState();
}

class _AthletePaywallScreenState extends ConsumerState<AthletePaywallScreen> {
  late final AthleteCheckout _checkout =
      widget.checkout ?? resolveAthleteCheckout();

  List<AthletePlanOferta>? _planes;
  AthletePlan? _elegido;
  bool _cargando = true;
  bool _comprando = false;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final checkout = _checkout;
    final planes = checkout is AthleteCheckoutOnStore
        ? await checkout.planes()
        : const <AthletePlanOferta>[];
    if (!mounted) return;
    setState(() {
      _planes = planes;
      // El anual arranca elegido cuando existe. No es un truco de venta: es el
      // que le conviene al alumno (2 meses gratis) y el que reduce a un evento
      // de cobro por año en un mercado donde los rechazos de tarjeta son la
      // primera causa de churn involuntario.
      _elegido = planes.isEmpty
          ? null
          : planes.map((p) => p.plan).firstWhere(
                (p) => p == AthletePlan.anual,
                orElse: () => planes.first.plan,
              );
      _cargando = false;
    });
  }

  Future<void> _comprar() async {
    final checkout = _checkout;
    final plan = _elegido;
    final uid = ref.read(currentUidProvider);
    if (checkout is! AthleteCheckoutOnStore || plan == null) return;
    if (uid == null || uid.isEmpty) return;

    setState(() => _comprando = true);
    final r = await checkout.start(uid: uid, plan: plan);
    if (!mounted) return;
    setState(() => _comprando = false);

    final l10n = AppL10n.of(context);
    final mensaje = switch (r) {
      AthletePurchaseOutcome.comprado => l10n.paywallAlumnoListo,
      AthletePurchaseOutcome.pendiente => l10n.paywallAlumnoPendiente,
      // El alumno cerró la hoja de pago. Tomó una decisión: no se le dice nada.
      AthletePurchaseOutcome.cancelado => null,
      AthletePurchaseOutcome.sinProducto => l10n.paywallAlumnoSinPlanes,
      AthletePurchaseOutcome.error => l10n.paywallAlumnoErrorCompra,
    };
    if (mensaje != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensaje)));
    }

    // Se cierra sólo si la tienda cobró. Ojo con lo que eso significa: el
    // derecho lo escribe `rcWebhook` del lado servidor, así que la pantalla
    // anterior lo va a ver cuando el provider recomponga, no ahora.
    if (r == AthletePurchaseOutcome.comprado &&
        Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final planes = _planes;

    return Scaffold(
      backgroundColor: palette.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(),
      ),
      body: SafeArea(
        top: false,
        child: _cargando
            ? const Center(child: CircularProgressIndicator())
            : (planes == null || planes.isEmpty)
                ? _SinPlanes(onReintentar: _cargar)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.s20,
                      AppSpacing.s8,
                      AppSpacing.s20,
                      AppSpacing.s20,
                    ),
                    children: [
                      Text(
                        l10n.paywallAlumnoTitulo,
                        style: TextStyle(
                          fontSize: AppTextSize.heading,
                          fontWeight: FontWeight.w700,
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s8),
                      Text(
                        l10n.paywallAlumnoBajada,
                        style: TextStyle(
                          fontSize: AppTextSize.body,
                          color: palette.textMuted,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s20),
                      for (final oferta in planes) ...[
                        _TarjetaDePlan(
                          oferta: oferta,
                          elegido: oferta.plan == _elegido,
                          onTap: () => setState(() => _elegido = oferta.plan),
                        ),
                        const SizedBox(height: AppSpacing.s12),
                      ],
                      const SizedBox(height: AppSpacing.s8),
                      for (final b in [
                        l10n.paywallAlumnoBeneficio1,
                        l10n.paywallAlumnoBeneficio2,
                        l10n.paywallAlumnoBeneficio3,
                        l10n.paywallAlumnoBeneficio4,
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.s8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.check,
                                  size: AppTextSize.bodyLarge,
                                  color: palette.accent),
                              const SizedBox(width: AppSpacing.s8),
                              Expanded(
                                child: Text(
                                  b,
                                  style: TextStyle(
                                    fontSize: AppTextSize.body,
                                    color: palette.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: AppSpacing.s18),

                      // El aviso de impuestos. SUBORDINADO al precio: más chico,
                      // menos contraste, y sin ningún monto. Ver el encabezado.
                      Text(
                        l10n.paywallAlumnoImpuestos,
                        key: const Key('paywall_alumno_impuestos'),
                        style: TextStyle(
                          fontSize: AppTextSize.caption,
                          color: palette.textMuted,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s18),

                      ElevatedButton(
                        key: const Key('paywall_alumno_cta'),
                        onPressed: _comprando ? null : _comprar,
                        child: _comprando
                            ? const SizedBox(
                                height: AppTextSize.bodyLarge,
                                width: AppTextSize.bodyLarge,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(l10n.paywallAlumnoCta),
                      ),
                      const SizedBox(height: AppSpacing.s8),

                      // Apple lo exige para suscripciones: sin esto es rechazo.
                      TextButton(
                        key: const Key('paywall_alumno_restaurar'),
                        onPressed: _comprando ? null : _restaurar,
                        child: Text(l10n.paywallAlumnoRestaurar),
                      ),
                      const SizedBox(height: AppSpacing.s12),

                      // Términos y Privacidad, in-app. La guideline 3.1.2 los
                      // exige en el flujo de compra, y este widget ya los abre
                      // sin salir de la app — que además es lo que evita que
                      // el guard de `launchUrl` se ponga rojo.
                      const TermsNoticeText(),
                    ],
                  ),
      ),
    );
  }

  Future<void> _restaurar() async {
    final checkout = _checkout;
    final uid = ref.read(currentUidProvider);
    if (checkout is! AthleteCheckoutOnStore) return;
    if (uid == null || uid.isEmpty) return;

    setState(() => _comprando = true);
    final tiene = await checkout.restaurar(uid: uid);
    if (!mounted) return;
    setState(() => _comprando = false);

    final l10n = AppL10n.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tiene ? l10n.paywallAlumnoListo : l10n.paywallAlumnoSinRestaurar,
        ),
      ),
    );
    if (tiene && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    }
  }
}

/// La tarjeta de un plan. El precio de la tienda es el elemento dominante.
class _TarjetaDePlan extends StatelessWidget {
  const _TarjetaDePlan({
    required this.oferta,
    required this.elegido,
    required this.onTap,
  });

  final AthletePlanOferta oferta;
  final bool elegido;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final esAnual = oferta.plan == AthletePlan.anual;

    return InkWell(
      key: Key('paywall_alumno_plan_${oferta.plan.name}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.s12),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.s12),
          border: Border.all(
            color: elegido ? palette.accent : palette.border,
            width: elegido ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    esAnual
                        ? l10n.paywallAlumnoPlanAnual
                        : l10n.paywallAlumnoPlanMensual,
                    style: TextStyle(
                      fontSize: AppTextSize.bodyLarge,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                  if (esAnual)
                    Text(
                      l10n.paywallAlumnoAhorro,
                      style: TextStyle(
                        fontSize: AppTextSize.caption,
                        color: palette.accent,
                      ),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // EL número dominante. Sale de la tienda, siempre.
                Text(
                  oferta.precio,
                  style: TextStyle(
                    fontSize: AppTextSize.title,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                ),
                // El equivalente mensual del anual, subordinado en tamaño y en
                // contraste — que es exactamente como Apple pide que se
                // muestren estos desgloses.
                if (oferta.precioPorMes != null)
                  Text(
                    oferta.precioPorMes!,
                    style: TextStyle(
                      fontSize: AppTextSize.caption,
                      color: palette.textMuted,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SinPlanes extends StatelessWidget {
  const _SinPlanes({required this.onReintentar});

  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.paywallAlumnoSinPlanes,
              key: const Key('paywall_alumno_sin_planes'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppTextSize.body,
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            TextButton(
              onPressed: onReintentar,
              child: Text(l10n.paywallAlumnoReintentar),
            ),
          ],
        ),
      ),
    );
  }
}
