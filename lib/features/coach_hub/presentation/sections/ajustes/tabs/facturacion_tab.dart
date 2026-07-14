import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach/domain/weighted_load.dart';
import 'package:treino/features/profile/application/user_providers.dart';

/// Tab «Facturación TREINO» (paywall Fase 7, PR2 — vista read-only).
///
/// Facturación de la SUSCRIPCIÓN del PF a TREINO (su plan + uso). La
/// facturación de alumnos (PF → alumnos) vive en la sección Pagos, no acá.
///
/// PR2 muestra SOLO lectura: plan actual + carga ponderada N/límite. Sin
/// pantalla de cambio de plan (eso es PR3, con el flujo de Mercado Pago) ni
/// historial de comprobantes (Fase 2). Un PF sin `subscription` en su doc es
/// Free por definición (sin backfill).
///
/// El uso se computa client-side desde los `trainerLinks` con
/// [computeWeightedLoad] (active=1.0, paused=0.5) — misma lógica que el gate
/// server-side de PR4. El `weightedLoad` denormalizado que el CF escribirá
/// aún no se puebla, así que la UI lo calcula en vivo.
class FacturacionTab extends ConsumerWidget {
  const FacturacionTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);

    final profile = ref.watch(userProfileProvider).valueOrNull;
    final sub = profile?.subscription;
    // Sin suscripción → Free (sin backfill). Límite del tier vigente.
    final tier = sub?.tier ?? SubscriptionTier.free;
    final limit = sub?.weightLimit ?? tier.weightLimit;

    final links = ref.watch(trainerLinksStreamProvider).valueOrNull ?? const [];
    final load = computeWeightedLoad(links);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'FACTURACIÓN TREINO', // i18n: Fase W3
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tu plan y uso de TREINO.', // i18n: Fase W3
          style: TextStyle(color: palette.textMuted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        _CurrentPlanCard(
          tier: tier,
          load: load,
          limit: limit,
          palette: palette,
        ),
      ],
    );
  }
}

/// Nombre visible del tier.
String _tierLabel(SubscriptionTier tier) => switch (tier) {
      SubscriptionTier.free => 'Free', // i18n: Fase W3
      SubscriptionTier.plan1 => 'Plan 1', // i18n: Fase W3
      SubscriptionTier.plan2 => 'Plan 2', // i18n: Fase W3
    };

/// Formatea la carga ponderada: entero sin decimal (7), fracción con uno (6.5).
String _formatLoad(double load) => load == load.roundToDouble()
    ? load.toStringAsFixed(0)
    : load.toStringAsFixed(1);

class _CurrentPlanCard extends StatelessWidget {
  const _CurrentPlanCard({
    required this.tier,
    required this.load,
    required this.limit,
    required this.palette,
  });

  final SubscriptionTier tier;
  final double load;
  final int limit;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    // Fracción para la barra, tope en 1.0 aunque esté sobre el límite.
    final fraction = limit == 0 ? 0.0 : (load / limit).clamp(0.0, 1.0);
    final overLimit = load > limit;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PLAN ACTUAL', // i18n: Fase W3
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'TREINO Coach · ${_tierLabel(tier)}', // i18n: Fase W3
                      style: GoogleFonts.barlowCondensed(
                        color: palette.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              // CAMBIAR PLAN llega en PR3 (flujo Mercado Pago). Se muestra
              // deshabilitado para no prometer una pantalla que no existe.
              _ChangePlanButton(palette: palette),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${_formatLoad(load)} / $limit',
                style: GoogleFonts.barlowCondensed(
                  color: overLimit ? palette.highlight : palette.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'ALUMNOS', // i18n: Fase W3
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: palette.border,
              valueColor: AlwaysStoppedAnimation(
                overLimit ? palette.highlight : palette.accent,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            // El peso ponderado explica por qué el número puede tener decimal.
            'Cada alumno activo cuenta 1 y cada pausado ½.', // i18n: Fase W3
            style: TextStyle(color: palette.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _ChangePlanButton extends StatelessWidget {
  const _ChangePlanButton({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Cambiar plan', // i18n: Fase W3
      child: GestureDetector(
        onTap: () => context.push('/facturacion/planes'),
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: palette.accent),
            borderRadius: BorderRadius.circular(9999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(TreinoIcon.money, size: 14, color: palette.accent),
              const SizedBox(width: 6),
              Text(
                'CAMBIAR PLAN', // i18n: Fase W3
                style: GoogleFonts.barlowCondensed(
                  color: palette.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
