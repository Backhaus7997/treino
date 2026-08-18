import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../../core/widgets/motion/treino_tappable.dart';
import '../../../../coach/domain/subscription_tier.dart';

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

Future<void> showPlanLimitPaywall(
  BuildContext context, {
  required SubscriptionTier currentTier,
  PlanLimitReason reason = PlanLimitReason.planLimit,
  SubscriptionStatus? subscriptionStatus,
  String? billingRoute,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => _PlanLimitPaywallDialog(
      currentTier: currentTier,
      reason: reason,
      subscriptionStatus: subscriptionStatus,
      billingRoute: billingRoute,
    ),
  );
}

class _PlanLimitPaywallDialog extends StatelessWidget {
  const _PlanLimitPaywallDialog({
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

    return Dialog(
      backgroundColor: palette.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: palette.accent, width: 1.5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        // Scrolleable para no overflowear en ventanas de poca altura.
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Ícono + título.
              Icon(Icons.lock_outline, size: 40, color: palette.accent),
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
                    : 'Tu plan ${_tierName(currentTier)} incluye hasta '
                        '${currentTier.weightLimit} alumnos. Para sumar más, '
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
          ),
        ),
      ),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
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
          const SizedBox(height: 4),
          Text(
            'Hasta ${nextTier.weightLimit} alumnos', // i18n: Fase W3
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
            'Reactivalo y volvés a tus ${currentTier.weightLimit} alumnos '
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
          final route = billingRoute;
          Navigator.of(context).pop();
          if (route == null) {
            // Superficie sin vista de facturacion (la app movil no tiene
            // ninguna). Antes esto navegaba a '/ajustes' fijo y en movil moria
            // contra una ruta inexistente: el modal decia lo correcto y el
            // boton no hacia nada. Mejor decirlo que fingirlo.
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Regularizá tu suscripción desde TREINO web.',
                ), // i18n: Fase W3
              ),
            );
            return;
          }
          // NUNCA mandar a /facturacion/planes acá: es la página de upsell, el
          // mensaje opuesto al que necesita quien ya pagó.
          // TODO(producto): deep-link al tab de Facturación cuando exista.
          context.push(route);
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
              color: palette.bg,
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
          borderRadius: BorderRadius.circular(9999),
        ),
        child: Text(
          hasNext ? 'VER PLANES' : 'CONTACTANOS', // i18n: Fase W3
          style: GoogleFonts.barlowCondensed(
            color: palette.bg,
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

String _tierName(SubscriptionTier tier) => switch (tier) {
      SubscriptionTier.free => 'Free', // i18n: Fase W3
      SubscriptionTier.plan1 => 'Plan 1', // i18n: Fase W3
      SubscriptionTier.plan2 => 'Plan 2', // i18n: Fase W3
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
