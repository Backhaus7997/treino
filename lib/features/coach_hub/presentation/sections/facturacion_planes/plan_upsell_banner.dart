import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/widgets/motion/treino_tappable.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/profile/application/user_providers.dart';

/// Nombre visible del tier. Fuente única de la etiqueta de plan en el hub web
/// — la pricing page usa su propia variante en MAYÚSCULAS (nombres de card),
/// pero todo lo que sea prosa ("Estás en Free", subtítulo del sidebar) sale
/// de acá para que no se desincronice como pasó con los carteles duplicados.
String tierLabel(SubscriptionTier tier) => switch (tier) {
      SubscriptionTier.free => 'Free', // i18n: Fase W3
      SubscriptionTier.plan1 => 'Plan 1', // i18n: Fase W3
      SubscriptionTier.plan2 => 'Plan 2', // i18n: Fase W3
      SubscriptionTier.plan3 => 'Plan 3', // i18n: Fase W3
    };

/// Etiqueta de plan para superficies angostas (subtítulo del sidebar), donde
/// "Free" solo no se lee como un plan. Anteponer "Plan " a secas daría
/// "Plan Plan 1" en los tiers pagos, que ya lo traen en el nombre.
String tierPlanLabel(SubscriptionTier tier) =>
    tier == SubscriptionTier.free ? 'Plan Free' : tierLabel(tier); // i18n: W3

/// Invitación a pasar a un plan pago — se muestra en «Ajustes → Cuenta», que
/// es donde aterriza el PF al tocar cualquiera de los dos símbolos de usuario
/// del shell (perfil del sidebar y avatar del top bar).
///
/// Es un banner de UPSELL, no la vista de facturación: no repite la barra de
/// uso ponderado de [FacturacionTab] a propósito. Su único trabajo es contar
/// en qué plan está el PF y mandarlo a `/facturacion/planes`.
///
/// Se auto-oculta cuando no hay nada que vender: `plan3` es el tope, así que
/// `tier.nextTier == null` → `SizedBox.shrink()`. Un PF sin `subscription` en
/// su doc es Free por definición (sin backfill), igual que en Facturación.
class PlanUpsellBanner extends ConsumerWidget {
  const PlanUpsellBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final tier =
        ref.watch(userProfileProvider).valueOrNull?.subscription?.tier ??
            SubscriptionTier.free;
    final next = tier.nextTier;
    if (next == null) return const SizedBox.shrink();

    // El margen inferior lo pone el banner y no el llamador porque el banner
    // decide su propia visibilidad: si el gap viviera afuera, un PF en plan3
    // vería un hueco de 20 px sin nada adentro.
    return Container(
      key: const Key('plan_upsell_banner'),
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
          Icon(TreinoIcon.sparkle, size: 20, color: palette.accent),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TU PLAN · ${tierLabel(tier).toUpperCase()}', // i18n: Fase W3
                  style: GoogleFonts.barlowCondensed(
                    color: palette.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.hairline),
                Text(
                  _pitch(tier, next),
                  style: TextStyle(color: palette.textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s14),
          const _VerPlanesButton(),
        ],
      ),
    );
  }
}

/// Copy del upsell: dónde estás hoy y qué te llevás si subís. El límite se
/// lee de `weightLimit` (mismo mapa que el gate server-side), así que si
/// cambian los tiers el texto acompaña solo.
String _pitch(SubscriptionTier tier, SubscriptionTier next) {
  final limit = tier.weightLimit;
  final nextLimit = next.weightLimit;
  // `null` sólo puede venir de plan3, que nunca es `tier` acá (se auto-oculta),
  // pero sí puede ser el `next` de plan2.
  final here = limit == null
      ? 'sin límite de alumnos' // i18n: Fase W3
      : 'hasta $limit alumnos'; // i18n: Fase W3
  final there = nextLimit == null
      ? 'alumnos sin límite' // i18n: Fase W3
      : 'hasta $nextLimit alumnos'; // i18n: Fase W3
  // Una línea, no tres. El banner vive ARRIBA de los datos personales del PF:
  // cada línea de más empuja el form (y el botón GUARDAR CAMBIOS, que está
  // pinneado al tope del scroll) fuera del viewport. El "cambiás cuando
  // quieras" ya lo dice la pricing page, que es adonde lleva el CTA.
  return 'Estás en ${tierLabel(tier)}, $here. '
      'Con ${tierLabel(next)}, $there.'; // i18n: Fase W3
}

/// CTA a la pricing page. `push` (no `go`) para que el PF vuelva a Cuenta con
/// el botón de atrás en vez de caer en el dashboard.
class _VerPlanesButton extends StatelessWidget {
  const _VerPlanesButton();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Semantics(
      button: true,
      label: 'Ver planes y precios', // i18n: Fase W3
      child: TreinoTappable(
        key: const Key('plan_upsell_cta'),
        onTap: () => context.push('/facturacion/planes'),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s14,
            vertical: AppSpacing.s8,
          ),
          decoration: BoxDecoration(
            color: palette.accent,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'VER PLANES', // i18n: Fase W3
                style: GoogleFonts.barlowCondensed(
                  color: TreinoButtonTokens.foreground(context),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(width: AppSpacing.hairline),
              Icon(
                TreinoIcon.arrowRight,
                size: 14,
                color: TreinoButtonTokens.foreground(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
