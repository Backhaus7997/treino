import 'package:flutter/material.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../../core/widgets/treino_icon.dart';
import '../../../../coach/domain/subscription_tier.dart';
import '../../widgets/treino_interactive_state.dart';
import 'plan_copy.dart';

/// Piezas visuales COMPARTIDAS por los tres avisos de tope del PF: el
/// paywall de alumnos (`plan_limit_paywall.dart`, este mismo directorio) y
/// el aviso de ejercicios propios / plantillas (`trainer_limit_notice.dart`,
/// en `coach/presentation/widgets/`).
///
/// Nacieron acá porque el dueño pidió que los tres se vean EXACTAMENTE
/// igual — no "parecido": envoltura sheet/dialog, encabezado con candado,
/// caja de upsell, CTA "VER PLANES" y "Ahora no" son la MISMA pieza en los
/// tres lugares. Un cambio de copy, ícono o spacing en una pieza cambia
/// automáticamente en las tres superficies; antes había DOS archivos que
/// dibujaban lo mismo con dos implementaciones (dumbbell vs. candado,
/// `OutlinedButton` vs. link de texto) que sólo coincidían por casualidad.
///
/// Lo que queda AFUERA a propósito:
///
/// - La lógica de REGULARIZAR (switch sobre
///   [PlanCheckoutOnWebOnly]/[PlanCheckoutAvailable]) es exclusiva de la
///   suscripción del PF — ejercicios/plantillas no tienen un estado
///   "suscripción suspendida" propio — así que esa rama no sube acá.
/// - Las envolturas `PlanLimitDialogShell`/`PlanLimitSheetShell` siguen
///   viviendo en `plan_limit_paywall.dart`, sin moverse: son código viejo,
///   ya con su deuda de spacing/tipografía registrada en los scanners de
///   `test/app/theme/tokens/`, y un archivo NUEVO no hereda esa allowlist
///   (AGENTS.md §2) — moverlas acá las hubiera obligado a re-tunear pixels
///   que nadie pidió tocar. Lo nuevo de este archivo (candado, cajas, CTA)
///   sí nace limpio: tokens desde el primer renglón.

/// Candado + título. El encabezado de los tres avisos — antes el de
/// ejercicios/plantillas usaba una pesa (`TreinoIcon.dumbbell`); ahora los
/// tres usan el mismo candado que el aviso de alumnos.
class PlanLimitHeader extends StatelessWidget {
  const PlanLimitHeader(
      {super.key, required this.title, required this.palette});

  final String title;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 58,
              height: 58,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.08),
                border:
                    Border.all(color: palette.accent.withValues(alpha: 0.33)),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(TreinoIcon.lock, size: 28, color: palette.accent),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppFonts.barlowCondensed,
              color: palette.textPrimary,
              fontSize: AppTextSize.heading,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      );
}

/// Caja de upsell al siguiente tier: nombre + precio-héroe + el beneficio
/// del tope que el PF acaba de chocar.
///
/// [beneficio] lo arma cada llamador con el texto de SU tope (alumnos,
/// ejercicios propios o plantillas) — esta caja no sabe de "kinds", sólo de
/// plata y de un renglón de texto. Mismo motivo que `plan_copy.dart`:
/// `nextTier` puede ser un tier ilimitado y el texto de beneficio tiene que
/// resolverlo ANTES de llegar acá, nunca interpolando un `null`.
///
/// [sellCta] — decisión del dueño del 2026-09-29: mismo estilo visual en las
/// tres superficies, pero el encabezado sólo dice "PASATE A X" (llamado a
/// comprar) cuando `sellCta` es `true` — la WEB, que sí vende. En el MÓVIL
/// (`sellCta: false`) dice sólo "X": el precio y el beneficio siguen siendo
/// información (misma lógica que la pantalla de planes del móvil, que
/// tampoco vende), pero la Guideline 3.1.3(f) prohíbe el llamado a comprar
/// desde ADENTRO del binario. Guard: `avisos_de_tope_movil_sin_llamado_a_
/// comprar_test.dart`.
///
/// [porMes] — el sufijo del precio («/mes»), con su barra. Lo pasa cada
/// llamador y NO se lee de acá adentro: la forma MÓVIL sale de AppL10n
/// (hallazgo Codex, PR #1266: con la app en inglés la tarjeta decía «/mes» al
/// lado de un beneficio en inglés) y la WEB sigue con el string hardcodeado
/// de siempre (`i18n: Fase W3`). Requerido y sin default a propósito, mismo
/// motivo que [beneficio]: que el compilador obligue a cada llamador nuevo a
/// elegir una fuente, en vez de heredar castellano en silencio.
class PlanLimitUpsellBox extends StatelessWidget {
  const PlanLimitUpsellBox({
    super.key,
    required this.nextTier,
    required this.beneficio,
    required this.porMes,
    required this.palette,
    required this.sellCta,
  });

  final SubscriptionTier nextTier;
  final String beneficio;
  final String porMes;
  final AppPalette palette;
  final bool sellCta;

  @override
  Widget build(BuildContext context) {
    final price = kTierPricesArs[nextTier]!;
    final nombre = tierName(nextTier).toUpperCase();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.bg,
        border: Border.all(color: palette.accent),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        children: [
          Text(
            sellCta ? 'PASATE A $nombre' : nombre, // i18n: Fase W3
            style: TextStyle(
              fontFamily: AppFonts.barlowCondensed,
              color: palette.accent,
              fontSize: AppTextSize.body,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          // Precio-héroe. El Row no lleva `Flexible` y con textScale alto se
          // pasa del ancho de la caja: `scaleDown` lo achica en vez de
          // recortarlo — un precio cortado («39.0…») MIENTE, uno más chico
          // sigue siendo cierto.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.hairline,
                    right: AppSpacing.hairline,
                  ),
                  child: Text(
                    '\$',
                    style: TextStyle(
                      fontFamily: AppFonts.barlowCondensed,
                      color: palette.textPrimary,
                      fontSize: AppTextSize.titleLarge,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  _formatArs(price.monthly),
                  style: TextStyle(
                    fontFamily: AppFonts.barlowCondensed,
                    color: palette.textPrimary,
                    fontSize: AppTextSize.displayLarge,
                    fontWeight: FontWeight.w800,
                    height: 1.0,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    top: AppSpacing.s18,
                    left: AppSpacing.hairline,
                  ),
                  child: Text(
                    porMes,
                    style: TextStyle(
                        color: palette.textMuted,
                        fontSize: AppTextSize.bodyDense),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.hairline),
          Text(
            beneficio,
            style: TextStyle(
              color: palette.textMuted,
              fontSize: AppTextSize.bodyDense,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Caja para cuando no hay siguiente tier (el PF ya está en el más caro).
///
/// [body] lo decide cada llamador — alumnos, ejercicios propios y
/// plantillas dicen cosas distintas acá ("para más de 15 alumnos" no tiene
/// sentido en ejercicios propios).
///
/// [title] («PLAN A MEDIDA») dice lo mismo en los tres avisos, pero tampoco se
/// lee de acá adentro: la forma MÓVIL lo saca de AppL10n y la WEB lo pasa
/// hardcodeado (`i18n: Fase W3`) — mismo criterio que
/// [PlanLimitUpsellBox.porMes]. Esta caja es una red que en producción no se
/// alcanza (el servidor nunca bloquea a un PF sin tope), pero un texto que
/// PUEDE renderizarse no puede quedar en castellano dentro de la forma en
/// inglés.
class PlanLimitCustomTierBox extends StatelessWidget {
  const PlanLimitCustomTierBox({
    super.key,
    required this.title,
    required this.body,
    required this.palette,
  });

  final String title;
  final String body;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: palette.bg,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                fontFamily: AppFonts.barlowCondensed,
                color: palette.textPrimary,
                fontSize: AppTextSize.body,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: AppSpacing.hairline),
            Text(
              body,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: palette.textMuted, fontSize: AppTextSize.bodyDense),
            ),
          ],
        ),
      );
}

/// El botón principal (pill, fondo accent) de los tres avisos: "VER
/// PLANES", "REGULARIZAR", "CONTACTANOS". El estilo es UNO solo; lo que
/// cambia entre llamadores es el label y el `onTap`.
///
/// Va sobre [TreinoInteractiveState] (el primitivo de foco/hover/teclado del
/// kit Coach Hub Web — el mismo que usa `TreinoButton`) y NO sobre
/// `TreinoTappable` pelado: `TreinoTappable` es sólo un `GestureDetector`,
/// sin `FocusNode` ni `Actions` — invisible para Tab y para Enter/Espacio.
/// En el dialog WEB del Coach Hub, quien navega sólo con teclado no podía
/// llegar a este botón (hallazgo de Codex, 2026-09-29). `TreinoInteractiveState`
/// envuelve `TreinoTappable` puertas adentro, así que la animación de
/// presión (`AnimatedScale` a 0.97) se conserva sin costo — no hace falta
/// elegir entre foco y feedback de presión.
class PlanLimitAccentButton extends StatelessWidget {
  const PlanLimitAccentButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final focus = TreinoFocusTokens.of(context);

    return TreinoInteractiveState(
      onTap: onTap,
      builder: (ctx, states) => Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.accent,
          borderRadius: BorderRadius.circular(AppRadius.full),
          // Mismo anillo que `TreinoButton` (`TreinoFocusTokens`): visible
          // SÓLO con foco de teclado, nunca con hover/tap de mouse.
          boxShadow: states.focused
              ? [
                  BoxShadow(
                    color: focus.ring.withValues(alpha: 0.5),
                    spreadRadius: TreinoFocusTokens.ringWidth,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppFonts.barlowCondensed,
            color: TreinoButtonTokens.foreground(context),
            fontSize: AppTextSize.body,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}

/// El link de descarte ("Ahora no") de los tres avisos.
///
/// Mismo motivo que [PlanLimitAccentButton]: [TreinoInteractiveState] en vez
/// de `TreinoTappable` pelado, para que Tab lo alcance y Enter/Espacio lo
/// activen.
class PlanLimitDismissLink extends StatelessWidget {
  const PlanLimitDismissLink({
    super.key,
    this.label = 'Ahora no', // i18n: Fase W3
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final focus = TreinoFocusTokens.of(context);

    return TreinoInteractiveState(
      onTap: onTap,
      builder: (ctx, states) => Container(
        // `s8` y no `hairline`: a diferencia de los gaps ópticos de arriba,
        // esto es el padding vertical del área tappable — un link de
        // descarte con menos de 8px de aire es un blanco de toque incómodo.
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          boxShadow: states.focused
              ? [
                  BoxShadow(
                    color: focus.ring.withValues(alpha: 0.5),
                    spreadRadius: TreinoFocusTokens.ringWidth,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: palette.textMuted, fontSize: AppTextSize.bodyDense),
        ),
      ),
    );
  }
}

String _formatArs(int amount) {
  final s = amount.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return buf.toString();
}
