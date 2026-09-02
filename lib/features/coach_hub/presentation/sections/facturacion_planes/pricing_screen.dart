import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../../core/widgets/motion/treino_tappable.dart';
import '../../../../../core/widgets/treino_icon.dart';
import '../../../../coach/domain/subscription_tier.dart';
import '../../../../profile/application/user_providers.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'plan_checkout.dart';

/// Umbral entre el layout ancho (Coach Hub web) y el apilado del teléfono.
///
/// Se mide sobre el ancho TOTAL de la pantalla. Antes vivía adentro de
/// [_PlanCards] y medía el ancho ya padeado (~48px menos), pero ahora el
/// header, el toggle y el pie también cambian de tamaño según el ancho, así
/// que la decisión tiene que tomarse UNA sola vez y arriba de todo — dos
/// LayoutBuilder con el mismo número es una forma cara de que algún día no
/// coincidan. El corte cae lejos de cualquier viewport de teléfono y de
/// cualquier ventana útil del Coach Hub, así que los ~48px de corrimiento no
/// mueven a nadie de layout.
const double _kNarrowBreakpoint = 820;

/// Lo que la app móvil dice EN LUGAR del botón de compra, y la línea que lo
/// explica al pie. Los dos strings viven acá, juntos, por una razón que no es
/// de estilo.
///
/// ─── DECISIÓN DE PRODUCTO PENDIENTE, no un detalle de copy ───
///
/// El guard de [resolvePlanCheckout] cierra 3.1.3(c): no se vende adentro de la
/// app. Pero la guideline de al lado, 3.1.1, prohíbe además «buttons, external
/// links, or other calls to action that direct customers to purchasing
/// mechanisms other than in-app purchase». Un texto que le dice al PF dónde
/// comprar afuera es una call to action aunque no sea un link — y acá aparece
/// junto a los cuatro precios en ARS.
///
/// Las dos salidas cuestan plata y ninguna es obviamente mejor:
///   - decirlo (hoy): riesgo de rechazo en review por 3.1.1. Recuperable: es
///     este archivo, dos constantes.
///   - callarlo (Netflix, Spotify): sin riesgo de 3.1.1, pero el PF que entró
///     por el APK queda en un callejón sin salida y ese es el 100% del funnel
///     de $12.000-$39.000 por mes.
///
/// No la decide un refactor. Lo único que corresponde antes de mandar a review
/// es que la decisión sea barata: son estas dos constantes y nada más. Si la
/// respuesta es «callarlo», [_WhereToSubscribeNote] y la rama
/// [PlanCheckoutOnWebOnly] del CTA se quedan sin texto y listo.
///
/// Lo que NO se puede hacer en ninguno de los dos casos es convertirlo en un
/// link, un botón o un deep link: eso es 3.1.1 sin discusión posible.
const String _kSubscribeElsewhereShort =
    'SE CONTRATA EN TREINO WEB'; // i18n: Fase W3

/// Ver [_kSubscribeElsewhereShort] — misma decisión pendiente.
const String _kSubscribeElsewhereLong =
    'El alta y el cambio de plan se hacen desde TREINO web, '
    'con esta misma cuenta.'; // i18n: Fase W3

/// El pie legal de la pantalla, en las dos superficies.
///
/// Decía «Renovación automática. Podés cancelar cuando quieras desde
/// Facturación» y era FALSO en las DOS: la app móvil no tiene ninguna pantalla
/// de Facturación (`router.dart` no registra `/ajustes`, y por eso
/// `plan_limit_paywall` cae al aviso) y el tab web es de sólo lectura — no hay
/// un control de baja en todo el repo. Prometer cancelación fácil es
/// exactamente el tipo de claim que un revisor de tienda va a ir a buscar.
///
/// TODO(producto): volver a prometer la baja cuando exista el control que la
/// haga verdad. Mientras tanto, sólo se afirma lo que la pantalla cumple.
const String _kRenewalNote =
    'La suscripción se renueva automáticamente según el ciclo '
    'que elijas.'; // i18n: Fase W3

/// Host de `/facturacion/planes` en la app MÓVIL.
///
/// [PricingScreen] es SOLO contenido: en el Coach Hub web el chrome (Scaffold,
/// SafeArea, sidebar para navegar) lo pone el shell (ADR-CHW-005). En móvil no
/// hay shell, y la ruta montaba un `Scaffold(body: PricingScreen())` pelado —
/// o sea, en un teléfono con notch el título se dibujaba DEBAJO de la barra de
/// estado y no había forma de volver salvo el gesto del sistema.
///
/// Por qué AppBar transparente y no una flecha propia arriba a la izquierda:
/// el header del diseño va CENTRADO, y meter la flecha en la misma fila lo
/// descentra. El AppBar además ya reserva el inset del notch, por eso el body
/// va con `SafeArea(top: false)` — solo queda cuidar el borde inferior (barra
/// de gestos). Es el mismo patrón de `notification_history_screen`: AppBar
/// transparente + [TreinoIcon.back], sin inventar nada nuevo.
///
/// Vive acá y no en el router porque es chrome de ESTA pantalla (el AppBar de
/// 56px es parte de cómo se llega a los 64 de padTop del diseño). El router
/// queda como tabla de rutas.
class PricingRouteScreen extends StatelessWidget {
  const PricingRouteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          // Al paywall se llega con `push` desde "VER PLANES", así que casi
          // siempre hay a dónde volver. El fallback cubre el deep-link directo
          // a la URL, donde `pop` no tiene destino y dejaría al PF encerrado.
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/coach'),
          icon: Icon(TreinoIcon.back, color: palette.textPrimary),
          tooltip: 'Volver', // i18n: Fase W3
        ),
      ),
      body: const SafeArea(top: false, child: PricingScreen()),
    );
  }
}

/// Pricing page del paywall PF→TREINO (Fase 7, PR3 UI + PR4 móvil).
///
/// Estilo inspirado en pricing pages SaaS (ref Rela/Fibrit) adaptado a la
/// identidad Mint Magenta: precio-héroe gigante, card recomendada ELEVADA con
/// cinta "MÁS POPULAR", toggle Mensual/Anual centrado con "Ahorrá 2 meses".
///
/// Dos layouts, no uno responsive a medias: ancho (Coach Hub web, grilla 2x2)
/// y angosto (teléfono, tarjetas apiladas con el precio y el rango de alumnos
/// en dos columnas). Ver [_WideBody] y [_NarrowBody].
///
/// Solo contenido — el Scaffold lo pone `coachHubPage` en web y
/// [PricingRouteScreen] en móvil.
///
/// Se abre desde "CAMBIAR PLAN" en Facturación y desde el CTA "VER PLANES" del
/// modal de límite. Precios de [kTierPricesArs].
///
/// El punto de compra NO está en todas las superficies: lo decide
/// [resolvePlanCheckout] y sólo el Coach Hub web lo tiene. En la app móvil esta
/// pantalla informa —planes, precios, cupo propio— y en lugar del CTA muestra
/// dónde se contrata. Ver [plan_checkout.dart] para el porqué (3.1.3(c) /
/// Play Billing) y para por qué es un tipo sellado y no un `if`.
class PricingScreen extends ConsumerStatefulWidget {
  const PricingScreen({super.key});

  @override
  ConsumerState<PricingScreen> createState() => _PricingScreenState();
}

class _PricingScreenState extends ConsumerState<PricingScreen> {
  bool _annual = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final currentTier =
        ref.watch(userProfileProvider).valueOrNull?.subscription?.tier ??
            SubscriptionTier.free;

    // La superficie de compra se resuelve UNA vez, acá arriba, y baja por
    // parámetro hasta el CTA. No se vuelve a preguntar adentro de las tarjetas:
    // dos llamadas son dos lugares donde algún día una puede quedar vieja.
    //
    // Va FUERA del LayoutBuilder a propósito. La superficie NO es el ancho: una
    // tablet Android en 900pt entra por [_WideBody] y sigue sin poder vender,
    // igual que el teléfono. Si esto viviera adentro del builder invitaría a
    // mezclar las dos decisiones, que es exactamente el bug caro.
    final checkout = resolvePlanCheckout();

    return LayoutBuilder(
      builder: (context, constraints) {
        void onCycleChanged(bool v) => setState(() => _annual = v);

        if (constraints.maxWidth < _kNarrowBreakpoint) {
          return _NarrowBody(
            annual: _annual,
            currentTier: currentTier,
            palette: palette,
            checkout: checkout,
            onCycleChanged: onCycleChanged,
          );
        }
        return _WideBody(
          annual: _annual,
          currentTier: currentTier,
          palette: palette,
          checkout: checkout,
          onCycleChanged: onCycleChanged,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Layout ancho — Coach Hub web
// ---------------------------------------------------------------------------

class _WideBody extends StatelessWidget {
  const _WideBody({
    required this.annual,
    required this.currentTier,
    required this.palette,
    required this.checkout,
    required this.onCycleChanged,
  });

  final bool annual;
  final SubscriptionTier currentTier;
  final AppPalette palette;

  /// Ancho NO implica web: una tablet Android de 900pt llega hasta acá. Por eso
  /// el layout no decide nada de la compra, sólo transporta lo que ya decidió
  /// [resolvePlanCheckout].
  final PlanCheckout checkout;

  final ValueChanged<bool> onCycleChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
      child: Column(
        children: [
          Text(
            'PLANES Y PRECIOS', // i18n: Fase W3
            style: GoogleFonts.barlowCondensed(
              color: palette.textPrimary,
              fontSize: 40,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Pagás según cuántos alumnos activos tengas. '
            'Cambiá de plan cuando quieras.', // i18n: Fase W3
            style: TextStyle(color: palette.textMuted, fontSize: 15),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          _CycleToggle(
            annual: annual,
            palette: palette,
            onChanged: onCycleChanged,
          ),
          const SizedBox(height: 40),
          _PlanCards(
            annual: annual,
            currentTier: currentTier,
            palette: palette,
            checkout: checkout,
            narrow: false,
          ),
          const SizedBox(height: 24),
          _WhereToSubscribeNote(
            checkout: checkout,
            palette: palette,
            fontSize: 12,
          ),
          Text(
            _kRenewalNote,
            style: TextStyle(color: palette.textMuted, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Toggle Mensual / Anual centrado, con "Ahorrá 2 meses" arriba y el
/// seleccionado subrayado en mint (patrón de la referencia web).
class _CycleToggle extends StatelessWidget {
  const _CycleToggle({
    required this.annual,
    required this.palette,
    required this.onChanged,
  });

  final bool annual;
  final AppPalette palette;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '¡Ahorrá 2 meses con el anual!', // i18n: Fase W3
          style: GoogleFonts.barlowCondensed(
            color: palette.accent,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CycleOption(
              label: 'Mensual', // i18n: Fase W3
              selected: !annual,
              palette: palette,
              onTap: () => onChanged(false),
            ),
            const SizedBox(width: 32),
            _CycleOption(
              label: 'Anual', // i18n: Fase W3
              selected: annual,
              palette: palette,
              onTap: () => onChanged(true),
            ),
          ],
        ),
      ],
    );
  }
}

class _CycleOption extends StatelessWidget {
  const _CycleOption({
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TreinoTappable(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.barlowCondensed(
              color: selected ? palette.textPrimary : palette.textMuted,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          // Subrayado mint bajo el seleccionado.
          Container(
            height: 2,
            width: 28,
            color: selected ? palette.accent : Colors.transparent,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Layout angosto — teléfono (artboard D: stack vertical)
// ---------------------------------------------------------------------------

/// Artboard D, medido sobre un viewport de 390x844.
///
/// Los números fuera de la escala del proyecto (8·12·14·18·20) vienen del
/// artboard y se dejan crudos igual que en el resto del paywall: 38 y 46 son
/// alturas de control táctil, 9.5/10.5/11.5/13.5 son tamaños tipográficos del
/// diseño y 3/4/10 son paddings de píldoras que en la escala quedarían el
/// doble de gordos de lo que el diseño pide.
class _NarrowBody extends StatelessWidget {
  const _NarrowBody({
    required this.annual,
    required this.currentTier,
    required this.palette,
    required this.checkout,
    required this.onCycleChanged,
  });

  final bool annual;
  final SubscriptionTier currentTier;
  final AppPalette palette;
  final PlanCheckout checkout;
  final ValueChanged<bool> onCycleChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      // 20 lateral (escala). Arriba van 8 y no los 64 del artboard porque el
      // AppBar de [PricingRouteScreen] ya se comió 56: 56 + 8 = 64.
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: Column(
        children: [
          Text(
            // Dos líneas a propósito (artboard D). En una sola, "PLANES Y
            // PRECIOS" en Barlow Condensed 30 cruza la pantalla como una tira
            // fina y deja de leerse como título.
            'PLANES Y\nPRECIOS', // i18n: Fase W3
            style: GoogleFonts.barlowCondensed(
              color: palette.textPrimary,
              fontSize: 30,
              fontWeight: FontWeight.w800,
              height: 1.05,
              letterSpacing: 1.0,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Pagás según cuántos alumnos activos tengas. '
            'Cambiá de plan cuando quieras.', // i18n: Fase W3
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 13.5,
              height: 1.35,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          _SavingsChip(palette: palette),
          const SizedBox(height: 12),
          _NarrowCycleToggle(
            annual: annual,
            palette: palette,
            onChanged: onCycleChanged,
          ),
          const SizedBox(height: 20),
          _PlanCards(
            annual: annual,
            currentTier: currentTier,
            palette: palette,
            checkout: checkout,
            narrow: true,
          ),
          const SizedBox(height: 20),
          _WhereToSubscribeNote(
            checkout: checkout,
            palette: palette,
            fontSize: 11.5,
          ),
          Text(
            _kRenewalNote,
            style: TextStyle(color: palette.textMuted, fontSize: 11.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Píldora "¡Ahorrá 2 meses con el anual!" sobre el toggle.
///
/// En móvil el ahorro es un chip y no un texto suelto como en web: al lado de
/// un toggle segmentado, un texto pelado se lee como parte del control.
class _SavingsChip extends StatelessWidget {
  const _SavingsChip({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.08),
        border: Border.all(color: palette.accent.withValues(alpha: 0.33)),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        '¡Ahorrá 2 meses con el anual!', // i18n: Fase W3
        style: TextStyle(
          color: palette.accent,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// Toggle segmentado MENSUAL / ANUAL a todo el ancho (artboard D).
class _NarrowCycleToggle extends StatelessWidget {
  const _NarrowCycleToggle({
    required this.annual,
    required this.palette,
    required this.onChanged,
  });

  final bool annual;
  final AppPalette palette;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Row(
        children: [
          Expanded(
            child: _NarrowCycleOption(
              label: 'MENSUAL', // i18n: Fase W3
              selected: !annual,
              palette: palette,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _NarrowCycleOption(
              label: 'ANUAL', // i18n: Fase W3
              selected: annual,
              palette: palette,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _NarrowCycleOption extends StatelessWidget {
  const _NarrowCycleOption({
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TreinoTappable(
      onTap: onTap,
      child: Container(
        // minHeight y no height: con textScale grande el label crece y una
        // altura fija lo recortaría.
        constraints: const BoxConstraints(minHeight: 38),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          // El activo invierte: fondo claro (textPrimary) y texto oscuro (bg).
          color: selected ? palette.textPrimary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(
          label,
          style: GoogleFonts.barlowCondensed(
            color: selected ? palette.bg : palette.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2, // 0.1em
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tarjetas — una por tier, en los dos layouts
// ---------------------------------------------------------------------------

/// Las tarjetas de plan: grilla 2x2 en ancho, stack vertical en angosto.
class _PlanCards extends StatelessWidget {
  const _PlanCards({
    required this.annual,
    required this.currentTier,
    required this.palette,
    required this.checkout,
    required this.narrow,
  });

  final bool annual;
  final SubscriptionTier currentTier;
  final AppPalette palette;
  final PlanCheckout checkout;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    const recommended = SubscriptionTier.plan1;

    // Se ITERA sobre el enum a proposito, y para los DOS layouts. Antes las
    // tarjetas estaban escritas a mano (free, plan1, plan2), asi que agregar un
    // tier al enum NO lo hacia aparecer aca: el compilador exige exhaustividad
    // en los switch, pero no dice nada de una lista literal. Plan 3 se agrego y
    // la pricing page siguio mostrando tres planes, en silencio.
    final cards = <SubscriptionTier, Widget>{
      for (final tier in SubscriptionTier.values)
        tier: narrow
            ? _NarrowPlanCard(
                tier: tier,
                annual: annual,
                isCurrent: currentTier == tier,
                recommended: tier == recommended,
                palette: palette,
                checkout: checkout,
              )
            : _PlanCard(
                tier: tier,
                annual: annual,
                isCurrent: currentTier == tier,
                recommended: tier == recommended,
                palette: palette,
                checkout: checkout,
              ),
    };

    const tiers = SubscriptionTier.values;

    if (narrow) {
      // Apilado en ORDEN DE PRECIO (el del enum: free → plan1 → plan2 → plan3).
      //
      // El diseño de referencia ponía la recomendada primero para ganar el
      // fold. Se descartó: en una lista scrolleable eso rompe la escalera y
      // obliga al PF a reconstruirla mentalmente para comparar — que es
      // exactamente lo que viene a hacer a esta pantalla. La recomendada ya se
      // distingue por el borde, el glow y la etiqueta «MÁS POPULAR»; no
      // necesita además saltearse la fila.
      return Column(
        children: [
          for (var i = 0; i < tiers.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            cards[tiers[i]]!,
          ],
        ],
      );
    }

    // Grilla 2x2 para todo lo ancho. NO hay variante de cuatro en fila: el
    // ancho por tarjeta lo fija el precio-heroe (Barlow Condensed grande) y
    // pide ~360px, o sea que cuatro necesitarian ~1500px utiles. Achicar el
    // precio para que entren seria sacrificar justo lo que la tarjeta tiene
    // para decir.
    Widget fila(List<SubscriptionTier> par) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < par.length; i++) ...[
                if (i > 0) const SizedBox(width: 16),
                Expanded(child: cards[par[i]]!),
              ],
            ],
          ),
        );
    return Column(
      children: [
        fila(tiers.take(2).toList()),
        const SizedBox(height: 16),
        fila(tiers.skip(2).toList()),
      ],
    );
  }
}

String _tierName(SubscriptionTier tier) => switch (tier) {
      SubscriptionTier.free => 'FREE', // i18n: Fase W3
      SubscriptionTier.plan1 => 'PLAN 1', // i18n: Fase W3
      SubscriptionTier.plan2 => 'PLAN 2', // i18n: Fase W3
      SubscriptionTier.plan3 => 'PLAN 3', // i18n: Fase W3
    };

/// (numeroAlumnos, labelAlumnos) para el bloque de features.
(String, String) _tierStudents(SubscriptionTier tier) => switch (tier) {
      SubscriptionTier.free => ('2', 'alumnos'), // i18n: Fase W3
      SubscriptionTier.plan1 => ('3-7', 'alumnos'), // i18n: Fase W3
      SubscriptionTier.plan2 => ('8-15', 'alumnos'), // i18n: Fase W3
      // "+15" y no "∞": sigue la serie de las otras tarjetas (2 · 3-7 ·
      // 8-15) y se lee de una. El simbolo quedaba chico y ajeno en Barlow
      // Condensed, y obligaba a interpretar en vez de leer. Ojo que el limite
      // de plan3 en `kTierWeightLimits` es `null` — la etiqueta se decide acá,
      // nunca interpolando el limite.
      SubscriptionTier.plan3 => ('+15', 'alumnos'), // i18n: Fase W3
    };

/// Formatea un monto ARS con separador de miles (12.000).
String _formatArs(int amount) {
  final s = amount.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Oferta anual de un tier, DERIVADA de `kTierPricesArs` — nunca hardcodeada.
///
/// `listPrice` es lo que costarían 12 meses pagando el precio mensual; el
/// anual sale más barato porque son 10 (`annual = monthly × 10`, los "2 meses
/// gratis"). El porcentaje se calcula, así que el día que cambien los precios
/// el cartel acompaña solo en vez de mentir.
///
/// Devuelve `null` cuando NO hay oferta que mostrar: Free (no tiene precio) y
/// el caso defensivo de un anual que dejara de ser más barato que el mensual.
({int listPrice, int percent})? _annualOffer(SubscriptionTier tier) {
  final price = kTierPricesArs[tier];
  if (price == null) return null;
  final list = price.monthly * 12;
  if (price.annual >= list) return null;
  final pct = ((list - price.annual) / list * 100).round();
  if (pct <= 0) return null;
  return (listPrice: list, percent: pct);
}

/// Precio de lista tachado + chip con el % de descuento, arriba del
/// precio-héroe cuando el ciclo es anual.
///
/// El toggle ya avisa "¡Ahorrá 2 meses con el anual!", pero eso vive a 40px de
/// distancia de los números y el PF tiene que hacer la cuenta él: ve $120.000
/// y no tiene contra qué compararlo. Acá la comparación está donde se toma la
/// decisión.
///
/// [reserveSpace] existe por la grilla 2x2 del layout ancho: FREE no tiene
/// oferta, y si su tarjeta no reservara esta fila su precio-héroe quedaría
/// más arriba que el de PLAN 1, que está al lado. La reserva se hace con los
/// textos VACÍOS y no escondiendo los de otro plan: el alto de un `Text` lo
/// fija la tipografía y no el contenido, así que la fila mide igual, y no
/// queda un "-17%" fantasma en el árbol para confundir a un `find.text` o a
/// un lector de pantalla. Que el alto realmente coincida lo prueba el test de
/// alineación FREE/PLAN 1, no este comentario.
///
/// En el layout angosto las tarjetas van apiladas, no hay nada con qué
/// alinear, y la fila se omite entera.
class _AnnualOfferRow extends StatelessWidget {
  const _AnnualOfferRow({
    required this.tier,
    required this.palette,
    required this.reserveSpace,
    required this.compact,
  });

  final SubscriptionTier tier;
  final AppPalette palette;
  final bool reserveSpace;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final offer = _annualOffer(tier);
    if (offer == null && !reserveSpace) return const SizedBox.shrink();

    final listText = offer == null ? '' : '\$${_formatArs(offer.listPrice)}';
    final pctText = offer == null ? '' : '-${offer.percent}%';

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          listText,
          style: GoogleFonts.barlowCondensed(
            color: palette.textMuted,
            fontSize: compact ? 14 : 20,
            fontWeight: FontWeight.w600,
            height: 1.0,
            decoration: TextDecoration.lineThrough,
            decorationColor: palette.textMuted,
            decorationThickness: 2,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        SizedBox(width: compact ? 6 : 8),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 6 : 8,
            vertical: compact ? 2 : 3,
          ),
          decoration: BoxDecoration(
            // Sin oferta la píldora sigue ocupando su alto pero no pinta: un
            // óvalo mint vacío en la tarjeta de FREE sería peor que el hueco.
            color: offer == null ? Colors.transparent : palette.accent,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Text(
            pctText,
            style: GoogleFonts.barlowCondensed(
              // Ink invariante: `palette.bg` sobre accent da 1.57:1 en el tema
              // claro (AGENTS.md §2). Nunca `palette.bg` acá.
              color: TreinoButtonTokens.foreground(context),
              fontSize: compact ? 10 : 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              height: 1.0,
            ),
          ),
        ),
      ],
    );

    // Mismo criterio que el precio-héroe: con textScale alto se achica en vez
    // de desbordar la tarjeta.
    return _PriceFit(
      alignment: compact ? Alignment.centerLeft : Alignment.center,
      child: row,
    );
  }
}

/// Envoltorio obligatorio del precio-héroe.
///
/// El Row del precio es `mainAxisSize.min` y sus hijos no son `Flexible`: con
/// textScale alto se pasa del ancho de la tarjeta y tira RenderFlex overflow
/// (las rayas amarillas, no un ellipsis). `scaleDown` lo achica en lugar de
/// recortarlo, que es lo correcto acá: un precio cortado ("39.0…") MIENTE,
/// uno más chico sigue siendo cierto.
class _PriceFit extends StatelessWidget {
  const _PriceFit({required this.alignment, required this.child});

  final Alignment alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: child,
      );
}

/// Tarjeta del layout ancho: todo centrado en una columna.
class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.tier,
    required this.annual,
    required this.isCurrent,
    required this.recommended,
    required this.palette,
    required this.checkout,
  });

  final SubscriptionTier tier;
  final bool annual;
  final bool isCurrent;
  final bool recommended;
  final AppPalette palette;
  final PlanCheckout checkout;

  @override
  Widget build(BuildContext context) {
    final price = kTierPricesArs[tier];
    final amount = price == null ? 0 : (annual ? price.annual : price.monthly);
    final cycleLabel = annual ? 'POR AÑO' : 'POR MES'; // i18n: Fase W3
    final (studentsNum, studentsLabel) = _tierStudents(tier);

    final card = Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(
          color: recommended ? palette.accent : palette.border,
          width: recommended ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: recommended
            ? [
                BoxShadow(
                  color: palette.accent.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _tierName(tier),
            style: GoogleFonts.barlowCondensed(
              color: recommended ? palette.accent : palette.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 18),
          if (annual) ...[
            _AnnualOfferRow(
              tier: tier,
              palette: palette,
              reserveSpace: true, // grilla 2x2: FREE reserva el alto
              compact: false,
            ),
            const SizedBox(height: 8),
          ],
          // Precio-héroe: "$" chico arriba a la izquierda del número gigante.
          _PriceFit(
            alignment: Alignment.center,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, right: 2),
                  child: Text(
                    '\$',
                    style: GoogleFonts.barlowCondensed(
                      color: palette.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  _formatArs(amount),
                  style: GoogleFonts.barlowCondensed(
                    color: palette.textPrimary,
                    fontSize: 52,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            price == null ? 'SIEMPRE GRATIS' : cycleLabel, // i18n: Fase W3
            style: GoogleFonts.barlowCondensed(
              color: palette.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 18),
          Divider(color: palette.border, height: 1),
          const SizedBox(height: 18),
          // Feature: número destacado + label (patrón de la referencia).
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                studentsNum,
                style: GoogleFonts.barlowCondensed(
                  color: recommended ? palette.accent : palette.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                studentsLabel,
                style: TextStyle(color: palette.textMuted, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _PlanCtaButton(
            tier: tier,
            annual: annual,
            isCurrent: isCurrent,
            recommended: recommended,
            palette: palette,
            checkout: checkout,
          ),
        ],
      ),
    );

    if (!recommended) return card;

    // Cinta "MÁS POPULAR" flotando sobre el borde superior de la recomendada.
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Padding(padding: const EdgeInsets.only(top: 14), child: card),
        Positioned(
          top: 0,
          child: _PopularBadge(
            palette: palette,
            fontSize: 12,
            letterSpacing: 0.8,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          ),
        ),
      ],
    );
  }
}

/// Tarjeta del layout angosto (artboard D): dos columnas —plan + precio a la
/// izquierda, caja de alumnos a la derecha— y el CTA a todo el ancho abajo.
///
/// Es una tarjeta distinta y no la ancha "apretada": apilar la de escritorio
/// dejaba una columna centrada altísima donde el precio y el rango de alumnos
/// quedaban a media pantalla de distancia, y había que scrollear una tarjeta
/// entera para comparar dos planes.
class _NarrowPlanCard extends StatelessWidget {
  const _NarrowPlanCard({
    required this.tier,
    required this.annual,
    required this.isCurrent,
    required this.recommended,
    required this.palette,
    required this.checkout,
  });

  final SubscriptionTier tier;
  final bool annual;
  final bool isCurrent;
  final bool recommended;
  final AppPalette palette;
  final PlanCheckout checkout;

  @override
  Widget build(BuildContext context) {
    final price = kTierPricesArs[tier];
    final amount = price == null ? 0 : (annual ? price.annual : price.monthly);
    final cycleLabel = annual ? 'POR AÑO' : 'POR MES'; // i18n: Fase W3
    final (studentsNum, studentsLabel) = _tierStudents(tier);

    final card = Container(
      width: double.infinity,
      // 18 de padding (escala). La recomendada abre a 24 arriba para que la
      // etiqueta "MÁS POPULAR" no se le siente encima al nombre del plan.
      padding: EdgeInsets.fromLTRB(18, recommended ? 24 : 18, 18, 18),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(
          color: recommended ? palette.accent : palette.border,
          width: recommended ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: recommended
            ? [
                BoxShadow(
                  color: palette.accent.withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _tierName(tier),
                      style: GoogleFonts.barlowCondensed(
                        color:
                            recommended ? palette.accent : palette.textPrimary,
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (annual) ...[
                      _AnnualOfferRow(
                        tier: tier,
                        palette: palette,
                        reserveSpace: false, // apiladas: nada con qué alinear
                        compact: true,
                      ),
                      const SizedBox(height: 6),
                    ],
                    _PriceFit(
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '\$',
                            style: GoogleFonts.barlowCondensed(
                              color: palette.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            _formatArs(amount),
                            style: GoogleFonts.barlowCondensed(
                              color: palette.textPrimary,
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              height: 1.0,
                              // Cifras de ancho fijo: al cambiar mensual↔anual
                              // el número no "salta" dígito por dígito.
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      price == null
                          ? 'SIEMPRE GRATIS'
                          : cycleLabel, // i18n: Fase W3
                      style: GoogleFonts.barlowCondensed(
                        color: palette.textMuted,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _StudentsBox(
                number: studentsNum,
                label: studentsLabel,
                recommended: recommended,
                palette: palette,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _PlanCtaButton(
            tier: tier,
            annual: annual,
            isCurrent: isCurrent,
            recommended: recommended,
            palette: palette,
            checkout: checkout,
            minHeight: 46,
          ),
        ],
      ),
    );

    if (!recommended) return card;

    // La etiqueta se sale 10px del borde superior, arriba a la izquierda: el
    // card se baja 10 y la etiqueta se ancla en el tope del Stack.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(padding: const EdgeInsets.only(top: 10), child: card),
        Positioned(
          top: 0,
          left: 18,
          child: _PopularBadge(
            palette: palette,
            fontSize: 9.5,
            letterSpacing: 1.14, // 0.12em
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          ),
        ),
      ],
    );
  }
}

/// Caja compacta con el rango de alumnos, a la derecha del precio.
class _StudentsBox extends StatelessWidget {
  const _StudentsBox({
    required this.number,
    required this.label,
    required this.recommended,
    required this.palette,
  });

  final String number;
  final String label;
  final bool recommended;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        // bg (no bgCard): la caja se hunde dentro de la tarjeta en vez de
        // flotar sobre ella.
        color: palette.bg,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            number,
            style: GoogleFonts.barlowCondensed(
              color: recommended ? palette.accent : palette.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: palette.textMuted, fontSize: 10.5),
          ),
        ],
      ),
    );
  }
}

/// Etiqueta "MÁS POPULAR". Misma píldora en los dos layouts, distinta escala.
class _PopularBadge extends StatelessWidget {
  const _PopularBadge({
    required this.palette,
    required this.fontSize,
    required this.letterSpacing,
    required this.padding,
  });

  final AppPalette palette;
  final double fontSize;
  final double letterSpacing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: palette.accent,
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      child: Text(
        'MÁS POPULAR', // i18n: Fase W3
        style: GoogleFonts.barlowCondensed(
          color: TreinoButtonTokens.foreground(context),
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          letterSpacing: letterSpacing,
        ),
      ),
    );
  }
}

/// El pie de la tarjeta. Tres estados que NO son el mismo con un flag:
/// "tu plan actual", "gratis" y —según la superficie— comprar o decir dónde se
/// compra.
class _PlanCtaButton extends StatelessWidget {
  const _PlanCtaButton({
    required this.tier,
    required this.annual,
    required this.isCurrent,
    required this.recommended,
    required this.palette,
    required this.checkout,
    this.minHeight = 0,
  });

  final SubscriptionTier tier;

  /// Ciclo elegido en el toggle. No cambia lo que se dibuja, pero es dato del
  /// checkout: sin él [PlanCheckoutAvailable.start] no sabe qué está cobrando.
  final bool annual;

  final bool isCurrent;
  final bool recommended;
  final AppPalette palette;

  /// Quién puede cobrar en ESTA superficie. Llega desde `PricingScreen.build`;
  /// esta clase no lo resuelve ni lo re-pregunta.
  final PlanCheckout checkout;

  /// Altura MÍNIMA (no fija): el artboard móvil pide 46, pero con textScale
  /// alto el label crece y el botón tiene que poder crecer con él.
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    if (isCurrent) {
      return _CtaBox(
        minHeight: minHeight,
        borderColor: palette.border,
        child: _ctaLabel(
          'TU PLAN ACTUAL', // i18n: Fase W3
          palette.textMuted,
        ),
      );
    }

    // FREE no pasa por el guard: no es una venta apagada, es que no hay nada
    // que cobrar. Se ve igual en las dos superficies.
    if (kTierPricesArs[tier] == null) {
      return Opacity(
        opacity: 0.5,
        child: _CtaBox(
          minHeight: minHeight,
          borderColor: palette.border,
          child: _ctaLabel(
            'GRATIS', // i18n: Fase W3
            palette.textPrimary,
          ),
        ),
      );
    }

    // `switch` sobre el sellado, no un `if`: si mañana aparece una tercera
    // superficie (in-app purchase de verdad, por ejemplo) esto DEJA DE
    // COMPILAR hasta que alguien decida qué muestra la tarjeta ahí.
    return switch (checkout) {
      // Sin `TreinoTappable`, sin `onTap`, sin ruta: no hay a dónde tocar.
      //
      // Eso NO es una observación decorativa y NO lo garantiza el tipo: colgar
      // acá un `TreinoTappable` con un `showDialog` de checkout —o un
      // `launchUrl` a la pasarela— compila, no toca `start`, no rompe el
      // sellado, y es un punto de venta adentro de la app. Lo que lo ataja es
      // el test «el cartel de la app NO es tappable» del group «guard de
      // superficie»: si envolvés esto, se pone rojo.
      PlanCheckoutOnWebOnly() => _CtaBox(
          minHeight: minHeight,
          borderColor: palette.border,
          child: _ctaLabel(
            _kSubscribeElsewhereShort,
            palette.textMuted,
          ),
        ),
      final PlanCheckoutAvailable disponible => TreinoTappable(
          onTap: () => disponible.start(context, tier: tier, annual: annual),
          child: _CtaBox(
            minHeight: minHeight,
            fillColor: recommended ? palette.accent : null,
            borderColor: recommended ? palette.accent : palette.border,
            child: _ctaLabel(
              'ELEGIR PLAN', // i18n: Fase W3
              recommended
                  ? TreinoButtonTokens.foreground(context)
                  : palette.textPrimary,
            ),
          ),
        ),
    };
  }

  Widget _ctaLabel(String label, Color color) => Text(
        label,
        textAlign: TextAlign.center,
        style: GoogleFonts.barlowCondensed(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      );
}

/// La caja del pie de tarjeta. Existe para que los estados compartan geometría
/// exacta: en la grilla 2x2 las cuatro tarjetas viven en el mismo
/// `IntrinsicHeight`, así que si el cartel de "se contrata en la web" midiera
/// distinto que el botón, cambiar de superficie descalzaría la fila entera.
class _CtaBox extends StatelessWidget {
  const _CtaBox({
    required this.minHeight,
    required this.borderColor,
    required this.child,
    this.fillColor,
  });

  final double minHeight;
  final Color borderColor;
  final Color? fillColor;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        constraints: BoxConstraints(minHeight: minHeight),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fillColor ?? Colors.transparent,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: child,
      );
}

/// La línea que cierra la pantalla cuando esta superficie no cobra.
///
/// El cartel de cada tarjeta dice DÓNDE; esto lo explica UNA vez y completo,
/// para que el PF no se quede con la sensación de que le falta algo: ve los
/// cuatro planes, los precios y su cupo — lo único que no hace acá es pagar.
///
/// No dice "próximamente" (sería falso: en la web ya se contrata) ni nombra a
/// Apple. Y no es un link: en la app no puede haber navegación a la compra.
class _WhereToSubscribeNote extends StatelessWidget {
  const _WhereToSubscribeNote({
    required this.checkout,
    required this.palette,
    required this.fontSize,
  });

  final PlanCheckout checkout;
  final AppPalette palette;
  final double fontSize;

  @override
  Widget build(BuildContext context) => switch (checkout) {
        PlanCheckoutAvailable() => const SizedBox.shrink(),
        PlanCheckoutOnWebOnly() => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _kSubscribeElsewhereLong,
              style: TextStyle(
                color: palette.textMuted,
                fontSize: fontSize,
                height: 1.35,
              ),
              textAlign: TextAlign.center,
            ),
          ),
      };
}
