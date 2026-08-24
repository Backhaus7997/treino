import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../../core/utils/argentina_time.dart';
import '../../../../../core/widgets/motion/treino_tappable.dart';
import '../../../../../core/widgets/treino_icon.dart';
import '../../../../coach/application/blocked_athletes_providers.dart';
import '../../../../coach/domain/subscription_tier.dart';
import '../../../../coach/domain/trainer_subscription.dart';
import '../../../../profile/application/user_providers.dart';
import '../../../../profile/application/user_public_profile_providers.dart';
import 'plan_limit_paywall.dart';

/// Qué alumnos del PF quedaron fuera del cupo de su plan, y qué significa eso.
///
/// ## Por qué existe
///
/// Cuando el enforcement frena una escritura, el PF ve rebotar la acción y no
/// tiene forma de saber sobre QUIÉNES le pasa ni por qué. Sin esta pantalla eso
/// es un ticket de soporte por PF; con ella es autoservicio.
///
/// ## La palabra
///
/// «Solo lectura» y no «bloqueado» / «sin acceso», y no es un eufemismo: es lo
/// único que describe bien las DOS mitades. Lo que se frena es que el PF
/// ESCRIBA sobre el alumno — seguirlo viendo, abrir su historial y chatear
/// sigue funcionando. Y del lado del alumno no se frena nada: conserva sus
/// rutinas, su historial y el chat.
///
/// «Bloqueado» se lee como que el alumno perdió algo, y sería falso. La
/// fricción la come el entrenador, nunca el alumno: el copy tiene que decir
/// eso mismo.
///
/// ## Nada se afirma desde un dato que no llegó
///
/// La pantalla necesita DOS lecturas — la lista publicada y el doc del PF — y
/// ninguna de las dos se reemplaza por un default cuando falta. Un
/// `?? SubscriptionTier.free` mientras el perfil carga le diría a un Plan 3
/// que su plan Free incluye 2 alumnos y le ofrecería comprar el Plan 1. Por eso
/// el `loading` de cualquiera de las dos gana sobre todo lo demás, y un perfil
/// que no cargó nunca deriva en [_BlockCause.unknownPlan] en vez de en Free.
/// La ruta de esta pantalla, en UN solo lugar.
///
/// La registra `routes.dart` y la empuja el banner de denegación del editor de
/// rutinas. Escrita dos veces, un typo en cualquiera de las dos manda al PF a
/// la página de error de go_router justo en el momento en que más necesita la
/// respuesta — y compila, y pasa la suite, porque nada compara los dos
/// literales.
const String kBlockedStudentsRoutePath = '/facturacion/alumnos-solo-lectura';

class BlockedStudentsScreen extends ConsumerWidget {
  const BlockedStudentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final blockedAsync = ref.watch(blockedAthletesProvider);
    final profileAsync = ref.watch(userProfileProvider);

    // El perfil resolvió cuando emitió algo (incluso `null`: sin sesión, o el
    // stream de auth erroró) o cuando falló. Mientras no pasó ninguna de las
    // dos NO se sabe qué plan tiene, y con `valueOrNull` eso es indistinguible
    // de «no tiene suscripción» — que es justo la confusión que baja un Plan 3
    // a Free.
    final profileResolved = profileAsync.hasValue || profileAsync.hasError;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: switch (blockedAsync) {
            // El error se muestra en vez de tragarse: una lista vacía por un
            // read fallido diría «no tenés ninguno», que es justo la respuesta
            // equivocada para el PF que llegó acá porque algo le rebotó.
            AsyncError() => _Message(
                icon: TreinoIcon.warning,
                title: 'NO PUDIMOS CARGAR TU CUPO', // i18n: Fase W3
                body: 'Volvé a entrar en un rato. Mientras tanto, nada de lo '
                    'que tenés cargado se toca.', // i18n: Fase W3
                palette: palette,
              ),
            AsyncData(:final value) when profileResolved => _Loaded(
                blocked: value,
                subscription: profileAsync.valueOrNull?.subscription,
                profileLoaded: profileAsync.valueOrNull != null,
                palette: palette,
              ),
            _ => const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
          },
        ),
      ),
    );
  }
}

class _Loaded extends ConsumerWidget {
  const _Loaded({
    required this.blocked,
    required this.subscription,
    required this.profileLoaded,
    required this.palette,
  });

  final BlockedAthletes blocked;
  final TrainerSubscription? subscription;

  /// `false` cuando el doc del PF no se pudo leer. Sin él no se sabe el tier,
  /// y un PF sin `subscription` (Free legítimo) no es lo mismo que un PF cuyo
  /// perfil no llegó.
  final bool profileLoaded;

  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Sin suscripción en un perfil que SÍ cargó → Free (sin backfill), igual
    // que la tab de Facturación.
    final tier = subscription?.tier ?? SubscriptionTier.free;
    final cause = profileLoaded
        ? _causeOf(tier: tier, subscription: subscription)
        : _BlockCause.unknownPlan;

    if (blocked.ids.isEmpty) {
      return _EmptyState(
        isPublished: blocked.isPublished,
        cause: cause,
        tier: tier,
        subscription: subscription,
        palette: palette,
      );
    }

    // Una sola lectura batcheada en vez de un listener por fila. La key va
    // ordenada para que dos builds con el mismo conjunto compartan instancia
    // de provider (contrato de userPublicProfilesBatchProvider).
    final key = (blocked.ids.toList()..sort()).join(',');
    final profiles =
        ref.watch(userPublicProfilesBatchProvider(key)).valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.accent.withValues(alpha: 0.08),
              border: Border.all(color: palette.accent.withValues(alpha: 0.33)),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(TreinoIcon.eye, size: 28, color: palette.accent),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'ALUMNOS EN SOLO LECTURA', // i18n: Fase W3
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
          _explanation(
            cause: cause,
            tier: tier,
            count: blocked.ids.length,
            subscription: subscription,
          ),
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.textMuted, fontSize: 14),
        ),
        const SizedBox(height: 12),
        // La mitad que más importa y la que más fácil se malentiende. Va en
        // caja aparte, no como una línea más del párrafo, porque es la
        // respuesta a la primera pregunta que se hace el PF: «¿qué perdió mi
        // alumno?». Nada.
        _AthleteSideBox(palette: palette),
        const SizedBox(height: 22),
        for (final id in blocked.ids.toList()..sort())
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _StudentRow(
              // Un doc público que todavía no cargó (o que no existe) no
              // puede borrar la fila: el PF necesita ver que son N, con
              // nombre o sin él.
              displayName: profiles?[id]?.displayName ?? 'Alumno', // i18n
              palette: palette,
            ),
          ),
        const SizedBox(height: 12),
        if (_ctaFits(cause))
          _UpgradeCta(
            tier: tier,
            isInactive: cause == _BlockCause.subscriptionInactive,
            status: subscription?.status,
            palette: palette,
          ),
      ],
    );
  }
}

/// Sin lista que mostrar. Cuál de los cuatro mensajes va NO depende sólo de
/// que la lista esté vacía: depende de si el backend la publicó y de qué se
/// sabe del plan.
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.isPublished,
    required this.cause,
    required this.tier,
    required this.subscription,
    required this.palette,
  });

  final bool isPublished;
  final _BlockCause cause;
  final SubscriptionTier tier;
  final TrainerSubscription? subscription;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    // Sin lista publicada no hay «ninguno» que afirmar. Decir acá «no fue por
    // el cupo de tu plan» sería la afirmación más cara de la pantalla hecha
    // sobre un dato que el backend nunca escribió.
    if (!isPublished) {
      return _Message(
        icon: TreinoIcon.warning,
        title: 'TODAVÍA NO LO SABEMOS', // i18n: Fase W3
        body: 'Tu cuenta todavía no tiene publicada la lista de alumnos fuera '
            'de cupo, así que no podemos confirmarte si el cupo explica lo que '
            'te rebotó. Volvé a entrar más tarde.', // i18n: Fase W3
        palette: palette,
      );
    }

    return switch (cause) {
      // El que MÁS necesita mirar facturación. Mandarlo a dejar de mirarla
      // porque hoy nadie quedó afuera es el consejo exactamente opuesto: su
      // límite efectivo ya cayó a Free y el próximo alumno rebota.
      _BlockCause.subscriptionInactive => Column(
          mainAxisSize: MainAxisSize.min,
          // `stretch` para que el CTA quede del mismo ancho que en el estado
          // con lista; sin él la píldora se encoge al texto y las dos mitades
          // de la misma pantalla se ven distintas.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Message(
              icon: TreinoIcon.users,
              title: 'NINGUNO', // i18n: Fase W3
              body: 'Ninguno de tus alumnos quedó fuera de tu cupo. Pero '
                  'mientras tu suscripción no esté al día tu cuenta funciona '
                  'con el límite del plan Free '
                  '(${_cupoTexto(SubscriptionTier.free)}), no con el de tu '
                  'plan ${_tierName(tier)}.', // i18n: Fase W3
              palette: palette,
            ),
            const SizedBox(height: 20),
            _UpgradeCta(
              tier: tier,
              isInactive: true,
              status: subscription?.status,
              palette: palette,
            ),
          ],
        ),
      // Igual que con la lista: se nombra el hecho y no el límite vigente.
      // «No fue por el cupo de tu plan» acá sería falso si la fecha ya pasó.
      _BlockCause.subscriptionCancelled => _Message(
          icon: TreinoIcon.users,
          title: 'NINGUNO', // i18n: Fase W3
          body: 'Ninguno de tus alumnos quedó fuera de tu cupo. Cancelaste tu '
              'suscripción: tu plan ${_tierName(tier)} rige hasta el '
              '${_fechaArg(subscription!.currentPeriodEnd!)} y después tu '
              'cuenta funciona con el límite del plan Free '
              '(${_cupoTexto(SubscriptionTier.free)}).', // i18n: Fase W3
          palette: palette,
        ),
      // Sin el doc del PF no se puede nombrar su cupo. Se dice lo que sí se
      // sabe y se calla lo que no.
      _BlockCause.unknownPlan => _Message(
          icon: TreinoIcon.users,
          title: 'NINGUNO', // i18n: Fase W3
          body: 'Ninguno de tus alumnos quedó fuera de tu cupo. No pudimos '
              'leer tu plan, así que no podemos decirte cuánto cupo te '
              'queda.', // i18n: Fase W3
          palette: palette,
        ),
      _ => _Message(
          icon: TreinoIcon.users,
          title: 'NINGUNO', // i18n: Fase W3
          // La segunda frase es el valor real de este estado vacío: le dice al
          // PF que dejó de tener sentido mirar su plan. Sin ella, el que llegó
          // desde un error se queda sin saber qué mirar.
          body: 'Ninguno de tus alumnos quedó fuera del cupo de tu plan '
              '${_tierName(tier)} (${_cupoTexto(tier)}). Si aun así te rebotó '
              'una acción, no fue por el cupo de tu plan.', // i18n: Fase W3
          palette: palette,
        ),
    };
  }
}

/// Por qué hay alumnos afuera del cupo, hasta donde el cliente PUEDE probarlo.
///
/// La pantalla no adivina: cada rama sale de un dato que está en el doc del
/// PF, y las que no se pueden explicar se llaman [unexplained] / [unknownPlan]
/// en vez de asumir la causa más probable.
enum _BlockCause {
  /// La suscripción no está al día, así que el límite EFECTIVO cayó a Free.
  /// Problema de cobro: ofrecerle un plan más caro es el mensaje equivocado.
  subscriptionInactive,

  /// Cancelada, con un `currentPeriodEnd` que el PF pagó.
  ///
  /// El servidor le respeta el tier pago HASTA esa fecha y después lo baja a
  /// Free (`effective-limit.ts`), así que de qué lado de la fecha estamos
  /// decide la causa — y el cliente no lo puede saber sin leer el reloj, que
  /// en el módulo Coach está prohibido (`no_raw_clock_scan_test.dart`). En vez
  /// de adivinar se dice el HECHO, que es cierto de los dos lados: cancelaste,
  /// y tu plan rige hasta tal fecha.
  subscriptionCancelled,

  /// Suscripción al día y el tier tiene tope: se quedó chico. Problema de
  /// upsell.
  planLimit,

  /// Suscripción al día y tier SIN LÍMITE. No debería poder pasar; si pasa,
  /// el cupo no lo explica y decir «llegaste al límite» sería mentira.
  unexplained,

  /// El doc del PF no cargó. No se sabe el tier ni el estado de cobro, así que
  /// no hay causa que afirmar ni CTA que ofrecer sin adivinar cuál.
  unknownPlan,
}

/// El CTA sólo aparece cuando se sabe QUÉ ofrecer.
///
/// En [_BlockCause.unexplained] ampliar no destraba nada (el plan ya es
/// ilimitado y está al día) y en [_BlockCause.unknownPlan] no se sabe si
/// corresponde upsell o regularizar — y las dos mitades son el mensaje
/// equivocado para la otra. Un botón que promete un arreglo que no arregla es
/// peor que no tener botón.
///
/// [_BlockCause.subscriptionCancelled] cae en la misma bolsa por una razón
/// distinta: DENTRO del período pagado el tier sigue vigente, así que lo que
/// falta es cupo y reactivar no destraba nada; PASADA la fecha sí hace falta
/// reactivar. Sin reloj no se sabe cuál de las dos, y las dos se venden con
/// botones opuestos.
bool _ctaFits(_BlockCause cause) =>
    cause == _BlockCause.planLimit || cause == _BlockCause.subscriptionInactive;

/// Espeja `effectiveWeightLimit` de `functions/src/subscriptions/
/// effective-limit.ts`, que es la autoridad real — hasta donde el cliente
/// PUEDE espejarlo.
///
/// `active` y `grace` conservan el derecho al tier pago (durante la gracia no
/// se castiga el primer cobro fallido). `pending` y `paused` bajan a Free. Sin
/// `subscription` en el doc, el PF es Free/active por definición y la causa es
/// el cupo.
///
/// ## `cancelled` es el que no se puede resolver acá, y por qué
///
/// El servidor conserva el tier pago HASTA `currentPeriodEnd` y recién después
/// baja a Free (`effective-limit.test.ts`: «cancelled before currentPeriodEnd
/// → still paid tier»). O sea que la causa depende de de qué lado de esa fecha
/// estamos, y eso pide el reloj.
///
/// El reloj crudo no se puede usar: `no_raw_clock_scan_test.dart` prohíbe el
/// `DateTime.now` pelado en archivos nuevos de `coach/` y `coach_hub/`, y su
/// allowlist es un ratchet que no crece. Y el helper que sí está permitido,
/// `argentinaNow()`, sería PEOR que el problema: devuelve el instante corrido
/// tres horas para que los campos de calendario lean en ART, así que
/// compararlo contra un instante real da tres horas de ventana equivocada. Lo
/// dice `argentina_time.dart` textual: «INSTANTS (createdAt, paidAt, "has it
/// ended yet") stay in true UTC».
///
/// Así que no se decide: se devuelve [_BlockCause.subscriptionCancelled], que
/// dice el hecho comprobable (cancelaste, tu plan rige hasta tal fecha) y no
/// afirma ningún límite ni ofrece ningún CTA. Es la misma regla del resto de
/// la pantalla aplicada a un dato que falta: el reloj.
_BlockCause _causeOf({
  required SubscriptionTier tier,
  required TrainerSubscription? subscription,
}) {
  final status = subscription?.status;
  final entitledToTier = switch (status) {
    null || SubscriptionStatus.active || SubscriptionStatus.grace => true,
    // Sin `currentPeriodEnd` no hay período pagado que respetar, así que no
    // hay ambigüedad: el servidor ya lo bajó a Free.
    SubscriptionStatus.cancelled =>
      subscription?.currentPeriodEnd == null ? false : null,
    SubscriptionStatus.pending || SubscriptionStatus.paused => false,
  };
  if (entitledToTier == null) return _BlockCause.subscriptionCancelled;
  if (!entitledToTier) return _BlockCause.subscriptionInactive;
  return tier.isUnlimited ? _BlockCause.unexplained : _BlockCause.planLimit;
}

/// `dd/mm` de un instante, en calendario argentino.
///
/// Va con `toArgentina` y no leyendo los campos crudos ni convirtiendo a hora
/// local: `currentPeriodEnd` es un instante UTC, y entre las 21:00 y las 23:59
/// ART su día UTC ya es el siguiente — el PF leería una fecha corrida un día.
///
/// (El nombre del helper de conversión local va sin escribir literal a
/// propósito: `no_raw_clock_scan_test.dart` escanea el TEXTO del archivo, así
/// que citarlo en un comentario suma deuda al ratchet igual que usarlo.)
String _fechaArg(DateTime instant) {
  final d = toArgentina(instant.toUtc());
  return '${d.day}/${d.month}';
}

String _explanation({
  required _BlockCause cause,
  required SubscriptionTier tier,
  required int count,
  required TrainerSubscription? subscription,
}) =>
    switch (cause) {
      // Cierto de los dos lados de la fecha, que es lo que lo hace decible sin
      // reloj. No se afirma cuál límite rige HOY, porque eso sí dependería de
      // saberlo.
      _BlockCause.subscriptionCancelled =>
        'Cancelaste tu suscripción: tu plan ${_tierName(tier)} rige hasta el '
            '${_fechaArg(subscription!.currentPeriodEnd!)} y después tu cuenta '
            'funciona con el límite del plan Free '
            '(${_cupoTexto(SubscriptionTier.free)}). Sobre estos $count pasás '
            'a solo lectura: los seguís viendo y podés chatear, pero no podés '
            'editarles rutinas ni notas.', // i18n: Fase W3
      _BlockCause.subscriptionInactive =>
        'Mientras tu suscripción no esté al día, tu cuenta funciona con el '
            'límite del plan Free (${_cupoTexto(SubscriptionTier.free)}). '
            'Sobre estos $count pasás a solo lectura: los seguís viendo y '
            'podés chatear, pero no podés editarles rutinas ni '
            'notas.', // i18n: Fase W3
      // «Superó ese cupo» y no «hoy tenés más [alumnos]»: el tope es de CARGA
      // PONDERADA, no de cabezas (ver `weighted-load.ts`), así que un PF con 9
      // alumnos de los cuales 6 están pausados pesa 6.0 y NO superó un tope de
      // 7. Compararlo contra lo que el PF cuenta en su lista lo dejaría
      // leyendo una resta que no cierra.
      _BlockCause.planLimit => 'Tu plan ${_tierName(tier)} incluye '
          '${_cupoTexto(tier)} y tu cuenta superó ese cupo (un alumno pausado '
          'cuenta mitad). Sobre estos $count pasás a solo lectura: los seguís '
          'viendo y podés chatear, pero no podés editarles rutinas ni '
          'notas.', // i18n: Fase W3
      // Sin causa demostrable no se inventa una. Se describe el ESTADO, que
      // sí es cierto, y se dice explícitamente que el cupo no lo explica.
      _BlockCause.unexplained =>
        'Sobre estos $count alumnos tu cuenta quedó en solo lectura: los '
            'seguís viendo y podés chatear, pero no podés editarles rutinas '
            'ni notas. Tu plan ${_tierName(tier)} no tiene tope de alumnos, '
            'así que esto no es por el cupo.', // i18n: Fase W3
      _BlockCause.unknownPlan =>
        'Sobre estos $count alumnos tu cuenta quedó en solo lectura: los '
            'seguís viendo y podés chatear, pero no podés editarles rutinas '
            'ni notas. No pudimos leer tu plan, así que no podemos decirte si '
            'el cupo lo explica.', // i18n: Fase W3
    };

/// Lo que el alumno conserva. Afirmación fuerte y verificable: el enforcement
/// del paywall sólo frena escrituras DEL PF.
class _AthleteSideBox extends StatelessWidget {
  const _AthleteSideBox({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bg,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(TreinoIcon.infoCircle, size: 18, color: palette.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Del lado de ellos no cambia nada: siguen entrenando con sus '
              'rutinas, su historial y el chat. No se elimina ni se pausa '
              'ningún alumno.', // i18n: Fase W3
              style: TextStyle(color: palette.textMuted, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({required this.displayName, required this.palette});

  final String displayName;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.accent.withValues(alpha: 0.18),
            ),
            child: Text(
              displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
              style: GoogleFonts.barlowCondensed(
                color: palette.accent,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Nombre y etiqueta APILADOS, no lado a lado. Con la etiqueta al
          // costado los dos textos compiten por el ancho y a textScale 2.0 en
          // un teléfono chico la fila desborda (43px medidos). Apilados no hay
          // competencia: los dos crecen hacia abajo, que es la dirección que
          // el scroll ya resuelve.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                // Etiqueta de estado. Dice lo que le pasa AL PF sobre ese
                // alumno, no lo que le pasa al alumno.
                Text(
                  'solo lectura', // i18n: Fase W3
                  style: TextStyle(color: palette.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Salida a facturación.
///
/// Delega en [showPlanLimitPaywall] en vez de navegar derecho a la pricing
/// page: el modal ya distingue las dos causas y manda a distinto lado. A quien
/// tiene la suscripción caída ofrecerle un plan MÁS CARO es el mensaje
/// equivocado — ya compró uno, lo que necesita es regularizar.
class _UpgradeCta extends StatelessWidget {
  const _UpgradeCta({
    required this.tier,
    required this.isInactive,
    required this.status,
    required this.palette,
  });

  final SubscriptionTier tier;
  final bool isInactive;
  final SubscriptionStatus? status;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return TreinoTappable(
      onTap: () => unawaited(
        showPlanLimitPaywall(
          context,
          currentTier: tier,
          reason: isInactive
              ? PlanLimitReason.subscriptionInactive
              : PlanLimitReason.planLimit,
          subscriptionStatus: status,
          // El Coach Hub SÍ tiene vista de facturación (tab de Ajustes).
          billingRoute: '/ajustes',
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.accent,
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
        child: Text(
          isInactive
              ? 'REGULARIZAR MI SUSCRIPCIÓN' // i18n: Fase W3
              : 'AMPLIAR MI PLAN', // i18n: Fase W3
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

/// Estado sin lista: vacío feliz, «no sé», o error de carga.
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    required this.palette,
  });

  final IconData icon;
  final String title;
  final String body;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 40, color: palette.textMuted),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: TextAlign.center,
          style: GoogleFonts.barlowCondensed(
            color: palette.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.textMuted, fontSize: 14),
        ),
      ],
    );
  }
}

/// Cupo del tier en texto.
///
/// `weightLimit == null` (plan3) NO es un dato faltante: es SIN LÍMITE.
/// Interpolarlo directo renderiza la palabra «null» — ya pasó una vez, en el
/// upsell del plan más caro («Hasta null alumnos»).
String _cupoTexto(SubscriptionTier tier) => tier.isUnlimited
    ? 'alumnos sin límite' // i18n: Fase W3
    : '${tier.weightLimit} alumnos'; // i18n: Fase W3

String _tierName(SubscriptionTier tier) => switch (tier) {
      SubscriptionTier.free => 'Free', // i18n: Fase W3
      SubscriptionTier.plan1 => 'Plan 1', // i18n: Fase W3
      SubscriptionTier.plan2 => 'Plan 2', // i18n: Fase W3
      SubscriptionTier.plan3 => 'Plan 3', // i18n: Fase W3
    };
