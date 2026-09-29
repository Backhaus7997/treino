import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/utils/app_clock.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../coach_hub/presentation/sections/facturacion_planes/plan_copy.dart';
// Las envolturas dialog/sheet ([PlanLimitDialogShell], [PlanLimitSheetShell])
// viven en `plan_limit_paywall.dart` y no en `plan_limit_shared.dart` — ver
// el dartdoc de ese archivo para el motivo (deuda de spacing ya registrada).
import '../../../coach_hub/presentation/sections/facturacion_planes/plan_limit_paywall.dart';
import '../../../coach_hub/presentation/sections/facturacion_planes/plan_limit_shared.dart';
import '../../domain/subscription_tier.dart';

/// Los topes del plan del PF que este aviso sabe mostrar
/// (docs/limite-ejercicios-pf.md y docs/limite-plantillas-pf.md, PR3).
///
/// Un solo widget para los dos avisos, generalizado por `kind`: son el mismo
/// layout diciendo lo mismo con otra palabra, y dos copias divergen
/// (docs/limite-plantillas-pf.md PR3, "El aviso"). Si se suma un tercer tope
/// de plan, entra acá con su propio caso — no con un tercer archivo.
enum TrainerLimitKind { customExercises, templates }

/// Resuelve, a partir del `limit` con el que YA bloqueó el gate —nunca del
/// tier nominal de `userProfileProvider` directo—, qué tier mostrar en el
/// aviso, y si corresponde decir que la suscripción no está activa.
///
/// ## Hallazgo P1 (Codex, 2026-09-29) — qué tier se NOMBRA
///
/// Los gates leían el tier NOMINAL (`subscription?.tier`) para el copy, pero
/// el [limit] que bloquea sale de `planLimits` del servidor, calculado con el
/// tier EFECTIVO — una suscripción `pending`/`paused`, o `cancelled` ya
/// vencida, cae a los topes de Free, y un piso prepago puede subir el
/// efectivo por ENCIMA del nominal. Nombrar el nominal ahí afirma un plan
/// que no explica el número que el PF tiene enfrente (AGENTS.md §11.1): un
/// Plan 1 pausado con 3 plantillas veía «Plan 1 incluye…» y el upsell le
/// ofrecía el Plan 2, cuando Plan 1 no tiene tope de plantillas — el efectivo
/// era Free. Se corrige resolviendo `efectivo` desde la TABLA
/// ([kTierCustomExerciseLimits] / [kTierTemplateLimits]), nunca desde
/// [nominalTier].
///
/// ## Segundo hallazgo (Codex, 2026-09-29) — CUÁNDO se afirma "inactiva"
///
/// La primera versión de este fix todavía decidía `inactive` COMPARANDO
/// límites (`efectivo.index < nominalTier.index`), no mirando el ESTADO real
/// de la suscripción. Eso miente en la ventana de propagación: cuando un
/// upgrade se confirma, `subscription` (tier/status) se escribe ANTES de que
/// `syncEntitlementsOnSubscription` (functions, asíncrono — y si falla NO
/// reintenta; sólo lo cura el barrido nocturno) termine de recalcular
/// `planLimits`. En ese intervalo un PF con Plan 1 YA ACTIVO todavía choca
/// con el límite de Free, y comparar límites decía «tu suscripción no está
/// activa» — falso: la suscripción SÍ está activa, sólo el número tarda en
/// llegar (AGENTS.md §11.1 — una advertencia falsa es peor que ninguna).
///
/// Ahora `inactive` sale del ESTADO, con las MISMAS reglas que
/// `limiteDelStatus` en `functions/src/subscriptions/effective-limit.ts`:
/// `active`/`grace` están al día; `pending`/`paused` no; `cancelled` depende
/// de si [now] todavía está antes de [currentPeriodEnd]. Ver
/// [_entitledToNominalTier].
///
/// Con el estado resuelto, tres casos posibles (en este orden de prioridad):
///
/// 1. **Piso prepago** — `efectivo` > [nominalTier]: es un PISO, nunca un
///    techo (mismo criterio que `conPisoPrepago` del servidor), así que se
///    nombra igual, esté la suscripción activa o no.
/// 2. **Inactiva por estado** — el estado dice que no está al día: `tier` es
///    el efectivo (típicamente Free) e `inactive` es `true`.
/// 3. **Activa pero el límite quedó atrás** — `efectivo` < [nominalTier] con
///    el estado al día: es propagación pendiente o un sync fallido, nunca un
///    hecho sobre la suscripción. No se nombra NINGÚN tier —ni el nominal,
///    que no explica el número, ni el efectivo, que contradice un estado
///    activo— y el llamador cae al cuerpo genérico («Tu plan incluye N…»,
///    sin upsell; ver `_TrainerLimitContent.build`).
///
/// Devuelve:
/// - `tier`: el tier a NOMBRAR. `null` = no afirmar ningún plan (tope
///   ajustado a mano sin match en la tabla, o el caso 3 de arriba) — el
///   llamador cae al cuerpo genérico.
/// - `inactive`: `true` sólo en el caso 2 de arriba. Nunca `true` con
///   `tier: null` — sin un tier verificable no hay nada que afirmar (mismo
///   criterio que `PlanLimitReason.subscriptionInactive` en
///   `plan_limit_paywall.dart`, que tampoco se afirma sin dato).
({SubscriptionTier? tier, bool inactive}) resolveNoticeTier({
  required TrainerLimitKind kind,
  required int limit,
  required SubscriptionTier nominalTier,
  required SubscriptionStatus subscriptionStatus,
  DateTime? currentPeriodEnd,
  DateTime? now,
}) {
  final table = switch (kind) {
    TrainerLimitKind.customExercises => kTierCustomExerciseLimits,
    TrainerLimitKind.templates => kTierTemplateLimits,
  };

  // Orden de declaración del enum (free < plan1 < plan2 < plan3): si algún
  // día dos tiers compartieran el mismo límite, esto se queda con el más
  // barato de los dos — la lectura más conservadora del dato.
  SubscriptionTier? efectivo;
  for (final tier in SubscriptionTier.values) {
    if (table[tier] == limit) {
      efectivo = tier;
      break;
    }
  }

  // Caso 1 — piso prepago, SIN mirar el estado: ver el punto 1 del dartdoc.
  if (efectivo != null && efectivo.index > nominalTier.index) {
    return (tier: efectivo, inactive: false);
  }

  final entitled = _entitledToNominalTier(
    status: subscriptionStatus,
    currentPeriodEnd: currentPeriodEnd,
    now: now ?? AppClock.now(),
  );

  // Caso 2 — el ESTADO dice que no está al día. Nunca `inactive: true` sin
  // un tier resuelto (contrato del dartdoc de arriba): si ni el efectivo
  // matchea una tabla conocida, no hay nada verificable que afirmar.
  if (!entitled) return (tier: efectivo, inactive: efectivo != null);

  // Caso 3 — activa (o cancelled todavía vigente) pero el límite del
  // servidor quedó atrás del nominal: ver el punto 3 del dartdoc.
  if (efectivo != null && efectivo.index < nominalTier.index) {
    return (tier: null, inactive: false);
  }

  return (tier: efectivo, inactive: false);
}

/// Espeja `limiteDelStatus` de `functions/src/subscriptions/
/// effective-limit.ts`: `true` cuando el ESTADO de la suscripción respeta el
/// tier nominal (activa, en gracia, o cancelada todavía dentro del período
/// pagado); `false` cuando el servidor ya la trató como caída a Free por el
/// ESTADO — sin mirar ningún límite. `grace` cuenta como activa a propósito:
/// MP reintenta un cobro fallido 7 días antes de cortar, y no se castiga el
/// primer fallo (mismo comentario en el TS).
bool _entitledToNominalTier({
  required SubscriptionStatus status,
  required DateTime? currentPeriodEnd,
  required DateTime now,
}) =>
    switch (status) {
      SubscriptionStatus.active || SubscriptionStatus.grace => true,
      SubscriptionStatus.pending || SubscriptionStatus.paused => false,
      // Sin `currentPeriodEnd` no hay período pagado que respetar — mismo
      // caso límite que `limiteDelStatus` resuelve a Free.
      SubscriptionStatus.cancelled =>
        currentPeriodEnd != null && now.isBefore(currentPeriodEnd),
    };

/// El aviso que el embudo de cada tope muestra cuando el PF lo choca
/// (docs/limite-ejercicios-pf.md PR3 y docs/limite-plantillas-pf.md PR3,
/// "Los avisos").
///
/// **Mismo estilo que [showPlanLimitPaywall]** (`plan_limit_paywall.dart`,
/// el paywall de alumnos) — candado, título, caja de upsell con precio y
/// beneficio, "VER PLANES" y "Ahora no". Antes este aviso tenía su propio
/// look (pesa en vez de candado, `OutlinedButton` en vez del link de
/// descarte): el dueño pidió unificar los tres, así que las piezas viven en
/// `plan_limit_shared.dart` y este archivo sólo decide QUÉ texto va en cada
/// una.
///
/// **Móvil: sheet.** El botón dice VER PLANES y navega a
/// `/facturacion/planes` — la MISMA pantalla informativa de precios y cupos
/// que ya viaja en el binario móvil sin vender (precedente:
/// `showPlanLimitPaywall`, #1141). Lo que sigue prohibido, bajo la Guideline
/// 3.1.3(f), es nombrar DÓNDE se paga —"web", "mail", "pasá a un plan",
/// Mercado Pago— o cualquier botón que compre: eso es lo que arriesga la
/// exención del ENTRENADOR (mismo criterio que `plan_limit_paywall.dart`).
/// Lo cuidan `anti_steering_movil_test.dart` y
/// `superficie_de_cobro_alumno_test.dart` — si alguno se pone rojo por este
/// archivo, se cambia el TEXTO acá, nunca el guard.
///
/// **Web: dialog**, mismo CTA. La web sí vende (E8 — 3.1.3(f) sólo ampara al
/// binario móvil); el destino es el mismo en las dos superficies, sólo
/// cambia la envoltura.
enum TrainerLimitNoticeForm { sheet, dialog }

/// Fuerza la forma del aviso. SÓLO para tests — mismo seam que
/// `debugPlanLimitPaywallForm` en `plan_limit_paywall.dart`, y por el mismo
/// motivo: `kIsWeb` es una constante de compilación que bajo `flutter test`
/// vale `false` siempre, así que sin este seam la rama [dialog] quedaría sin
/// cobertura.
@visibleForTesting
TrainerLimitNoticeForm? debugTrainerLimitNoticeForm;

TrainerLimitNoticeForm _resolveForm() =>
    debugTrainerLimitNoticeForm ??
    (kIsWeb ? TrainerLimitNoticeForm.dialog : TrainerLimitNoticeForm.sheet);

/// Muestra el aviso de [kind]. [limit] y [count] son los que ya resolvió el
/// provider de cuota de ese tope (`customExerciseQuotaProvider` /
/// `templateQuotaProvider`) — acá no se vuelve a mirar la cuota, sólo se
/// decide qué texto mostrar. [currentTier] es el plan vigente del PF —lo
/// resuelve el gate desde `userProfileProvider`, igual que
/// `pricing_screen.dart`— y sólo se usa para el copy "en el tope" y para
/// resolver el upsell al siguiente tier; nunca para decidir si bloquea (eso
/// ya lo decidió el gate con `limit`/`count`).
///
/// [subscriptionStatus] y [currentPeriodEnd] vienen del MISMO
/// `TrainerSubscription` que [currentTier] (`userProfileProvider`; sin
/// `subscription` — el PF nunca pagó — el gate pasa `active`, porque no hay
/// nada "inactivo" que decir de un PF Free). Son los que deciden si el aviso
/// puede afirmar "tu suscripción no está activa" — ver [resolveNoticeTier].
/// REQUERIDO y no con default acá adentro a propósito: que el compilador
/// obligue a cada llamador a pensarlo, en vez de que un default silencioso
/// vuelva a esconder el mismo bug bajo otra forma.
///
/// El tier que NOMBRA el aviso nunca es [currentTier] a ciegas: se resuelve
/// desde [limit] (ver [resolveNoticeTier]), porque el nominal puede no
/// coincidir con el efectivo (suscripción no activa, propagación de
/// entitlements pendiente, o piso prepago).
///
/// Cuatro estados:
/// - **En el tope**, tier efectivo == nominal (el caso normal): "tu plan
///   incluye N" con la caja de upsell al siguiente tier. En WEB suma "para
///   sumar más, subí de plan"; en MÓVIL no (Guideline 3.1.3(f) — decisión
///   del dueño, 2026-09-29), y en su lugar dice qué puede hacer el PF con lo
///   que ya tiene.
/// - **En el tope, con la suscripción no activa** ([subscriptionStatus]
///   `pending`/`paused`, o `cancelled` ya vencida): nombra el plan pagado Y
///   el límite efectivo, sin caja de upsell — no se le ofrece "el
///   siguiente" a quien ya pagó uno más caro (mismo criterio que
///   `PlanLimitReason.subscriptionInactive` del paywall de alumnos).
/// - **En el tope, suscripción activa pero el límite quedó atrás** (tier
///   efectivo < nominal CON [subscriptionStatus] al día): propagación de
///   entitlements pendiente o un sync fallido, nunca un problema de la
///   suscripción — cuerpo genérico sin nombrar ningún plan y sin caja de
///   upsell (AGENTS.md §11.1: no se afirma lo que no se sabe).
/// - **Por encima** (`count > limit`, bajaste de plan): el texto de
///   conservación — "conservás todos, para crear uno nuevo
///   [borrá/archivá] N", con `N = count - limit + 1` — sin caja de upsell:
///   acá el problema no es elegir un plan, es que ya bajó de uno. Igual en
///   las dos superficies: no nombra un tier, así que 3.1.3(f) no lo alcanza.
Future<void> showTrainerLimitNotice(
  BuildContext context, {
  required TrainerLimitKind kind,
  required SubscriptionTier currentTier,
  required SubscriptionStatus subscriptionStatus,
  DateTime? currentPeriodEnd,
  required int limit,
  required int count,
}) {
  final form = _resolveForm();
  final content = _TrainerLimitContent(
    kind: kind,
    currentTier: currentTier,
    subscriptionStatus: subscriptionStatus,
    currentPeriodEnd: currentPeriodEnd,
    overLimit: count > limit,
    limit: limit,
    count: count,
    toFree: count - limit + 1,
    // Mismo booleano que decide sheet-vs-dialog: desde el 2026-09-29 el
    // COPY también depende de la superficie (3.1.3(f) — ver el dartdoc de
    // `showPlanLimitPaywall`, mismo criterio acá).
    isWeb: form == TrainerLimitNoticeForm.dialog,
  );

  if (form == TrainerLimitNoticeForm.dialog) {
    return showDialog<void>(
      context: context,
      builder: (_) => PlanLimitDialogShell(content: content),
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    // Mismo motivo que `plan_limit_paywall.dart`: en la app móvil el shell
    // vive DENTRO del `Scaffold.body`, así que sin `useRootNavigator: true`
    // el sheet queda recortado y la bottom bar flota encima.
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (_) => PlanLimitSheetShell(content: content),
  );
}

/// Contenido del aviso — EL MISMO en las dos envolturas (sheet/dialog) y en
/// los dos `kind`, mismo criterio que `_PlanLimitPaywallContent` en
/// `plan_limit_paywall.dart`: un solo lugar decide QUÉ dice, las envolturas
/// deciden CÓMO entra a la pantalla.
class _TrainerLimitContent extends StatelessWidget {
  const _TrainerLimitContent({
    required this.kind,
    required this.currentTier,
    required this.subscriptionStatus,
    this.currentPeriodEnd,
    required this.overLimit,
    required this.limit,
    required this.count,
    required this.toFree,
    required this.isWeb,
  });

  final TrainerLimitKind kind;
  final SubscriptionTier currentTier;
  final SubscriptionStatus subscriptionStatus;
  final DateTime? currentPeriodEnd;
  final bool overLimit;
  final int limit;
  final int count;
  final int toFree;

  /// `true` = superficie WEB (Coach Hub), que sí vende. `false` = MÓVIL, que
  /// sólo informa (Guideline 3.1.3(f) — ver el dartdoc de
  /// [showPlanLimitPaywall] en `plan_limit_paywall.dart`, mismo criterio
  /// acá). Decisión del dueño, 2026-09-29.
  final bool isWeb;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final title = switch (kind) {
      TrainerLimitKind.customExercises =>
        'TOPE DE EJERCICIOS PROPIOS', // i18n: Fase W3
      TrainerLimitKind.templates => 'TOPE DE PLANTILLAS', // i18n: Fase W3
    };

    // "Uno nuevo/todos" (ejercicios, masculino) vs. "una nueva/todas"
    // (plantillas, femenino) — el género del sustantivo cambia con el kind.
    final noun = switch (kind) {
      TrainerLimitKind.customExercises => 'ejercicios propios',
      TrainerLimitKind.templates => 'plantillas',
    };
    final unoNuevo = switch (kind) {
      TrainerLimitKind.customExercises => 'uno nuevo',
      TrainerLimitKind.templates => 'una nueva',
    };
    final todos = switch (kind) {
      TrainerLimitKind.customExercises => 'todos',
      TrainerLimitKind.templates => 'todas',
    };
    final verb = switch (kind) {
      TrainerLimitKind.customExercises => 'borrá',
      TrainerLimitKind.templates => 'archivá',
    };
    // Móvil, "en el tope" (Cambio 1 del 2026-09-29): reemplaza al CTA de
    // venta por una reafirmación de lo que el PF YA puede hacer con lo que
    // tiene — mismo tono que el texto de conservación de "pasado de tope".
    final accionConservar = switch (kind) {
      TrainerLimitKind.customExercises => 'editar o borrar los que ya tenés',
      TrainerLimitKind.templates => 'editar o archivar las que ya tenés',
    };

    // El tier a NOMBRAR nunca es el nominal a ciegas: se resuelve desde
    // [limit] — el mismo número con el que bloqueó el gate — porque una
    // suscripción no activa puede haber hecho caer el efectivo por debajo
    // del nominal (o un piso prepago, subirlo por encima). Ver el dartdoc de
    // [resolveNoticeTier].
    final resolved = resolveNoticeTier(
      kind: kind,
      limit: limit,
      nominalTier: currentTier,
      subscriptionStatus: subscriptionStatus,
      currentPeriodEnd: currentPeriodEnd,
    );
    final effectiveTier = resolved.tier;
    final inactive = resolved.inactive;

    // "En el tope": mismo tono que `_PlanLimitPaywallContent` — "tu plan
    // incluye X". El número es [limit], el MISMO que usó el gate para
    // bloquear (`planLimits` del servidor), y NO la tabla estática del tier:
    // si difieren (el piso prepago sube el plan efectivo, o un tope ajustado
    // a mano), el aviso diría un tope que no es el que está frenando al PF.
    // En este aviso [limit] nunca es null: sin tope no hay aviso.
    //
    // "Pasado de tope": el texto de conservación que ya tenía este aviso
    // (docs/limite-ejercicios-pf.md y docs/limite-plantillas-pf.md, PR3, "Los
    // avisos") — sin caja de upsell, adaptado sólo al encabezado/CTA nuevos.
    // No nombra tier, así que el nominal/efectivo no lo afecta.
    final nounLimite = limit == 1
        ? switch (kind) {
            TrainerLimitKind.customExercises => 'ejercicio propio',
            TrainerLimitKind.templates => 'plantilla',
          }
        : noun;
    // Sin tier resuelto (tope ajustado a mano) no se afirma un nombre de
    // plan — AGENTS.md §11.1: lo que no se puede verificar, no se dice.
    final tierPrefix = effectiveTier == null
        ? 'Tu plan'
        : 'Tu plan ${tierName(effectiveTier)}';
    final body = overLimit
        ? 'Tenés $count $noun y tu plan incluye $limit. '
            'Conservás $todos; para crear $unoNuevo, $verb $toFree.' // i18n: Fase W3
        : inactive
            // El [inactive] de `resolveNoticeTier` sólo es `true` con
            // `effectiveTier` resuelto — el `!` es seguro por contrato.
            ? 'Tu suscripción a ${tierName(currentTier)} no está activa. '
                'Mientras tanto, tu plan ${tierName(effectiveTier!)} '
                'incluye $limit $nounLimite.' // i18n: Fase W3
            : isWeb
                ? '$tierPrefix incluye $limit $nounLimite. Para sumar más, '
                    'subí de plan.' // i18n: Fase W3
                // Móvil, decisión del dueño 2026-09-29: sin "para sumar más,
                // subí de plan" (3.1.3(f)) — en su lugar, lo que el PF puede
                // hacer con lo que ya tiene. Guard:
                // `avisos_de_tope_movil_sin_llamado_a_comprar_test.dart`.
                : '$tierPrefix incluye $limit $nounLimite. Podés '
                    '$accionConservar.'; // i18n: Fase W3

    // Sin upsell cuando: ya está sobre el tope (conservación, no venta);
    // está `inactive` (ofrecerle "el siguiente" a quien ya pagó uno más caro
    // es el mensaje equivocado — mismo criterio que
    // `PlanLimitReason.subscriptionInactive`); o no se pudo resolver un tier
    // (no hay una base cierta desde la cual calcular "el siguiente").
    final showUpsell = !overLimit && !inactive && effectiveTier != null;
    // Sin `!`: el analyzer ya promueve `effectiveTier` a no-nulo acá, porque
    // `showUpsell` lo chequeó en la misma expresión un renglón arriba.
    final next = showUpsell ? effectiveTier.nextTier : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlanLimitHeader(title: title, palette: palette),
        const SizedBox(height: AppSpacing.s8),
        Text(
          body,
          textAlign: TextAlign.center,
          style:
              TextStyle(color: palette.textMuted, fontSize: AppTextSize.body),
        ),
        const SizedBox(height: AppSpacing.s18),
        // Upsell sólo cuando `showUpsell` — ver su dartdoc arriba: nunca
        // sobre el tope, nunca con la suscripción inactiva, nunca sin un
        // tier del que partir.
        if (showUpsell) ...[
          if (next != null)
            PlanLimitUpsellBox(
              nextTier: next,
              beneficio: switch (kind) {
                TrainerLimitKind.customExercises =>
                  next.customExerciseLimit == null
                      ? 'Ejercicios propios sin límite' // i18n: Fase W3
                      : 'Hasta ${next.customExerciseLimit} ejercicios '
                          'propios', // i18n: Fase W3
                TrainerLimitKind.templates => next.templateLimit == null
                    ? 'Plantillas sin límite' // i18n: Fase W3
                    : 'Hasta ${next.templateLimit} plantillas', // i18n: Fase W3
              },
              palette: palette,
              sellCta: isWeb,
            )
          else
            // En la práctica es inalcanzable: Plan 3 no tiene tope de
            // ejercicios propios ni de plantillas, así que el gate nunca
            // llega a chocarlo acá. Queda como red por si el tier cambia —
            // mismo criterio que el "PLAN A MEDIDA" de alumnos en
            // `plan_limit_paywall.dart`.
            PlanLimitCustomTierBox(
              body: 'Estás en el plan más grande. Estamos preparando un '
                  'plan a tu medida.', // i18n: Fase W3
              palette: palette,
            ),
          const SizedBox(height: AppSpacing.s18),
        ],
        PlanLimitAccentButton(
          key: const Key('trainer_limit_ver_planes'),
          label: 'VER PLANES', // i18n: Fase W3
          onTap: () {
            Navigator.of(context).pop();
            context.push('/facturacion/planes');
          },
        ),
        const SizedBox(height: AppSpacing.s12),
        PlanLimitDismissLink(
          key: const Key('trainer_limit_dismiss'),
          // Móvil: "Entendido" — "Ahora no" presupone una oferta que el
          // móvil ya no hace (decisión del dueño, 2026-09-29).
          label: isWeb ? 'Ahora no' : 'Entendido', // i18n: Fase W3
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
