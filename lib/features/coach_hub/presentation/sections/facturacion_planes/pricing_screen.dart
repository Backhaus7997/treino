import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../../core/widgets/motion/treino_tappable.dart';
import '../../../../coach/domain/subscription_tier.dart';
import '../../../../profile/application/user_providers.dart';

/// Pricing page del paywall PF→TREINO (Fase 7, PR3 UI).
///
/// Estilo inspirado en pricing pages SaaS (ref Rela/Fibrit) adaptado a la
/// identidad Mint Magenta: precio-héroe gigante, card recomendada ELEVADA con
/// cinta "MÁS POPULAR", toggle Mensual/Anual centrado con "Ahorrá 2 meses".
///
/// Se abre desde "CAMBIAR PLAN" en Facturación. El botón "ELEGIR PLAN" está
/// MOCKEADO en este PR (aviso "próximamente") — el flujo real de Mercado Pago
/// se cablea cuando la cuenta MP esté lista. Precios de [kTierPricesArs].
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
            annual: _annual,
            palette: palette,
            onChanged: (v) => setState(() => _annual = v),
          ),
          const SizedBox(height: 40),
          _PlanCardsRow(
            annual: _annual,
            currentTier: currentTier,
            palette: palette,
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
/// seleccionado subrayado en mint (patrón de la referencia).
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

/// Fila de las 3 cards. La recomendada (Plan 1) va elevada. En anchos chicos
/// (< 820px) se apilan verticalmente.
class _PlanCardsRow extends StatelessWidget {
  const _PlanCardsRow({
    required this.annual,
    required this.currentTier,
    required this.palette,
  });

  final bool annual;
  final SubscriptionTier currentTier;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    _PlanCard card(SubscriptionTier tier, {required bool recommended}) =>
        _PlanCard(
          tier: tier,
          annual: annual,
          isCurrent: currentTier == tier,
          recommended: recommended,
          palette: palette,
        );

    // Se ITERA sobre el enum a proposito. Antes las tres tarjetas estaban
    // escritas a mano (free, plan1, plan2), asi que agregar un tier al enum
    // NO lo hacia aparecer aca: el compilador exige exhaustividad en los
    // switch, pero no dice nada de una lista literal. Plan 3 se agrego y la
    // pricing page siguio mostrando tres planes, en silencio.
    const recommended = SubscriptionTier.plan1;
    final cards = {
      for (final tier in SubscriptionTier.values)
        tier: card(tier, recommended: tier == recommended),
    };

    // El ancho por tarjeta lo fija el precio-heroe (Barlow Condensed grande).
    // Con cuatro planes ya no entran en una fila salvo en pantallas anchas:
    // a ~1165px utiles se pasaba 55px. Por eso hay tres layouts y no dos.
    const tiers = SubscriptionTier.values;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;

        if (w < 820) {
          // Apilado: la recomendada primero (mas visible en mobile).
          final ordered = [
            recommended,
            ...tiers.where((t) => t != recommended),
          ];
          return Column(
            children: [
              for (var i = 0; i < ordered.length; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                cards[ordered[i]]!,
              ],
            ],
          );
        }

        // Grilla 2x2 para todo lo ancho. NO hay variante de cuatro en fila:
        // el ancho por tarjeta lo fija el precio-heroe (Barlow Condensed
        // grande) y pide ~360px, o sea que cuatro necesitarian ~1500px utiles.
        // Achicar el precio para que entren seria sacrificar justo lo que la
        // tarjeta tiene para decir.
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
      },
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
      // Condensed, y obligaba a interpretar en vez de leer.
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
          // Precio-héroe: "$" chico arriba a la izquierda del número gigante.
          Row(
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
                ),
              ),
            ],
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
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            decoration: BoxDecoration(
              color: palette.accent,
              borderRadius: BorderRadius.circular(9999),
            ),
            child: Text(
              'MÁS POPULAR', // i18n: Fase W3
              style: GoogleFonts.barlowCondensed(
                color: palette.bg,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PlanCtaButton extends StatelessWidget {
  const _PlanCtaButton({
    required this.isCurrent,
    required this.recommended,
    required this.isFree,
    required this.palette,
  });

  final bool isCurrent;
  final bool recommended;
  final bool isFree;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    if (isCurrent) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(9999),
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
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? palette.accent : Colors.transparent,
            border: Border.all(
              color: filled ? palette.accent : palette.border,
            ),
            borderRadius: BorderRadius.circular(9999),
          ),
          child: Text(
            isFree ? 'GRATIS' : 'ELEGIR PLAN', // i18n: Fase W3
            style: GoogleFonts.barlowCondensed(
              color: filled ? palette.bg : palette.textPrimary,
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
