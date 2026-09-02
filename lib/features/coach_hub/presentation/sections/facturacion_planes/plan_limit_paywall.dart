import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../../core/widgets/motion/treino_tappable.dart';
import '../../../../../core/widgets/treino_icon.dart';
import '../../../../coach/domain/subscription_tier.dart';
import 'plan_checkout.dart';

/// Muestra el paywall de bloqueo cuando el PF intentó agregar un alumno que
/// supera el límite de su plan (Fase 7, PR3 UI — el trigger real es el
/// enforcement de `acceptTrainerLink` en PR4).
///
/// Diseño honesto (principio del estudio de paywall): dice claramente que
/// llegó al límite, cuál es su plan actual, y ofrece el upsell al siguiente
/// tier con su precio. Misma armonía que la pricing page (Mint Magenta,
/// precio-héroe, Barlow Condensed).
///
/// [currentTier] es el plan vigente del PF. Si el siguiente tier existe,
/// muestra el upsell; si ya está en Plan 2 (tope Fase 1), muestra el mensaje
/// del plan a-medida.
/// Por qué el PF chocó contra el límite. Son DOS problemas de producto
/// distintos y ninguna variante de `tier` puede codificar la diferencia sin
/// mentir en alguna de las dos ramas (diseño D-2):
///
/// - [planLimit] — está al tope de su tier vigente. Problema de upsell.
/// - [subscriptionInactive] — pagó un tier más alto, pero su suscripción está
///   `pending`/`paused`/vencida, así que su límite EFECTIVO cayó a Free.
///   Problema de cobro. Ofrecerle un plan más caro acá es el mensaje
///   equivocado: ya compró uno.
enum PlanLimitReason { planLimit, subscriptionInactive }

/// Envoltura visual del paywall. El CONTENIDO es idéntico en las dos: lo único
/// que cambia es cómo entra a la pantalla.
///
/// - [dialog] — card centrada con ancho máximo. Es la forma de WEB (Coach Hub):
///   una app de escritorio con sidebar y ventana ancha. Un panel que sube desde
///   el borde inferior ahí es un error de plataforma, no una decisión estética.
/// - [sheet] — bottom sheet pegado al borde inferior, ancho completo,
///   redondeado sólo arriba, descartable deslizando. Es la forma de MÓVIL: el
///   pulgar llega al CTA y el gesto de descarte es el nativo del sistema.
enum PlanLimitPaywallForm { dialog, sheet }

/// Fuerza la forma del paywall. SÓLO para tests.
///
/// `kIsWeb` es una constante de COMPILACIÓN: bajo `flutter test` (que corre en
/// la VM de Dart, no en un browser) vale `false` siempre y no hay forma de
/// moverlo. Sin este seam la rama [PlanLimitPaywallForm.dialog] quedaría
/// literalmente sin cobertura, y un test que dijera «en web es dialog» estaría
/// verde sin haber probado nada.
///
/// Nadie en `lib/` lo lee ni lo escribe: el default `null` deja mandar a la
/// plataforma. Los tests lo fijan y lo devuelven a `null` con `addTearDown`.
@visibleForTesting
PlanLimitPaywallForm? debugPlanLimitPaywallForm;

/// Forma efectiva: el override si un test lo fijó, si no la plataforma.
PlanLimitPaywallForm _resolveForm() =>
    debugPlanLimitPaywallForm ??
    (kIsWeb ? PlanLimitPaywallForm.dialog : PlanLimitPaywallForm.sheet);

Future<void> showPlanLimitPaywall(
  BuildContext context, {
  required SubscriptionTier currentTier,
  PlanLimitReason reason = PlanLimitReason.planLimit,
  SubscriptionStatus? subscriptionStatus,
  String? billingRoute,
}) {
  // Un solo contenido para las dos envolturas. Si mañana cambia el copy o el
  // CTA, cambia UNA vez: duplicarlo garantiza que tarde o temprano web y móvil
  // digan cosas distintas y nadie se entere hasta que lo reporte un usuario.
  final content = _PlanLimitPaywallContent(
    currentTier: currentTier,
    reason: reason,
    subscriptionStatus: subscriptionStatus,
    billingRoute: billingRoute,
  );
  final barrierColor = Colors.black.withValues(alpha: 0.6);

  if (_resolveForm() == PlanLimitPaywallForm.dialog) {
    return showDialog<void>(
      context: context,
      barrierColor: barrierColor,
      builder: (_) => _PlanLimitPaywallDialog(content: content),
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    // OBLIGATORIO, no una preferencia. `showModalBottomSheet` defaultea a
    // `useRootNavigator: false`, y en la app móvil eso lo montaría en el
    // Navigator del ShellRoute — que vive DENTRO del `Scaffold.body` del shell
    // (`router.dart`, `_ShellScaffold`). El sheet quedaría recortado al body,
    // con la bottom bar flotando ENCIMA y el scrim sin taparla. Además el
    // shell popea popups en los dos navigators al cambiar de tab
    // (`router.dart`, `onTap` de la bottom bar), así que el sheet tiene que
    // estar donde el `showDialog` de antes: en el raíz. `showDialog` ya
    // defaultea a `useRootNavigator: true` — esto mantiene la paridad.
    useRootNavigator: true,
    // El contenido pasa la mitad de la pantalla con textScale de accesibilidad.
    // Sin esto el sheet se topa contra el 50% y se corta.
    isScrollControlled: true,
    // El fondo real lo pinta `_PlanLimitPaywallSheet` en su propio Container:
    // es la única forma de redondear SÓLO las esquinas de arriba sin que el
    // material del sheet dibuje su rectángulo debajo.
    backgroundColor: Colors.transparent,
    barrierColor: barrierColor,
    builder: (_) => _PlanLimitPaywallSheet(content: content),
  );
}

/// Envoltura DIALOG — web. Card centrada, ancho acotado, esquinas todas
/// redondeadas.
class _PlanLimitPaywallDialog extends StatelessWidget {
  const _PlanLimitPaywallDialog({required this.content});

  final Widget content;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Dialog(
      backgroundColor: palette.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: palette.accent, width: 1.5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        // Scrolleable para no overflowear en ventanas de poca altura.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: content,
        ),
      ),
    );
  }
}

/// Envoltura SHEET — móvil. Sube desde abajo, ancho completo, pegado al borde
/// inferior, redondeado sólo arriba.
class _PlanLimitPaywallSheet extends StatelessWidget {
  const _PlanLimitPaywallSheet({required this.content});

  final Widget content;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // Techo de altura: `isScrollControlled` habilita la pantalla entera, y sin
    // techo un contenido alto (textScale de accesibilidad) empuja el sheet
    // hasta desbordar. Con techo, el `SingleChildScrollView` de abajo scrollea.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;

    return Padding(
      // Cualquier inset del sistema (teclado incluido) empuja el sheet en vez
      // de taparlo.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(
            top: BorderSide(color: palette.accent.withValues(alpha: 0.33)),
          ),
        ),
        // `bottom: true` — la barra de gestos no se come el "Ahora no".
        // `top: false` — el sheet nunca llega a la barra de estado.
        child: SafeArea(
          top: false,
          bottom: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle de arrastre: la señal de que esto se descarta
                // deslizando, no sólo con el "Ahora no". 40x4 con `border` y
                // radio 2 es la medida que ya usan los ~25 sheets del repo
                // (`athlete_picker_sheet`, `set_entry_sheet`,
                // `review_bottom_sheet`, …): otro ancho se lee como otro
                // control.
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Flexible(child: SingleChildScrollView(child: content)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Contenido del paywall — EL MISMO en las dos envolturas.
///
/// Vive separado de [_PlanLimitPaywallDialog] y [_PlanLimitPaywallSheet] a
/// propósito: las envolturas deciden CÓMO entra a la pantalla, esto decide QUÉ
/// dice. Un cambio de copy toca un solo lugar.
class _PlanLimitPaywallContent extends StatelessWidget {
  const _PlanLimitPaywallContent({
    required this.currentTier,
    this.reason = PlanLimitReason.planLimit,
    this.subscriptionStatus,
    this.billingRoute,
  });

  final SubscriptionTier currentTier;
  final PlanLimitReason reason;
  final SubscriptionStatus? subscriptionStatus;

  /// Ruta a la vista de facturacion. NULL = esta superficie no tiene una (la
  /// app movil no tiene pantalla de facturacion), y entonces el CTA explica
  /// en vez de navegar a una ruta inexistente y morir.
  final String? billingRoute;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isInactive = reason == PlanLimitReason.subscriptionInactive;
    // `reason` MANDA sobre el tier: un plan2 con la suscripción suspendida
    // necesita regularizar, no el aviso del plan a-medida del tope.
    final next = isInactive ? null : currentTier.nextTier;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Ícono + título.
        Center(
          child: Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.08),
              border: Border.all(color: palette.accent.withValues(alpha: 0.33)),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(TreinoIcon.lock, size: 28, color: palette.accent),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          isInactive
              ? 'TU SUSCRIPCIÓN ESTÁ SUSPENDIDA' // i18n: Fase W3
              : 'LLEGASTE AL LÍMITE DE TU PLAN', // i18n: Fase W3
          textAlign: TextAlign.center,
          style: GoogleFonts.barlowCondensed(
            color: palette.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isInactive
              // TODO(producto): copy placeholder — pendiente de revisión
              // antes de cerrar el PR (diseño D-2, riesgo residual 4).
              ? 'Mientras tu suscripción no esté al día, tu cuenta '
                  'funciona con el límite del plan Free. Ningún alumno '
                  'se elimina.' // i18n: Fase W3
              : 'Tu plan ${_tierName(currentTier)} incluye '
                  '${_cupoTexto(currentTier)}. Para sumar más, '
                  'subí de plan.', // i18n: Fase W3
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.textMuted, fontSize: 14),
        ),
        const SizedBox(height: 22),
        if (isInactive)
          _ReactivateBox(
            currentTier: currentTier,
            status: subscriptionStatus,
            palette: palette,
          )
        else if (next != null)
          _UpsellBox(nextTier: next, palette: palette)
        else
          _CustomPlanBox(palette: palette),
        const SizedBox(height: 20),
        // CTA principal.
        _PrimaryCta(
          hasNext: next != null,
          isInactive: isInactive,
          billingRoute: billingRoute,
          palette: palette,
        ),
        const SizedBox(height: 10),
        TreinoTappable(
          onTap: () => Navigator.of(context).pop(),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'Ahora no', // i18n: Fase W3
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Caja de upsell al siguiente tier: nombre + precio-héroe + rango de alumnos.
class _UpsellBox extends StatelessWidget {
  const _UpsellBox({required this.nextTier, required this.palette});

  final SubscriptionTier nextTier;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final price = kTierPricesArs[nextTier]!;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.bg,
        border: Border.all(color: palette.accent),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            'PASATE A ${_tierName(nextTier).toUpperCase()}', // i18n: Fase W3
            style: GoogleFonts.barlowCondensed(
              color: palette.accent,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          // Precio-héroe. El Row no lleva `Flexible` y con textScale alto se
          // pasa del ancho de la caja: dentro del sheet móvil (390 pt menos
          // los paddings) eso ya son rayas amarillas a textScale 2.0.
          // `scaleDown` lo achica en vez de recortarlo — un precio cortado
          // («39.0…») MIENTE, uno más chico sigue siendo cierto. Mismo
          // criterio (y misma causa) que `_PriceFit` en la pricing page.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 2),
                  child: Text(
                    '\$',
                    style: GoogleFonts.barlowCondensed(
                      color: palette.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  _formatArs(price.monthly),
                  style: GoogleFonts.barlowCondensed(
                    color: palette.textPrimary,
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 18, left: 4),
                  child: Text(
                    '/mes', // i18n: Fase W3
                    style: TextStyle(color: palette.textMuted, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            nextTier.isUnlimited
                ? 'Alumnos sin límite' // i18n: Fase W3
                : 'Hasta ${nextTier.weightLimit} alumnos', // i18n: Fase W3
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Caja para cuando el PF ya está en Plan 2 (tope Fase 1) — plan a-medida.
class _CustomPlanBox extends StatelessWidget {
  const _CustomPlanBox({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.bg,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            'PLAN A MEDIDA', // i18n: Fase W3
            style: GoogleFonts.barlowCondensed(
              color: palette.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Estás en el plan más grande. Para más de 15 alumnos '
            'estamos preparando un plan a tu medida.', // i18n: Fase W3
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Caja de la rama `subscription-inactive`. Hermana de [_UpsellBox], pero
/// SIN precio-héroe: el precio no es la pregunta acá — el PF ya compró este
/// plan, sólo hay que reactivarlo.
class _ReactivateBox extends StatelessWidget {
  const _ReactivateBox({
    required this.currentTier,
    required this.status,
    required this.palette,
  });

  final SubscriptionTier currentTier;
  final SubscriptionStatus? status;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.bg,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            'TU PLAN: ${_tierName(currentTier).toUpperCase()}', // i18n: Fase W3
            style: GoogleFonts.barlowCondensed(
              color: palette.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            // TODO(producto): copy placeholder — pendiente de revisión.
            'Reactivalo y volvés a tus ${_cupoTexto(currentTier)} '
            'al instante.', // i18n: Fase W3
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.textMuted, fontSize: 13),
          ),
          if (status != null) ...[
            const SizedBox(height: 8),
            Text(
              'Estado: ${_statusName(status!)}', // i18n: Fase W3
              style: TextStyle(color: palette.textMuted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}

class _PrimaryCta extends StatelessWidget {
  const _PrimaryCta({
    required this.hasNext,
    required this.isInactive,
    required this.billingRoute,
    required this.palette,
  });

  final bool hasNext;
  final bool isInactive;
  final String? billingRoute;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    if (isInactive) {
      return TreinoTappable(
        onTap: () {
          // REACTIVAR ES COBRAR. Este CTA es el otro punto de entrada al pago
          // que se ve DESDE EL TELEFONO (dashboard movil -> aceptar solicitud
          // con la suscripcion pausada -> este modal), y es donde el dia que se
          // cablee Mercado Pago alguien va a escribir la llamada: reactivar es
          // la mitad del negocio de una suscripcion y la pricing page ni
          // siquiera se lo ofrece a quien ya tiene el plan.
          //
          // Por eso pasa por el MISMO guard que la pricing page y no por
          // `billingRoute == null`. La ruta es un string que hoy correlaciona
          // con la superficie de casualidad (solo los callsites del Coach Hub
          // la pasan): el dia que alguien agregue '/ajustes' al router movil,
          // esa correlacion se rompe sin que nadie lo revise. La superficie no.
          //
          // El `switch` es exhaustivo sobre el sellado: una tercera superficie
          // rompe la compilacion aca tambien.
          final checkout = resolvePlanCheckout();
          final route = billingRoute;
          Navigator.of(context).pop();
          switch (checkout) {
            case PlanCheckoutOnWebOnly():
              // La app informa donde se regulariza. No navega, no linkea y no
              // abre nada: si algun dia esto arranca un cobro, es 3.1.3(c).
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Regularizá tu suscripción desde TREINO web.',
                  ), // i18n: Fase W3
                ),
              );
            case PlanCheckoutAvailable():
              if (route == null) {
                // Superficie que cobra pero sin vista de facturacion cableada.
                // Antes esto navegaba a '/ajustes' fijo y en movil moria contra
                // una ruta inexistente: el modal decia lo correcto y el boton
                // no hacia nada. Mejor decirlo que fingirlo.
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Regularizá tu suscripción desde TREINO web.',
                    ), // i18n: Fase W3
                  ),
                );
                return;
              }
              // NUNCA mandar a /facturacion/planes aca: es la pagina de upsell,
              // el mensaje opuesto al que necesita quien ya pago.
              // TODO(producto): deep-link al tab de Facturacion cuando exista.
              context.push(route);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.accent,
            borderRadius: BorderRadius.circular(9999),
          ),
          child: Text(
            'REGULARIZAR', // i18n: Fase W3
            style: GoogleFonts.barlowCondensed(
              color: TreinoButtonTokens.foreground(context),
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
      );
    }
    return TreinoTappable(
      onTap: () {
        Navigator.of(context).pop();
        if (hasNext) {
          // Lleva a la pricing page para completar el cambio de plan.
          context.push('/facturacion/planes');
        } else {
          // Plan 2 tope: aviso del plan a-medida (mock hasta canal de contacto).
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Muy pronto vas a poder tener más de 15 alumnos.',
              ), // i18n: Fase W3
            ),
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.accent,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(
          hasNext ? 'VER PLANES' : 'CONTACTANOS', // i18n: Fase W3
          style: GoogleFonts.barlowCondensed(
            color: TreinoButtonTokens.foreground(context),
            fontSize: 14,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

String _statusName(SubscriptionStatus status) => switch (status) {
      SubscriptionStatus.active => 'activa', // i18n: Fase W3
      SubscriptionStatus.pending => 'pendiente de pago', // i18n: Fase W3
      SubscriptionStatus.grace => 'con pago pendiente', // i18n: Fase W3
      SubscriptionStatus.paused => 'pausada', // i18n: Fase W3
      SubscriptionStatus.cancelled => 'cancelada', // i18n: Fase W3
    };

/// Cupo del tier en texto.
///
/// `weightLimit == null` (plan3) NO es un dato faltante: significa SIN
/// LÍMITE. Interpolarlo directo renderiza la palabra «null» — y eso fue
/// exactamente lo que se publicó: el upsell al plan más caro decía
/// «Hasta null alumnos». Cualquier lugar que muestre el cupo pasa por acá.
String _cupoTexto(SubscriptionTier tier) => tier.isUnlimited
    ? 'alumnos sin límite' // i18n: Fase W3
    : '${tier.weightLimit} alumnos'; // i18n: Fase W3

String _tierName(SubscriptionTier tier) => switch (tier) {
      SubscriptionTier.free => 'Free', // i18n: Fase W3
      SubscriptionTier.plan1 => 'Plan 1', // i18n: Fase W3
      SubscriptionTier.plan2 => 'Plan 2', // i18n: Fase W3
      SubscriptionTier.plan3 => 'Plan 3', // i18n: Fase W3
    };

String _formatArs(int amount) {
  final s = amount.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return buf.toString();
}
