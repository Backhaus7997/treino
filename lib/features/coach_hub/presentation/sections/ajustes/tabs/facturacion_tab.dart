import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/widgets/motion/treino_tappable.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/application/custom_exercise_quota_provider.dart';
import 'package:treino/features/coach/application/template_quota_provider.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach/domain/weighted_load.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/cancel_subscription_dialog.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/plan_cancel.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/plan_upsell_banner.dart';
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
        // ── La baja ──
        //
        // Sólo con un plan PAGO: un PF en Free no tiene nada que dar de baja, y
        // ofrecérselo le haría creer que sí. El servidor devuelve
        // `sin-suscripcion` igual —un botón que no se dibuja no es una
        // garantía— pero acá no hay por qué mostrarlo.
        //
        // Fuera de la card y no adentro, a propósito: la card dice lo que el PF
        // TIENE, y esto es una acción destructiva. Meterla ahí la pondría al
        // lado de «CAMBIAR PLAN», que es lo contrario de lo que hace.
        if (tier != SubscriptionTier.free) ...[
          const SizedBox(height: AppSpacing.s14),
          _CancelSubscriptionLink(palette: palette),
        ],
      ],
    );
  }
}

class _CurrentPlanCard extends StatelessWidget {
  const _CurrentPlanCard({
    required this.tier,
    required this.load,
    required this.limit,
    required this.palette,
  });

  final SubscriptionTier tier;
  final double load;

  /// `null` = sin límite (plan3).
  final int? limit;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    // Fracción para la barra, tope en 1.0 aunque esté sobre el límite.
    // Sin límite: la barra queda vacía y nunca hay excedente. Mostrar una
    // barra llena al 100% sugeriría que estás al tope, que es lo contrario.
    final lim = limit;
    final fraction =
        lim == null || lim == 0 ? 0.0 : (load / lim).clamp(0.0, 1.0);
    final overLimit = lim != null && load > lim;

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
                      'TREINO Coach · ${tierLabel(tier)}', // i18n: Fase W3
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
              // Decia que este boton llegaba «en PR3» y que se mostraba
              // «deshabilitado para no prometer una pantalla que no existe».
              // Las dos cosas son falsas desde PR3: el boton esta vivo y
              // navega, y `/facturacion/planes` existe.
              //
              // NO cablear el checkout aca. Este boton NAVEGA a la pricing
              // page y nada mas; el unico punto de cobro de la app es
              // `PlanCheckoutAvailable.start` (ver `plan_checkout.dart`).
              // Meterlo aca daria DOS puntos de compra que se desincronizan:
              // este no sabe si el PF eligio mensual o anual.
              _ChangePlanButton(palette: palette),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                lim == null
                    // Contador sin techo: "N / sin límite" en vez de un
                    // simbolo. Mismo criterio que la pricing page.
                    ? '${formatWeightedLoad(load)} / sin límite' // i18n: Fase W3
                    : '${formatWeightedLoad(load)} / $lim',
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
          const SizedBox(height: AppSpacing.s8),
          _ExerciseUsageLine(palette: palette),
          // Plantillas: sólo cuando el TIER tiene tope de plantillas
          // (docs/limite-plantillas-pf.md §3 PR5). Se deriva de
          // `tier.templateLimit`, no de `tier == free` a mano: hoy sólo Free
          // tiene tope, pero si el producto le pone tope a otro plan el día
          // de mañana, este gate sigue correcto solo — el hardcodeo habría
          // quedado mudo justo en el plan nuevo.
          //
          // A diferencia de ejercicios propios, un plan SIN tope de
          // plantillas no vale la pena anunciar como "(sin límite)" acá, así
          // que la línea entera se omite en vez de mostrarla siempre.
          if (tier.templateLimit != null) ...[
            const SizedBox(height: AppSpacing.s8),
            _TemplateUsageLine(palette: palette),
          ],
        ],
      ),
    );
  }
}

/// «Ejercicios propios: 12 de 60» — línea de uso, calcada de la fila de
/// ALUMNOS de esta misma card. Lee `customExerciseUsageSummaryProvider`: el
/// tope y el contador del documento del PF, sin bajar la colección entera de
/// ejercicios sólo para contarla (ver el dartdoc del provider).
///
/// ⚠️ NO usa `tier.customExerciseLimit` (la tabla estática que sí consulta
/// `pricing_screen.dart` para vender el PLAN). Usa el tope REAL que devuelve
/// el servidor: hoy `TRAINER_EXERCISE_LIMITS_ENABLED` está apagado
/// (docs/limite-ejercicios-pf.md), así que `planLimits.customExercises` es
/// `null` para TODOS los planes — no sólo Plan 3. Si esta línea mostrara
/// «12 de 60» sacado de la tabla estática, afirmaría un tope que hoy no rige
/// para nadie.
///
/// `limit == null` entonces significa DOS cosas indistinguibles desde acá
/// (Plan 3 real, o el interruptor apagado) y las dos se muestran igual: «N
/// (sin límite)». Es la MISMA decisión que ya toma el bloque de ALUMNOS de
/// arriba con `lim == null` («$load / sin límite») — no se oculta la fila,
/// se dice la verdad que el servidor sí sabe hoy.
class _ExerciseUsageLine extends ConsumerWidget {
  const _ExerciseUsageLine({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quota = ref.watch(customExerciseUsageSummaryProvider).valueOrNull;

    // `AsyncLoading` (recién montado), `AsyncError`, o el contador todavía
    // ausente en el documento: no hay nada confirmado. No se inventa un
    // número — se oculta la línea entera, y reaparece sola cuando el
    // servidor escriba el conteo.
    if (quota == null) return const SizedBox.shrink();

    final text = quota.limit == null
        ? 'Ejercicios propios: ${quota.count} (sin límite)' // i18n: Fase W3
        : 'Ejercicios propios: ${quota.count} de ${quota.limit}'; // i18n: Fase W3

    return Text(
      text,
      style: TextStyle(color: palette.textMuted, fontSize: AppTextSize.caption),
    );
  }
}

/// «Plantillas: 2 de 3» — línea de uso, calcada de [_ExerciseUsageLine] y por
/// el mismo motivo (docs/limite-plantillas-pf.md §3 PR5). Lee
/// `templateUsageSummaryProvider`: el CONTADOR DENORMALIZADO que escribe la CF
/// de PR1, no el stream del gate de PR3 — ver el dartdoc de ese provider.
///
/// El caller sólo la monta cuando `tier.templateLimit != null` (hoy, sólo
/// Free): a diferencia de ejercicios propios, acá NO hay un caso "sin
/// límite" que valga la pena mostrar en un plan sin tope, así que la línea
/// entera se omite en vez de aparecer con un límite que nunca aplica.
class _TemplateUsageLine extends ConsumerWidget {
  const _TemplateUsageLine({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quota = ref.watch(templateUsageSummaryProvider).valueOrNull;

    // `AsyncLoading`, `AsyncError`, o el contador todavía ausente: no hay
    // nada confirmado. Se oculta la línea, igual que `_ExerciseUsageLine`.
    if (quota == null) return const SizedBox.shrink();

    final text = quota.limit == null
        ? 'Plantillas: ${quota.count} (sin límite)' // i18n: Fase W3
        : 'Plantillas: ${quota.count} de ${quota.limit}'; // i18n: Fase W3

    return Text(
      text,
      style: TextStyle(color: palette.textMuted, fontSize: AppTextSize.caption),
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
      child: TreinoTappable(
        onTap: () => context.push('/facturacion/planes'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: palette.accent),
            borderRadius: BorderRadius.circular(AppRadius.full),
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

/// El acceso a la baja.
///
/// Es un LINK discreto y no un botón con borde: a lo que el PF viene a
/// Facturación es a mirar su plan o a cambiarlo, y darle a la baja el mismo
/// peso visual que a «CAMBIAR PLAN» sería empujarla. Tampoco está escondida —
/// el art. 10 ter de la Ley 24.240 exige poder darse de baja por el mismo medio
/// en que se contrató, y algo que no se encuentra no cumple eso.
///
/// La norma que lo reglamenta es la **Disposición 954/2025** (art. 4), que
/// derogó la Res. 424/2020 que este comentario citaba. Y OJO: este link no es
/// el «BOTÓN DE BAJA DE SERVICIO» que esa disposición exige — ése tiene que
/// estar público en el pie de `gettreino.com`, alcanzable sin sesión iniciada.
/// Éste es el acceso para quien YA está adentro. Los dos hacen falta.
/// → `docs/legal/spec-web-legal.md` §3.5.
///
/// El texto dice «dar de baja» y no «cancelar suscripción»: es el término de
/// los Términos de Suscripción §7, y usar dos nombres para lo mismo obliga al
/// PF a adivinar si son la misma cosa.
class _CancelSubscriptionLink extends StatelessWidget {
  const _CancelSubscriptionLink({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    // En móvil el tipo sellado no expone `cancelar`, así que no hay nada que
    // ofrecer. Mismo criterio que `PlanCheckoutOnWebOnly`.
    if (resolvePlanCancel() is! PlanCancelAvailable) {
      return const SizedBox.shrink();
    }

    return Semantics(
      button: true,
      label: 'Dar de baja la suscripción', // i18n: Fase W3
      child: TreinoTappable(
        onTap: () => showCancelSubscriptionDialog(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
          child: Text(
            'Dar de baja la suscripción', // i18n: Fase W3
            style: TextStyle(
              // Token y no literal: este archivo está en la allowlist del guard
              // de `fontSize` crudo, pero su deuda NO puede crecer — código
              // nuevo usa la escala.
              fontSize: AppTextSize.caption,
              color: palette.textMuted,
              decoration: TextDecoration.underline,
              decorationColor: palette.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
