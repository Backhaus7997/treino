import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../app/theme/app_motion.dart';
import '../../app/theme/app_palette.dart';
import '../../core/widgets/motion/treino_fade_slide_in.dart';
import '../../core/widgets/treino_icon.dart';
import '../../l10n/app_l10n.dart';
import '../coach/application/trainer_link_providers.dart';
import '../coach/domain/trainer_link.dart';
import '../coach/presentation/trainer_dashboard_tab.dart';
import '../notifications/presentation/permission_gate.dart';
import '../notifications/presentation/widgets/notification_bell.dart';
import '../onboarding/presentation/onboarding_gate.dart';
import '../profile/application/user_providers.dart';
import '../profile/domain/user_role.dart';
import '../profile/presentation/legacy_privacy_notice_banner.dart';
import '../profile/presentation/trainer_location_consent_sheet.dart'
    show TrainerLocationConsentGate;
import '../workout/application/assigned_routine_providers.dart';
import '../workout/application/session_duration.dart';
import '../workout/application/session_providers.dart';
import '../workout/application/weekly_streak_providers.dart';
import '../workout/application/user_routines_providers.dart';
import '../workout/domain/session.dart';
import '../watch/application/watch_credential_providers.dart'
    show watchNudgeServiceProvider;
import '../watch/data/watch_nudge_service.dart';
import '../workout/domain/set_log.dart';
import '../workout/presentation/widgets/resume_session_modal.dart';
import 'widgets/daily_check_in_card.dart';
import 'widgets/empezar_entrenamiento_card.dart';
import 'widgets/esta_semana_card.dart';
import 'widgets/home_cta_button.dart';
import 'widgets/home_header.dart';
import '../coach/presentation/widgets/invite_gate.dart';

/// Role-aware home screen.
///
/// - Trainer → [TrainerDashboardTab] (mirrors docs/app-trainer/screens/dashboard).
/// - Athlete → existing athlete home (header + Empezar + Esta semana + resume
///   session modal listener).
/// - Loading → empty surface (cheap, no spinner — matches `_CoachLoadingView`
///   pattern in [CoachScreen]).
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserRole? role = ref.watch(
      userProfileProvider.select((async) => async.valueOrNull?.role),
    );

    // Default to athlete view while role is loading. Athletes are the
    // dominant user, and the athlete home is safe to render without role
    // confirmation (HomeHeader gracefully handles a null profile). Trainers
    // may see a brief athlete flicker before their dashboard mounts — an
    // acceptable trade for not stalling the 99% common case.
    return Stack(
      children: [
        role == UserRole.trainer
            ? const TrainerDashboardTab()
            : const _AthleteHome(),
        // REQ-PN-PERM-001: session-scoped permission prompt.
        // Renders SizedBox.shrink() — zero layout impact. ADR-PN-012.
        const PermissionGate(),
        // Welcome tour, once per surface (#627). Also SizedBox.shrink().
        // Ordered after PermissionGate for readability only — the actual
        // sequencing (tour first, prompt second) is enforced by
        // `onboardingBlocksProvider`, not by Stack order.
        const OnboardingGate(),
        // Invitación de un PF pendiente de aplicar (#alta de alumnos). También
        // SizedBox.shrink(). Va después del tour por legibilidad: no compiten
        // —el tour corre una vez por superficie y la invitación sólo existe si
        // alguien abrió un link— y ninguno bloquea al otro.
        const InviteGate(),
        // Trainer location-publication consent prompt
        // (consentimiento-legal-versionado, R7). Also SizedBox.shrink() —
        // waits on `onboardingBlocksProvider` internally so it never stacks
        // with the welcome tour or the push-permission prompt on the same
        // frame.
        const TrainerLocationConsentGate(),
        // Aviso de política actualizada para el atleta legacy
        // (consentimiento-legal-versionado, R4). Único de este Stack que sí
        // pinta algo: los otros cuatro son prompts que colapsan a
        // SizedBox.shrink(). Este también colapsa cuando no corresponde, y
        // cuando corresponde se ancla abajo sin capturar los taps de la app
        // — a diferencia de ellos, no interrumpe nada. Va último para quedar
        // por encima en el Stack.
        const LegacyPrivacyNoticeBanner(),
      ],
    );
  }
}

/// Athlete home — original [HomeScreen] body extracted intact so role split
/// is purely additive.
class _AthleteHome extends ConsumerWidget {
  const _AthleteHome();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);

    // Resume-on-reopen listener (REQ-SESSION-RESUME-002 / Decision 12).
    ref.listen<AsyncValue<({Session session, List<SetLog> setLogs})?>>(
      activeSessionForUidProvider,
      (prev, next) {
        // Dedupe by stable session id, not identity. The provider returns a
        // fresh Dart record on every run, so `identical` never matches and the
        // resume dialog would re-stack whenever currentUidProvider's auth
        // stream re-emits the same active session.
        if (prev?.valueOrNull?.session.id == next.valueOrNull?.session.id) {
          return;
        }
        _maybeShowResumePrompt(context, ref, next);
      },
    );

    // The avatar opens the athlete's OWN public profile. Pushed (not `go`)
    // so PublicProfileScreen's back affordance — `canPop() ? pop() : go('/feed')`
    // — pops back to Home instead of falling through to the feed. The
    // `/home/profile/:uid` twin keeps INICIO highlighted (see router.dart).
    final Widget headerOrSkeleton = profileAsync.when(
      data: (profile) => HomeHeader(
        profile: profile,
        accion: const NotificationBell(),
        onAvatarTap: profile == null
            ? null
            : () => context.push('/home/profile/${profile.uid}'),
      ),
      loading: () => const _HomeHeaderSkeleton(),
      error: (_, __) =>
          const HomeHeader(profile: null, accion: NotificationBell()),
    );

    // Gate the hero "Empezar" card behind real routine data so a brand-new
    // athlete never lands on a hardcoded fake workout (finding 5). We treat
    // the athlete as first-run only once BOTH their self-created routines and
    // their trainer-assigned plans have resolved to empty. While either is
    // loading or errors, fall back to the existing card (no spinner flash,
    // and we never hide a real workout behind a transient empty read).
    final uid = ref.watch(currentUidProvider) ?? '';
    final hasNoRoutine = uid.isEmpty
        ? false
        : _isEmptyData(ref.watch(userCreatedRoutinesProvider(uid))) &&
            _isEmptyData(ref.watch(assignedRoutinesProvider(uid)));

    // El tercer camino ("Buscar entrenador") sólo se ofrece cuando el servidor
    // CONFIRMÓ que el atleta no tiene PF activo — mismo criterio que
    // `_isEmptyData`, del otro lado del dato.
    //
    // Se mira ACÁ y no adentro de `_AthleteFirstRunCard` a propósito: así la
    // suscripción arranca en el mismo frame que las dos consultas de rutinas,
    // y como la card no se monta hasta que ESAS confirman contra el servidor,
    // para cuando aparece el vínculo ya resolvió. Mirándolo adentro de la card
    // la consulta recién empezaría al montarse, y el primer arranque —el caso
    // más común de esta card— mostraría dos caminos y saltaría a tres.
    //
    // Con `select` y no watcheando el `AsyncValue` entero: de todo el vínculo
    // acá sólo se usan tres estados, y sin el select cualquier re-emisión del
    // stream —un cambio de `status`, un `updatedAt`— rebuildea _AthleteHome
    // entera sin que se dibuje nada distinto.
    final estadoDelVinculo = ref.watch(
      currentAthleteLinkProvider.select(_estadoDelVinculo),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      // SingleChildScrollView + Column (no ListView(children:)): un
      // ListView, aunque construya sus widgets eager, sigue siendo un
      // viewport — los Elements/State de los TreinoFadeSlideIn que salen
      // del cacheExtent se desmontan y re-animan al volver a scrollear.
      // Column dentro de SingleChildScrollView scrollea como una sola
      // unidad, sin reciclar Elements por ítem (ver doc de
      // TreinoFadeSlideIn).
      child: SingleChildScrollView(
        // + bottom inset: the floating bar overlays the body (extendBody),
        // so the last item needs room to scroll out from behind it.
        padding: EdgeInsets.fromLTRB(
          0,
          20,
          0,
          20 + MediaQuery.paddingOf(context).bottom,
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TreinoFadeSlideIn(
              delay: AppMotion.stagger(0),
              child: headerOrSkeleton,
            ),
            const SizedBox(height: 20),
            TreinoFadeSlideIn(
              delay: AppMotion.stagger(1),
              child: hasNoRoutine
                  ? _AthleteFirstRunCard(estadoDelVinculo: estadoDelVinculo)
                  : const EmpezarEntrenamientoCard(),
            ),
            const SizedBox(height: 12),
            TreinoFadeSlideIn(
              delay: AppMotion.stagger(2),
              child: const EstaSemanaCard(),
            ),
            const SizedBox(height: 12),
            // Debajo de "Esta semana" a propósito: lo que trae al atleta a
            // Inicio sigue siendo entrenar. El check-in SUMA una dimensión, no
            // reemplaza ni desplaza a las métricas objetivas (#643).
            TreinoFadeSlideIn(
              delay: AppMotion.stagger(3),
              child: const DailyCheckInCard(),
            ),
          ],
        ),
      ),
    );
  }
}

/// True only when [async] has resolved to an empty list. Loading and error
/// states return false so the caller keeps showing the existing workout card
/// instead of a premature first-run empty state (finding 5).
bool _isEmptyData(AsyncValue<List<Object?>> async) =>
    async.valueOrNull?.isEmpty ?? false;

/// Lo que la card de primer arranque sabe sobre el vínculo del atleta con un
/// PF. Son TRES estados y no dos, y la diferencia no es teórica.
///
/// La primera versión de esto era un `bool showFindTrainer`, y colapsaba
/// [sinConfirmar] contra [conPf]: bajo incertidumbre ocultaba el CTA —bien— y
/// **además** mostraba el body que dice "Ya tenés entrenador" —mal—. Para un
/// atleta SIN PF con la caché fría o un error de permisos, la tarjeta le
/// afirmaba en la cara algo que nadie confirmó. Es exactamente la advertencia
/// falsa de AGENTS.md §11.1, cometida por el mismo cambio que vino a sacar
/// otra. Lo encontró Codex en el PR #1124.
///
/// Ocultar un botón y afirmar un hecho son decisiones distintas y necesitan
/// estados distintos.
enum _EstadoDelVinculo {
  /// El servidor confirmó que tiene PF activo.
  conPf,

  /// El servidor confirmó que NO tiene PF. Es lo único que habilita a ofrecer
  /// "Buscar entrenador" y a enumerar los tres caminos.
  sinPf,

  /// Todavía no se sabe: cargando, error, o un error que retuvo un valor
  /// previo. Se ocultan los botones que dependen del vínculo y el copy no
  /// afirma nada sobre él.
  sinConfirmar,
}

/// Traduce el `AsyncValue` del vínculo a uno de los tres estados.
///
/// **No sirve `valueOrNull`**, que es el idioma del resto del archivo: el dato
/// de este provider ya es `TrainerLink?`, así que `valueOrNull` da `null`
/// tanto para "todavía no sé" como para "confirmado que no hay", y colapsa
/// justo la distinción que decide qué se dibuja.
///
/// **Tampoco alcanza `hasValue` solo.** Riverpod retiene el último valor al
/// entrar en error (`AsyncError.copyWithPrevious`), así que después de un
/// `AsyncData(null)` seguido de una falla del stream, `hasValue` sigue en true
/// y `value` sigue en null — y el estado se leería como "confirmado que no
/// hay" cuando en realidad el vínculo dejó de estar confirmado. Por eso
/// `hasError` e `isLoading` se miran PRIMERO. (Codex, PR #1124.)
_EstadoDelVinculo _estadoDelVinculo(AsyncValue<TrainerLink?> async) {
  if (async.isLoading || async.hasError || !async.hasValue) {
    return _EstadoDelVinculo.sinConfirmar;
  }
  return async.value == null
      ? _EstadoDelVinculo.sinPf
      : _EstadoDelVinculo.conPf;
}

/// First-run empty state shown on Home when the athlete has no self-created
/// routine and no trainer-assigned plan. Replaces the hardcoded fake workout
/// card with an honest onboarding surface and up to three CTAs (finding 5,
/// #636) — el tercero depende de si ya tiene PF, ver [showFindTrainer].
///
/// ## Los tres caminos y su orden (#636)
///
/// Las entrevistas de la auditoría sacaron tres perfiles de atleta nuevo: el
/// que se arma la rutina solo, el que quiere agarrar un plan ya hecho, y el
/// que quiere un PF que lo guíe. Los tres tienen que ser legibles de un
/// vistazo — por eso el camino de PLANES es un botón con el MISMO peso visual
/// que "Buscar entrenador", no un link chiquito abajo.
///
/// El orden es **CREAR RUTINA → Explorar planes → Buscar entrenador**, y no
/// el "menor esfuerzo primero" que sugería el issue, por dos razones:
///
/// 1. El propio issue descartó rotar cuál de los tres gana la jerarquía
///    ("Reemplazar 'Crear rutina' por 'Elegir plantilla' como CTA primario.
///    Descartado"). Poner un `OutlinedButton` ARRIBA del botón lleno no
///    entrega esa prioridad: el peso visual le gana al orden de lectura y el
///    ojo cae igual en el botón lleno. Sería una jerarquía contradictoria,
///    no la que se buscaba.
/// 2. Entre los dos secundarios —que sí pesan igual— el orden manda de
///    verdad, y ahí PLANES va primero. Ahí es donde la hipótesis del issue
///    se puede aplicar sin romper el punto 1.
///
/// El body de l10n enumera los caminos EN ESTE MISMO ORDEN. Si alguien
/// reordena los botones, tiene que reescribir `homeAthleteFirstRunBody`.
///
/// ## El tercer camino es condicional
///
/// Un atleta que YA tiene PF activo pero todavía no recibió su plan cae igual
/// en esta card —la condición de arriba mira rutinas, no vínculo— y ofrecerle
/// "Buscar entrenador" es decirle que busque lo que ya tiene.
///
/// **Y el body cambia con el botón**, porque sacar un botón sin tocar el texto
/// deja la card prometiendo tres caminos y mostrando dos — el desfasaje que el
/// dartdoc de arriba venía avisando.
///
/// De ahí los TRES bodies, uno por cada [_EstadoDelVinculo]:
///
/// | estado | botones | body |
/// |---|---|---|
/// | [_EstadoDelVinculo.sinPf] | 3 | enumera los tres caminos |
/// | [_EstadoDelVinculo.conPf] | 2 | "Ya tenés entrenador…" |
/// | [_EstadoDelVinculo.sinConfirmar] | 2 | **neutro**: no dice nada del PF |
///
/// El tercero existe porque la primera versión usaba un `bool` y bajo
/// incertidumbre mostraba el body de "ya tenés entrenador" a alguien que capaz
/// no tiene ninguno. Ocultar un botón y afirmar un hecho son decisiones
/// distintas — ver [_EstadoDelVinculo].
class _AthleteFirstRunCard extends StatelessWidget {
  const _AthleteFirstRunCard({required this.estadoDelVinculo});

  /// Lo que se sabe del vínculo con un PF. Ver [_estadoDelVinculo].
  final _EstadoDelVinculo estadoDelVinculo;

  /// El tercer camino sólo se ofrece con confirmación del servidor de que NO
  /// hay PF. Bajo incertidumbre no se ofrece: ver [_EstadoDelVinculo].
  bool get _ofreceBuscarEntrenador =>
      estadoDelVinculo == _EstadoDelVinculo.sinPf;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.homeAthleteFirstRunTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              // Atado al MISMO estado que dibuja los botones, y no a una copia
              // del criterio: si divergen, la card miente sobre sí misma.
              switch (estadoDelVinculo) {
                _EstadoDelVinculo.sinPf => l10n.homeAthleteFirstRunBody,
                _EstadoDelVinculo.conPf =>
                  l10n.homeAthleteFirstRunBodyWithTrainer,
                // Sin confirmar: se enumeran los dos caminos que SÍ se
                // dibujan y no se dice una palabra sobre el entrenador,
                // porque no se sabe si tiene.
                _EstadoDelVinculo.sinConfirmar =>
                  l10n.homeAthleteFirstRunBodyNeutral,
              },
              style: theme.textTheme.bodyMedium?.copyWith(
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: 18),
            HomeCTAButton(
              label: l10n.homeAthleteFirstRunCreateCta,
              leadingIcon: TreinoIcon.plus,
              onPressed: () => context.push('/workout/my-routine-editor'),
            ),
            const SizedBox(height: 10),
            // Secondary CTA: la página EXPLORAR de la tab Entrenar, donde
            // viven los planes ya armados.
            //
            // ⚠️ El valor del deep-link sigue siendo `plantillas` a propósito:
            // el copy del tab pasó a "EXPLORAR" en #638 pero la ruta NO se
            // movió, porque hay bookmarks y notificaciones vivas apuntándole
            // (ver `_AthleteWorkout._resolveInitialIndex`). Etiqueta y ruta
            // divergen por diseño — no "arreglar" una para que matchee la otra.
            //
            // `go` y no `push`: es una tab raíz del shell, igual que /coach.
            _FirstRunSecondaryCta(
              label: l10n.homeAthleteFirstRunExplorePlansCta,
              icon: TreinoIcon.dumbbell,
              onPressed: () => context.go('/workout?tab=plantillas'),
            ),
            // Secondary CTA: route to the Coach tab where athletes browse and
            // request a trainer. Se omite —con su separador— cuando el atleta
            // ya tiene PF activo O cuando no se pudo confirmar: ver el dartdoc
            // de la clase.
            if (_ofreceBuscarEntrenador) ...[
              const SizedBox(height: 10),
              _FirstRunSecondaryCta(
                label: l10n.homeAthleteFirstRunFindTrainerCta,
                icon: TreinoIcon.search,
                onPressed: () => context.go('/coach'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Camino secundario del primer arranque: pill outlined, ancho completo, 48
/// de alto. Extraído cuando #636 sumó el tercer camino — los dos secundarios
/// tienen que pesar exactamente lo mismo, y dos copias del mismo
/// `OutlinedButton.styleFrom` se desincronizan a la primera edición.
class _FirstRunSecondaryCta extends StatelessWidget {
  const _FirstRunSecondaryCta({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;

  /// Constante de [TreinoIcon] — nunca un `PhosphorIcons.*` directo.
  final IconData icon;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16, color: palette.accent),
      label: Text(label, style: TextStyle(color: palette.accent)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        side: BorderSide(color: palette.accent.withValues(alpha: 0.6)),
        shape: const StadiumBorder(),
      ),
    );
  }
}

void _maybeShowResumePrompt(
  BuildContext context,
  WidgetRef ref,
  AsyncValue<({Session session, List<SetLog> setLogs})?> next,
) {
  final record = next.valueOrNull;
  if (record == null) return;
  final session = record.session;

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    // ⚠️ Solo si HOME es la pantalla visible.
    //
    // Home queda MONTADA abajo del player. Desde que
    // `activeSessionForUidProvider` es reactivo —para enterarse de un entreno
    // que arrancó el reloj— empezar uno DESDE EL TELÉFONO también lo hace
    // re-emitir, y este aviso saltaba encima del entreno en el que el atleta
    // acababa de entrar, ofreciéndole "continuar o descartar" lo que estaba
    // haciendo. Peor: descartar ahí lo cerraba de verdad.
    //
    // `isCurrent` es false mientras haya cualquier ruta encima, que es
    // exactamente la condición que queremos.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      // ⚠️ El diálogo se cierra SOLO cuando su sujeto deja de existir.
      //
      // Sin esto, terminar el entreno DESDE EL RELOJ dejaba este modal abierto
      // sobre una sesión que ya no está activa. Y como es `barrierDismissible:
      // false`, el atleta quedaba encerrado con dos salidas y las dos malas:
      // CONTINUAR tiraba `StateError` en `_buildResume` (pantalla en blanco), y
      // DESCARTAR le pisaba el volumen y la duración a un entreno YA TERMINADO
      // con datos viejos, dejándolo sin contar. Se reportó como "se borra del
      // historial": no se borraba, se mutilaba.
      //
      // Va como `Consumer` y no como estado de `_AthleteHome` a propósito: el
      // diálogo se apaga solo, sin convertir un `ConsumerWidget` caliente en
      // stateful ni rastrear rutas desde afuera.
      builder: (dialogCtx) => Consumer(
        builder: (consumerCtx, dialogRef, _) {
          dialogRef
              .listen<AsyncValue<({Session session, List<SetLog> setLogs})?>>(
            activeSessionForUidProvider,
            (_, next) {
              // `loading` no cierra: durante un refetch el valor es transitorio
              // y cerrar ahí haría parpadear el diálogo.
              if (next.isLoading) return;
              final vigente = next.valueOrNull?.session.id;
              if (vigente == session.id) return;
              if (dialogCtx.mounted) {
                Navigator.of(dialogCtx, rootNavigator: true).pop();
              }
            },
          );
          return _resumeModal(context, ref, dialogCtx, session, record);
        },
      ),
    );
  });
}

/// El modal en sí, extraído para que el `Consumer` de arriba quede legible.
Widget _resumeModal(
  BuildContext context,
  WidgetRef ref,
  BuildContext dialogCtx,
  Session session,
  ({Session session, List<SetLog> setLogs}) record,
) {
  return ResumeSessionModal(
    session: session,
    onContinue: () {
      Navigator.of(dialogCtx, rootNavigator: true).pop();
      context.push('/workout/session/resume/${session.id}');
    },
    onDiscard: () async {
      final repo = ref.read(sessionRepositoryProvider);
      // Carrera: el atleta puede tocar DESCARTAR en el mismo instante en
      // que el reloj termina el entreno. Sin esta relectura, `finish()`
      // pisaría los totales de una sesión ya cerrada. El cierre automático
      // del diálogo cubre el caso normal; esto cubre el toque simultáneo.
      final vigente = await repo.getActive(session.uid).catchError(
            (_) => null,
          );
      if (vigente == null || vigente.id != session.id) {
        if (dialogCtx.mounted) {
          Navigator.of(dialogCtx, rootNavigator: true).pop();
        }
        return;
      }
      // QA-WKT-011: clamp the discarded session's duration with the same
      // policy SessionNotifier uses (recover from the set-log timeline, cap
      // at maxWorkoutDuration) instead of raw wall-clock minutes — a session
      // left open overnight was persisting durationMin well over 480.
      final elapsedSecs = sanitizedActiveSessionElapsedSeconds(
        session: session,
        setLogs: record.setLogs,
        now: DateTime.now(),
      );
      final durationMin = elapsedSecs <= 0 ? 1 : (elapsedSecs + 59) ~/ 60;
      try {
        await repo
            .finish(
              uid: session.uid,
              sessionId: session.id,
              finishedAt: DateTime.now(),
              totalVolumeKg: _sumVolume(record.setLogs),
              durationMin: durationMin,
              // Sin esto la racha se recalculaba contra el fallback de 1
              // sesión por semana y le pisaba el valor correcto al atleta.
              weeklyTarget: ref.read(weeklyStreakTargetProvider),
            )
            .timeout(const Duration(seconds: 15));
      } catch (_) {
        // QA-WKT-011: the write can throw or (offline) stall indefinitely.
        // Don't leave the barrierDismissible:false dialog stuck with an
        // unhandled exception — close it and surface a retryable error.
        if (dialogCtx.mounted) {
          Navigator.of(dialogCtx, rootNavigator: true).pop();
        }
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppL10n.of(context).workoutDiscardError),
            ),
          );
        }
        return;
      }
      // _AthleteHome may have been disposed during the finish() write
      // (user navigated away). Invalidating through a torn-down ref throws,
      // so guard on the host context before touching ref again.
      if (!context.mounted) return;
      if (dialogCtx.mounted) {
        Navigator.of(dialogCtx, rootNavigator: true).pop();
      }
      ref.invalidate(activeSessionForUidProvider);
      // El reloj no tiene listeners: sin este aviso descartar acá cerraba
      // la sesión en Firestore y en el teléfono, pero la muñeca se quedaba
      // con la pantalla de entreno abierta sobre algo que ya no existe.
      // El aviso desde `SessionNotifier` no cubre este camino: acá el
      // notifier ni siquiera está vivo.
      unawaited(
        ref.read(watchNudgeServiceProvider).nudge(
              reason: WatchNudgeService.reasonWorkoutFinished,
            ),
      );
    },
  );
}

double _sumVolume(List<SetLog> logs) =>
    logs.fold<double>(0, (acc, l) => acc + l.reps * l.weightKg);

/// Private placeholder that occupies the same 56 px height as [HomeHeader]
/// during [AsyncLoading], preventing a layout jump (REQ-HOME-PROVIDER-003).
class _HomeHeaderSkeleton extends StatelessWidget {
  const _HomeHeaderSkeleton();

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    // Announce the loading state so screen readers don't land on a silent,
    // empty 56px surface while the profile header resolves.
    //
    // Sin TreinoShimmer a propósito (TREINO Motion PR2): este skeleton es un
    // spacer transparente sin cajas pintadas — con BlendMode.srcATop el
    // barrido no pintaría ni un píxel, pero el controller correría igual
    // (createShader + ShaderMaskLayer por frame). Trabajo muerto.
    return Semantics(
      label: l10n.commonLoading,
      liveRegion: true,
      child: const SizedBox(height: 56),
    );
  }
}
