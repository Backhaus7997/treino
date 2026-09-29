import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

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
/// Dos estados:
/// - **En el tope** (`count == limit`): "tu plan incluye N" con la caja de
///   upsell al siguiente tier. En WEB suma "para sumar más, subí de plan";
///   en MÓVIL no (Guideline 3.1.3(f) — decisión del dueño, 2026-09-29), y en
///   su lugar dice qué puede hacer el PF con lo que ya tiene.
/// - **Por encima** (`count > limit`, bajaste de plan): el texto de
///   conservación — "conservás todos, para crear uno nuevo
///   [borrá/archivá] N", con `N = count - limit + 1` — sin caja de upsell:
///   acá el problema no es elegir un plan, es que ya bajó de uno. Igual en
///   las dos superficies: no nombra un tier, así que 3.1.3(f) no lo alcanza.
Future<void> showTrainerLimitNotice(
  BuildContext context, {
  required TrainerLimitKind kind,
  required SubscriptionTier currentTier,
  required int limit,
  required int count,
}) {
  final form = _resolveForm();
  final content = _TrainerLimitContent(
    kind: kind,
    currentTier: currentTier,
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
    required this.overLimit,
    required this.limit,
    required this.count,
    required this.toFree,
    required this.isWeb,
  });

  final TrainerLimitKind kind;
  final SubscriptionTier currentTier;
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
    final nounLimite = limit == 1
        ? switch (kind) {
            TrainerLimitKind.customExercises => 'ejercicio propio',
            TrainerLimitKind.templates => 'plantilla',
          }
        : noun;
    final body = overLimit
        ? 'Tenés $count $noun y tu plan incluye $limit. '
            'Conservás $todos; para crear $unoNuevo, $verb $toFree.' // i18n: Fase W3
        : isWeb
            ? 'Tu plan ${tierName(currentTier)} incluye $limit $nounLimite. '
                'Para sumar más, subí de plan.' // i18n: Fase W3
            // Móvil, decisión del dueño 2026-09-29: sin "para sumar más,
            // subí de plan" (3.1.3(f)) — en su lugar, lo que el PF puede
            // hacer con lo que ya tiene. Guard:
            // `avisos_de_tope_movil_sin_llamado_a_comprar_test.dart`.
            : 'Tu plan ${tierName(currentTier)} incluye $limit $nounLimite. '
                'Podés $accionConservar.'; // i18n: Fase W3

    final next = currentTier.nextTier;

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
        // Sólo "en el tope" ofrece la caja de upsell: "pasado de tope" ya es
        // un problema de conservación, no de elegir un plan nuevo.
        if (!overLimit) ...[
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
