import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../../l10n/app_l10n.dart';
import '../../../../coach/domain/subscription_tier.dart';
import 'plan_checkout.dart';
import 'plan_copy.dart';
import 'plan_limit_shared.dart';

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
  final form = _resolveForm();
  // Un solo contenido para las dos envolturas. Si mañana cambia el copy o el
  // CTA, cambia UNA vez: duplicarlo garantiza que tarde o temprano web y móvil
  // digan cosas distintas y nadie se entere hasta que lo reporte un usuario.
  //
  // `isWeb` viaja con el contenido, no sólo con la envoltura: desde la
  // decisión del dueño del 2026-09-29 el COPY también depende de la
  // superficie —el móvil no puede tener "calls to action for purchase
  // outside of the app" (Guideline 3.1.3(f))—, así que el mismo booleano que
  // elige sheet-vs-dialog ahora también elige "vende" vs "informa". Una sola
  // fuente de verdad, nunca dos `kIsWeb` sueltos que puedan desincronizarse.
  final content = _PlanLimitPaywallContent(
    currentTier: currentTier,
    reason: reason,
    subscriptionStatus: subscriptionStatus,
    billingRoute: billingRoute,
    isWeb: form == PlanLimitPaywallForm.dialog,
  );
  final barrierColor = Colors.black.withValues(alpha: 0.6);

  if (form == PlanLimitPaywallForm.dialog) {
    return showDialog<void>(
      context: context,
      barrierColor: barrierColor,
      builder: (_) => PlanLimitDialogShell(content: content),
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
    // El fondo real lo pinta `PlanLimitSheetShell` en su propio Container: es
    // la única forma de redondear SÓLO las esquinas de arriba sin que el
    // material del sheet dibuje su rectángulo debajo.
    backgroundColor: Colors.transparent,
    barrierColor: barrierColor,
    builder: (_) => PlanLimitSheetShell(content: content),
  );
}

/// Envoltura DIALOG — web/escritorio. Card centrada, ancho acotado, esquinas
/// todas redondeadas.
///
/// - [dialog] es la forma de WEB (Coach Hub): una app de escritorio con
///   sidebar y ventana ancha. Un panel que sube desde el borde inferior ahí
///   es un error de plataforma, no una decisión estética.
///
/// Pública y usada TAMBIÉN por `trainer_limit_notice.dart` (el aviso de
/// ejercicios propios y plantillas) — mismo estilo, misma implementación,
/// para que las tres envolturas nunca diverjan. Se queda en este archivo (no
/// en `plan_limit_shared.dart`) porque su padding ya tiene deuda de spacing
/// registrada en los scanners de `test/app/theme/tokens/`; moverla a un
/// archivo nuevo la hubiera obligado a re-tunear pixels que nadie pidió
/// tocar (AGENTS.md §2 — un archivo nuevo no hereda esa allowlist).
class PlanLimitDialogShell extends StatelessWidget {
  const PlanLimitDialogShell({super.key, required this.content});

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

/// Envoltura SHEET — móvil. Sube desde abajo, ancho completo, pegado al
/// borde inferior, redondeado sólo arriba, descartable deslizando. Es la
/// forma de MÓVIL: el pulgar llega al CTA y el gesto de descarte es el
/// nativo del sistema.
///
/// Misma nota que [PlanLimitDialogShell]: pública, compartida con
/// `trainer_limit_notice.dart`, y se queda en este archivo por su deuda de
/// spacing ya registrada.
class PlanLimitSheetShell extends StatelessWidget {
  const PlanLimitSheetShell({super.key, required this.content});

  final Widget content;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // Techo de altura: `isScrollControlled` habilita la pantalla entera, y
    // sin techo un contenido alto (textScale de accesibilidad) empuja el
    // sheet hasta desbordar. Con techo, el `SingleChildScrollView` de abajo
    // scrollea.
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
        // `bottom: true` — la barra de gestos no se come el CTA de abajo.
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
                // deslizando, no sólo con el CTA. 40x4 con `border` y radio 2
                // es la medida que ya usan los ~25 sheets del repo
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
/// Vive separado de [PlanLimitDialogShell] y [PlanLimitSheetShell] a
/// propósito: las envolturas deciden CÓMO entra a la pantalla, esto decide
/// QUÉ dice. Un cambio de copy toca un solo lugar.
class _PlanLimitPaywallContent extends StatelessWidget {
  const _PlanLimitPaywallContent({
    required this.currentTier,
    this.reason = PlanLimitReason.planLimit,
    this.subscriptionStatus,
    this.billingRoute,
    required this.isWeb,
  });

  final SubscriptionTier currentTier;
  final PlanLimitReason reason;
  final SubscriptionStatus? subscriptionStatus;

  /// Ruta a la vista de facturacion. NULL = esta superficie no tiene una (la
  /// app movil no tiene pantalla de facturacion), y entonces el CTA explica
  /// en vez de navegar a una ruta inexistente y morir.
  final String? billingRoute;

  /// `true` = superficie WEB (Coach Hub), que sí vende. `false` = MÓVIL, que
  /// sólo informa (Guideline 3.1.3(f) — ver el dartdoc de
  /// [showPlanLimitPaywall]). Decisión del dueño, 2026-09-29: mismo estilo
  /// visual en las dos, pero sin verbos de compra en el móvil.
  final bool isWeb;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isInactive = reason == PlanLimitReason.subscriptionInactive;
    // Una baja no es una suspensión: el PF la pidió. Decirle «suspendida» con
    // «Estado: cancelada» en la caja de abajo es contradecirse en el mismo
    // modal (Codex, #1314). Acá sólo se mira el status: que la baja ya haya
    // vencido (y por eso esté inactiva) lo decide quien abre el modal con
    // [PlanLimitReason.subscriptionInactive]. Los que abren el modal por un
    // rechazo del servidor no pasan status, y siguen con el título genérico.
    // El resto de la rama inactiva —cuerpo, caja, CTA— es el mismo.
    final dadaDeBaja =
        isInactive && subscriptionStatus == SubscriptionStatus.cancelled;
    // `reason` MANDA sobre el tier: un plan2 con la suscripción suspendida
    // necesita regularizar, no el aviso del plan a-medida del tope.
    final next = isInactive ? null : currentTier.nextTier;
    // Dos superficies, dos fuentes de texto (hallazgo Codex, PR #1266). La WEB
    // sigue con sus strings hardcodeados de siempre (`i18n: Fase W3`, sin
    // cambios) y el MÓVIL sale de AppL10n, con su traducción al inglés —
    // antes de este fix el aviso de ALUMNOS ni siquiera pasaba por AppL10n:
    // estaba en castellano hardcodeado en las dos superficies. Los `AppL10n`
    // sólo se resuelven en las ramas móviles (`AppL10n.of(context)` revienta
    // sin delegates; la web no los necesita, y sus tests tampoco).
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlanLimitHeader(
          title: _title(context, isInactive, dadaDeBaja: dadaDeBaja),
          palette: palette,
        ),
        const SizedBox(height: 8),
        Text(
          _body(context, isInactive),
          textAlign: TextAlign.center,
          style:
              TextStyle(color: palette.textMuted, fontSize: AppTextSize.body),
        ),
        const SizedBox(height: 22),
        if (isInactive)
          _ReactivateBox(
            currentTier: currentTier,
            status: subscriptionStatus,
            palette: palette,
            isWeb: isWeb,
          )
        else if (next != null)
          PlanLimitUpsellBox(
            nextTier: next,
            beneficio: _beneficio(context, next),
            porMes: isWeb
                ? '/mes' // i18n: Fase W3
                : AppL10n.of(context).planLimitPorMes,
            palette: palette,
            sellCta: isWeb,
          )
        else
          PlanLimitCustomTierBox(
            title: isWeb
                ? 'PLAN A MEDIDA' // i18n: Fase W3
                : AppL10n.of(context).planLimitPlanAMedidaTitulo,
            body: isWeb
                ? 'Estás en el plan más grande. Para más de 15 alumnos '
                    'estamos preparando un plan a tu medida.' // i18n: Fase W3
                : AppL10n.of(context).planLimitAlumnosPlanAMedidaCuerpo,
            palette: palette,
          ),
        const SizedBox(height: 20),
        // CTA principal.
        _PrimaryCta(
          hasNext: next != null,
          isInactive: isInactive,
          dadaDeBaja: dadaDeBaja,
          billingRoute: billingRoute,
          palette: palette,
          isWeb: isWeb,
        ),
        const SizedBox(height: 10),
        PlanLimitDismissLink(
          // Móvil: "Entendido" — "Ahora no" presupone una oferta que el
          // móvil ya no hace (decisión del dueño, 2026-09-29).
          label: isWeb
              ? 'Ahora no' // i18n: Fase W3
              : AppL10n.of(context).planLimitEntendido,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  /// Título del aviso.
  String _title(
    BuildContext context,
    bool isInactive, {
    required bool dadaDeBaja,
  }) {
    if (isWeb) {
      if (dadaDeBaja) {
        return 'TU SUSCRIPCIÓN ESTÁ DADA DE BAJA'; // i18n: Fase W3
      }
      return isInactive
          ? 'TU SUSCRIPCIÓN ESTÁ SUSPENDIDA' // i18n: Fase W3
          : 'LLEGASTE AL LÍMITE DE TU PLAN'; // i18n: Fase W3
    }
    final l10n = AppL10n.of(context);
    if (dadaDeBaja) return l10n.planLimitAlumnosTituloBaja;
    return isInactive
        ? l10n.planLimitAlumnosTituloInactiva
        : l10n.planLimitAlumnosTituloTope;
  }

  /// Cuerpo del aviso, en la superficie que corresponda.
  String _body(BuildContext context, bool isInactive) {
    if (isWeb) {
      if (isInactive) {
        // TODO(producto): copy placeholder — pendiente de revisión antes de
        // cerrar el PR (diseño D-2, riesgo residual 4).
        return 'Mientras tu suscripción no esté al día, tu cuenta '
            'funciona con el límite del plan Free. Ningún alumno '
            'se elimina.'; // i18n: Fase W3
      }
      return 'Tu plan ${tierName(currentTier)} incluye '
          '${cupoTexto(currentTier)}. Para sumar más, '
          'subí de plan.'; // i18n: Fase W3
    }
    final l10n = AppL10n.of(context);
    if (isInactive) return l10n.planLimitAlumnosCuerpoInactivaExplicacion;
    // Móvil, decisión del dueño 2026-09-29: sólo el estado — sin "para sumar
    // más, subí de plan" (3.1.3(f)). Guard:
    // `avisos_de_tope_movil_sin_llamado_a_comprar_test.dart`.
    final cupo = currentTier.weightLimit;
    return cupo == null
        ? l10n.planLimitAlumnosCuerpoTopeMovilIlimitado(tierName(currentTier))
        : l10n.planLimitAlumnosCuerpoTopeMovilLimitado(
            tierName(currentTier), cupo);
  }

  /// El beneficio del siguiente tier ([next]) para la tarjeta de upsell.
  /// `weightLimit == null` = SIN LÍMITE (Plan 3), nunca se interpola.
  String _beneficio(BuildContext context, SubscriptionTier next) {
    if (isWeb) {
      return next.isUnlimited
          ? 'Alumnos sin límite' // i18n: Fase W3
          : 'Hasta ${next.weightLimit} alumnos'; // i18n: Fase W3
    }
    final l10n = AppL10n.of(context);
    final cupo = next.weightLimit;
    return cupo == null
        ? l10n.planLimitAlumnosBeneficioIlimitado
        : l10n.planLimitAlumnosBeneficioLimitado(cupo);
  }
}

/// Caja de la rama `subscription-inactive`. Hermana de [PlanLimitUpsellBox],
/// pero SIN precio-héroe: el precio no es la pregunta acá — el PF ya compró
/// este plan, sólo hay que reactivarlo.
class _ReactivateBox extends StatelessWidget {
  const _ReactivateBox({
    required this.currentTier,
    required this.status,
    required this.palette,
    required this.isWeb,
  });

  final SubscriptionTier currentTier;
  final SubscriptionStatus? status;
  final AppPalette palette;
  final bool isWeb;

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
            isWeb
                ? 'TU PLAN: ${tierName(currentTier).toUpperCase()}' // i18n: Fase W3
                : AppL10n.of(context).planLimitReactivateTituloMovil(
                    tierName(currentTier).toUpperCase()),
            style: TextStyle(
              fontFamily: AppFonts.barlowCondensed,
              color: palette.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isWeb
                // TODO(producto): copy placeholder — pendiente de revisión.
                ? 'Reactivalo y volvés a tus ${cupoTexto(currentTier)} '
                    'al instante.' // i18n: Fase W3
                // Móvil, decisión del dueño 2026-09-29: estado neutro, sin
                // "reactivalo/reactivá/regularizá/pagá" (3.1.3(f)). El
                // efectivo acá SIEMPRE es Free: `subscriptionInactive` es
                // justo "lo que pagaste no está al día", y el derecho cae a
                // Free (mismo criterio que `effectiveWeightLimit` del
                // servidor). Guard:
                // `avisos_de_tope_movil_sin_llamado_a_comprar_test.dart`.
                : AppL10n.of(context).planLimitReactivateCuerpoMovil(
                    SubscriptionTier.free.weightLimit!),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: palette.textMuted, fontSize: AppTextSize.bodyDense),
          ),
          if (status != null) ...[
            const SizedBox(height: 8),
            Text(
              isWeb
                  ? 'Estado: ${_statusName(status!)}' // i18n: Fase W3
                  : AppL10n.of(context).planLimitReactivateEstadoMovil(
                      _statusNameMovil(AppL10n.of(context), status!)),
              style: TextStyle(
                  color: palette.textMuted, fontSize: AppTextSize.caption),
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
    required this.dadaDeBaja,
    required this.billingRoute,
    required this.palette,
    required this.isWeb,
  });

  final bool hasNext;
  final bool isInactive;

  /// Rama inactiva con la suscripción `cancelled`: el SnackBar no puede decir
  /// «pausada» de una baja.
  final bool dadaDeBaja;
  final String? billingRoute;
  final AppPalette palette;
  final bool isWeb;

  @override
  Widget build(BuildContext context) {
    if (isInactive) {
      // El texto del SnackBar se resuelve ACÁ y no adentro del `onTap`: ahí
      // ya se hizo `pop()` del modal y no se vuelve a leer su contexto. La
      // WEB sigue con el hardcodeado de siempre (`i18n: Fase W3`); el MÓVIL
      // sale de AppL10n.
      final estado = switch ((isWeb, dadaDeBaja)) {
        (true, true) => 'Tu suscripción está dada de baja.', // i18n: Fase W3
        (true, false) => 'Tu suscripción está pausada.', // i18n: Fase W3
        (false, true) => AppL10n.of(context).planLimitSuscripcionBajaMovil,
        (false, false) => AppL10n.of(context).planLimitSuscripcionPausadaMovil,
      };
      return PlanLimitAccentButton(
        // "REGULARIZAR" es un verbo de pago — en el móvil, con el SnackBar
        // de abajo ya diciendo el estado, el botón pasa a describir lo que
        // efectivamente hace ("VER ESTADO") y no lo que Apple prohíbe pedir
        // (3.1.3(f)). Decisión del dueño, 2026-09-29. Guard:
        // `avisos_de_tope_movil_sin_llamado_a_comprar_test.dart`.
        label: isWeb
            ? 'REGULARIZAR' // i18n: Fase W3
            : AppL10n.of(context).planLimitVerEstadoMovil,
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
              // ⚠️ ACA DECIA DONDE SE REGULARIZA, Y ESO ERA EL PROBLEMA.
              //
              // El comentario que estaba aca razonaba sobre 3.1.3(c) —«no
              // navega, no linkea y no abre nada»— y miraba el COBRO. La
              // clausula que muerde es otra: 3.1.3(f) ampara la app del PF
              // «provided there is no purchasing inside the app, **or calls to
              // action for purchase outside of the app**». Un call to action no
              // necesita abrir nada: alcanza con decir donde se paga.
              //
              // Y el amparo se cae solo el dia que el ALUMNO compre por IAP:
              // ahi el binario deja de ser una «free app» y 3.1.3(f) no le
              // aplica mas, por su propio texto.
              //
              // Ahora dice el ESTADO de la cuenta y nada mas. Eso no es un CTA
              // de compra externa: es un hecho sobre su suscripcion.
              //
              // ⚠️ SE PIERDE ALGO REAL, Y NO ES GRATIS: el PF que entro por el
              // telefono se queda sin saber que hacer. El encabezado de
              // `pricing_screen.dart` lo cuantifica — es el 100% del funnel de
              // $12.000-$39.000 por mes. Recuperarlo NO puede ser un cartel
              // acá: tiene que salir por fuera de la app (un mail), que es lo
              // unico que Apple no gobierna.
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(estado)),
              );
            case PlanCheckoutAvailable():
              if (route == null) {
                // Superficie que cobra pero sin vista de facturacion cableada.
                // Antes esto navegaba a '/ajustes' fijo y en movil moria contra
                // una ruta inexistente: el modal decia lo correcto y el boton
                // no hacia nada. Mejor decirlo que fingirlo.
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(estado)),
                );
                return;
              }
              // NUNCA mandar a /facturacion/planes aca: es la pagina de upsell,
              // el mensaje opuesto al que necesita quien ya pago.
              // TODO(producto): deep-link al tab de Facturacion cuando exista.
              context.push(route);
          }
        },
      );
    }
    // Sin siguiente tier ('CONTACTANOS' + su SnackBar) la rama es inalcanzable
    // en producción —Plan 3 es ilimitado en alumnos, así que el servidor nunca
    // bloquea a un PF sin tope; mismo criterio que PLAN A MEDIDA— pero SE
    // RENDERIZA (los tests la ejercitan), así que la forma móvil tampoco puede
    // quedar en castellano acá. Resueltos antes del `onTap`, igual que arriba.
    final contactanos = isWeb
        ? 'CONTACTANOS' // i18n: Fase W3
        : AppL10n.of(context).planLimitContactanos;
    final muyPronto = isWeb
        ? 'Muy pronto vas a poder tener más de 15 alumnos.' // i18n: Fase W3
        : AppL10n.of(context).planLimitAlumnosPlanAMedidaSnack;
    return PlanLimitAccentButton(
      label: !hasNext
          ? contactanos
          : (isWeb
              ? 'VER PLANES' // i18n: Fase W3
              : AppL10n.of(context).planLimitVerPlanesMovil),
      onTap: () {
        Navigator.of(context).pop();
        if (hasNext) {
          // Lleva a la pricing page para completar el cambio de plan.
          context.push('/facturacion/planes');
        } else {
          // Plan 2 tope: aviso del plan a-medida (mock hasta canal de contacto).
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(muyPronto)),
          );
        }
      },
    );
  }
}

/// Nombre del estado para la WEB — hardcodeado, sin cambios (i18n: Fase W3).
String _statusName(SubscriptionStatus status) => switch (status) {
      SubscriptionStatus.active => 'activa', // i18n: Fase W3
      SubscriptionStatus.pending => 'pendiente de pago', // i18n: Fase W3
      SubscriptionStatus.grace => 'con pago pendiente', // i18n: Fase W3
      SubscriptionStatus.paused => 'pausada', // i18n: Fase W3
      SubscriptionStatus.cancelled => 'cancelada', // i18n: Fase W3
    };

/// Hermano de [_statusName] para el MÓVIL — mismo estado, vía AppL10n
/// (hallazgo Codex, 2026-09-29: el móvil no tenía forma de decir esto en
/// inglés).
String _statusNameMovil(AppL10n l10n, SubscriptionStatus status) =>
    switch (status) {
      SubscriptionStatus.active => l10n.planLimitEstadoActiva,
      SubscriptionStatus.pending => l10n.planLimitEstadoPendiente,
      SubscriptionStatus.grace => l10n.planLimitEstadoGracia,
      SubscriptionStatus.paused => l10n.planLimitEstadoPausada,
      SubscriptionStatus.cancelled => l10n.planLimitEstadoCancelada,
    };
