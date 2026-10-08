import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../coach_hub/application/cf_providers.dart'
    show cloudFunctionsProvider;
import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../data/session_share_repository.dart';
import '../data/trainer_link_promotion_service.dart';
import '../data/trainer_link_repository.dart';
import '../domain/trainer_link.dart';
import '../domain/trainer_link_status.dart';

final trainerLinkRepositoryProvider = Provider<TrainerLinkRepository>(
  (ref) => TrainerLinkRepository(firestore: ref.watch(firestoreProvider)),
);

/// Server-authoritative `accept` — replaces
/// `trainerLinkRepositoryProvider.accept()` (Fase 7, PR4, slice 2).
final trainerLinkPromotionServiceProvider =
    Provider<TrainerLinkPromotionService>(
  (ref) => TrainerLinkPromotionService(
    functions: ref.watch(cloudFunctionsProvider),
  ),
);

/// Lista de vínculos donde el usuario actuó como PF.
///
/// Preferí [trainerLinksStreamProvider] — entrega los mismos datos pero como
/// stream real-time, lo cual permite que el Coach Hub refleje transiciones
/// (pause/resume/terminate/accept) sin un `ref.invalidate` manual.
///
/// Este provider queda exportado por back-compat de consumidores fuera del
/// dashboard. Se elimina cuando esos consumidores migren al stream.
@Deprecated(
  'Use trainerLinksStreamProvider for real-time updates. '
  'See ADR-CHLM-03 (coach-hub-link-management).',
)
final linksForTrainerProvider =
    FutureProvider.autoDispose.family<List<TrainerLink>, String>(
  (ref, trainerId) async {
    if (trainerId.isEmpty) return const [];
    return ref.read(trainerLinkRepositoryProvider).listForTrainer(trainerId);
  },
);

/// Lista de vínculos donde el usuario actuó como atleta.
final linksForAthleteProvider =
    FutureProvider.autoDispose.family<List<TrainerLink>, String>(
  (ref, athleteId) async {
    if (athleteId.isEmpty) return const [];
    return ref.read(trainerLinkRepositoryProvider).listForAthlete(athleteId);
  },
);

/// Cuánto puede esperar un CONSUMIDOR a que conteste el servidor.
///
/// Los providers de acá NO la usan: con [TrainerLinkRepository.watchForAthlete]
/// descartando los resultados vacíos que vienen de caché, un dispositivo que no
/// llega al servidor se queda en `AsyncLoading`, y eso es lo correcto — un
/// `AsyncData(null)` significa "el servidor dijo que no tenés vínculo activo",
/// nunca "nos cansamos de esperar".
///
/// Al principio esta espera vivía adentro de los providers y emitía la lista
/// vacía al vencerse. Eso convertía un timeout en una ausencia CONFIRMADA:
/// `AthleteCoachView` mandaba a discovery a un alumno vinculado, el entitlement
/// le sacaba el acceso derivado del Coach, y los `.future` resolvían con "no
/// hay vínculo". El bug original, otra vez, por otra puerta. Lo encontró Codex
/// en el PR #1109.
///
/// La espera pasó a los DOS consumidores que no pueden quedarse colgados —los
/// que hacen `await ...future` adentro de un handler de usuario— porque ahí sí
/// se puede representar "no pude confirmar" sin mentirle a nadie más.
const kEsperaDelServidorDeVinculo = Duration(seconds: 8);

/// Vínculo activo del atleta actual con su PF, o null si no tiene.
/// Si hay múltiples activos (no debería pasar — un atleta solo se vincula
/// con UN PF a la vez en Etapa 1), devolvemos el más reciente.
///
/// Es `StreamProvider` y no `FutureProvider` a propósito. Con un `.get()` de
/// una sola oportunidad, una caché fría devolvía lista vacía —no error—, el
/// provider daba `null` por la rama BUENA de `.when(data:)`, y el gate de
/// `/coach/agenda` y `/coach/nutricion` le decía "necesitás un vínculo activo"
/// a alguien que lo tenía, sin forma de recuperarse: `autoDispose` hacía que
/// cada reentrada disparara otro `.get()` que podía volver a caer en la caché.
final currentAthleteLinkProvider =
    StreamProvider.autoDispose<TrainerLink?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream<TrainerLink?>.value(null);
  // SIN la ventana de gracia que sí tiene el lado del PF, y a propósito.
  //
  // Allá arregla un parpadeo real: el roster de Alumnos se soltaba al salir de
  // la sección y volver arrancaba en `AsyncLoading`. Acá no hace falta, porque
  // `watchForAthlete` sólo descarta las snapshots vacías: apenas el vínculo
  // está en la caché local, una suscripción nueva llega CON documentos, pasa
  // la guarda y resuelve en un frame. La caché ya da la continuidad.
  //
  // Y el `keepAlive` no es gratis: impide el dispose, así que el `Timer` le
  // sobrevive al widget. Cualquier test que monte un árbol que toque este
  // provider —el shell entero, sin ir más lejos— muere con `!timersPending`
  // sin tener nada que ver con vínculos. Medido:
  // `router_post_login_bottom_bar_test.dart` se cayó por esto.
  return ref
      .read(trainerLinkRepositoryProvider)
      .watchForAthlete(uid, statuses: {TrainerLinkStatus.active}).map(
    // watchForAthlete viene ordenado por requestedAt DESC.
    (links) => links.isEmpty ? null : links.first,
  );
});

/// Vínculo NO terminado del atleta actual: `pending`, `active` o `paused`, o
/// null si no tiene ninguno.
///
/// A diferencia de [currentAthleteLinkProvider] (solo `active`), este incluye
/// `pending` y `paused`. Lo consume la vista de coach del atleta para decidir
/// si mostrar la card de estado (SOLICITUD ENVIADA / VÍNCULO PAUSADO) o la
/// discovery, y el guard anti-duplicados de "PEDIR VÍNCULO". QA-COA-001: con el
/// provider active-only, una solicitud `pending` (o un vínculo `paused`) hacía
/// que la vista devolviera null → caía a discovery, la card quedaba muerta, y
/// el guard no veía la solicitud en curso → solicitudes duplicadas ilimitadas.
///
/// NO lo usan los consumidores que requieren específicamente el vínculo activo
/// (chat, reviews, mi_cuota, agenda, workout) — esos siguen en
/// [currentAthleteLinkProvider].
///
/// Si hubiera varios no-terminados (no debería — un atleta se vincula con UN PF
/// a la vez), devuelve el más reciente (requestedAt DESC).
///
/// Stream por el mismo motivo que [currentAthleteLinkProvider]: éste es el que
/// consume la vista que DIBUJA los botones de agenda/nutrición/archivos, así
/// que dejarlo en `.get()` movía el bug de lugar en vez de arreglarlo — la
/// pantalla habría caído a discovery con una solicitud `pending` viva.
final currentAthleteLinkAnyStatusProvider =
    StreamProvider.autoDispose<TrainerLink?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream<TrainerLink?>.value(null);
  // Ver [currentAthleteLinkProvider]: tampoco lleva ventana de gracia.
  return ref.read(trainerLinkRepositoryProvider).watchForAthlete(
    uid,
    statuses: {
      TrainerLinkStatus.pending,
      TrainerLinkStatus.active,
      TrainerLinkStatus.paused,
    },
  ).map((links) => links.isEmpty ? null : links.first);
});

/// Ventana en la que el stream de vínculos SOBREVIVE a que lo suelten.
///
/// Es navegación, no caché de datos: moverse entre secciones del Coach Hub no
/// puede costar una recarga.
const _kVentanaDeGracia = Duration(minutes: 5);

/// Stream real-time de los vínculos del PF actual. Lo consume el dashboard
/// del PF (Etapa 3) y el roster de Alumnos.
///
/// `autoDispose` CON ventana de gracia. Con `autoDispose` pelado, salir de
/// Alumnos destruía el provider y volver arrancaba en `AsyncLoading` sin
/// valor: la pantalla dibujaba el esqueleto, el `AnimatedSwitcher` de
/// `TreinoStateSwitcher` hacía un cross-fade, Firestore resolvía DE CACHÉ en
/// un frame, y venía el segundo cross-fade más los cuatro
/// `TreinoFadeSlideIn` escalonados del contenido.
///
/// Eso es el parpadeo que reportó el PF, y pasaba en CADA entrada a la
/// sección — no sólo en la primera. Con la ventana, volver encuentra el valor
/// ya puesto y la pantalla entra derecho en `data`: una sola animación de
/// entrada, la que el diseño quería.
///
/// El esqueleto sigue estando para la carga de verdad, que es cuando dice algo.
final trainerLinksStreamProvider =
    StreamProvider.autoDispose<List<TrainerLink>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return const Stream.empty();
  // El `keepAlive` se toma SIEMPRE y lo suelta el timer, no el último oyente:
  // si lo soltara el oyente, volver a entrar antes de los 5 minutos seguiría
  // encontrando el provider destruido y no habríamos arreglado nada.
  final link = ref.keepAlive();
  final timer = Timer(_kVentanaDeGracia, link.close);
  ref.onDispose(timer.cancel);
  return ref.read(trainerLinkRepositoryProvider).watchForTrainer(uid);
});

/// Privacy-grant repository — wraps the `session_shares/{athleteId}` doc.
/// Used by the athlete's "Compartir con mi PF" toggle to keep the Firestore
/// security grant in sync with `trainer_links.sharedWithTrainer`.
final sessionShareRepositoryProvider = Provider<SessionShareRepository>(
  (ref) => SessionShareRepository(firestore: ref.watch(firestoreProvider)),
);
