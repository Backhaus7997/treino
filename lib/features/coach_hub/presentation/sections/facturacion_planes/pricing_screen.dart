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
/// modal de límite. El botón "ELEGIR PLAN" está MOCKEADO en este PR (aviso
/// "próximamente") — el flujo real de Mercado Pago se cablea cuando la cuenta
/// MP esté lista. Precios de [kTierPricesArs].
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

    return LayoutBuilder(
      builder: (context, constraints) {
        void onCycleChanged(bool v) => setState(() => _annual = v);

        if (constraints.maxWidth < _kNarrowBreakpoint) {
          return _NarrowBody(
            annual: _annual,
            currentTier: currentTier,
            palette: palette,
            onCycleChanged: onCycleChanged,
          );
        }
        return _WideBody(
          annual: _annual,
          currentTier: currentTier,
          palette: palette,
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
    required this.onCycleChanged,
  });

  final bool annual;
  final SubscriptionTier currentTier;
  final AppPalette palette;
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
            narrow: false,
          ),
          const SizedBox(height: 24),
          Text(
            'Renovación automática. Podés cancelar cuando quieras '
            'desde Facturación.', // i18n: Fase W3
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
    required this.onCycleChanged,
  });

  final bool annual;
  final SubscriptionTier currentTier;
  final AppPalette palette;
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
            narrow: true,
          ),
          const SizedBox(height: 20),
          Text(
            'Renovación automática. Podés cancelar cuando quieras '
            'desde Facturación.', // i18n: Fase W3
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
    required this.narrow,
  });

  final bool annual;
  final SubscriptionTier currentTier;
  final AppPalette palette;
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
              )
            : _PlanCard(
                tier: tier,
                annual: annual,
                isCurrent: currentTier == tier,
                recommended: tier == recommended,
                palette: palette,
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
  });

  final SubscriptionTier tier;
  final bool annual;
  final bool isCurrent;
  final bool recommended;
  final AppPalette palette;

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
            isCurrent: isCurrent,
            recommended: recommended,
            isFree: price == null,
            palette: palette,
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
  });

  final SubscriptionTier tier;
  final bool annual;
  final bool isCurrent;
  final bool recommended;
  final AppPalette palette;

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
            isCurrent: isCurrent,
            recommended: recommended,
            isFree: price == null,
            palette: palette,
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

class _PlanCtaButton extends StatelessWidget {
  const _PlanCtaButton({
    required this.isCurrent,
    required this.recommended,
    required this.isFree,
    required this.palette,
    this.minHeight = 0,
  });

  final bool isCurrent;
  final bool recommended;
  final bool isFree;
  final AppPalette palette;

  /// Altura MÍNIMA (no fija): el artboard móvil pide 46, pero con textScale
  /// alto el label crece y el botón tiene que poder crecer con él.
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    if (isCurrent) {
      return Container(
        width: double.infinity,
        constraints: BoxConstraints(minHeight: minHeight),
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(
          'TU PLAN ACTUAL', // i18n: Fase W3
          style: GoogleFonts.barlowCondensed(
            color: palette.textMuted,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      );
    }

    final enabled = !isFree;
    final filled = recommended;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: TreinoTappable(
        onTap: enabled ? () => _showComingSoon(context) : null,
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(minHeight: minHeight),
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? palette.accent : Colors.transparent,
            border: Border.all(
              color: filled ? palette.accent : palette.border,
            ),
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Text(
            isFree ? 'GRATIS' : 'ELEGIR PLAN', // i18n: Fase W3
            style: GoogleFonts.barlowCondensed(
              color: filled
                  ? TreinoButtonTokens.foreground(context)
                  : palette.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    // MOCK: el flujo real de Mercado Pago se cablea cuando la cuenta esté
    // lista (createPreapproval → checkout). Por ahora, aviso honesto.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'El pago con Mercado Pago se habilita muy pronto.', // i18n: Fase W3
        ),
      ),
    );
  }
}
