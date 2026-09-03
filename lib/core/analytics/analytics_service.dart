import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Servicio centralizado de eventos analytics.
///
/// Una sola fuente de verdad para los nombres de eventos + parámetros.
/// Los call sites llaman métodos nombrados (`logRoutineStarted(...)`) en lugar
/// de pasar strings sueltos — eso evita typos en event names y facilita
/// agregar/cambiar parámetros sin tocar cada call site.
///
/// Para tests: override `analyticsServiceProvider` con [FakeAnalyticsService]
/// y assertear sobre `events` capturados.
///
/// Eventos auto-trackeados por Firebase Analytics que NO disparamos acá:
/// `session_start`, `app_open`, `first_open`, etc.
///
/// `screen_view` NO está en esa lista, aunque antes lo estuviera: el
/// auto-tracking de Firebase cuenta pantallas NATIVAS, y toda una app Flutter
/// es una sola. Lo emite `RouteAnalytics` (ver `route_analytics.dart`).
abstract class AnalyticsService {
  /// Tap "EMPEZAR" en RoutineDetail — el atleta arrancó una rutina (intent).
  Future<void> logRoutineStarted({
    required String routineId,
    String? routineName,
  });

  /// `SessionRepository.finish` — sesión cerrada exitosamente.
  Future<void> logRoutineFinished({
    required String routineId,
    required String sessionId,
    required int durationSeconds,
  });

  /// Se guardó una rutina NUEVA en `routines` — desde cualquier editor y por
  /// cualquier actor. Es el evento que dice qué FORMA tienen las rutinas que
  /// la gente arma de verdad; sin él, "¿cuánta gente querría un segundo día?"
  /// no se puede responder.
  ///
  /// [source] separa al alumno suelto (el único segmento que un paywall
  /// tocaría) del ruido del PF. Las asignadas por un profe se cuentan igual y
  /// se filtran en el reporte — omitirlas dejaría el evento ciego a la mitad
  /// de las rutinas y sesgaría la comparación.
  ///
  /// Solo contadores y un enum: nada que identifique a una persona.
  Future<void> logRoutineCreated({
    required RoutineCreationSource source,
    required int daysCount,
    required int weeksCount,
  });

  /// "Agregar día" en el editor — la rutina pasó de N a N+1 días.
  ///
  /// [daysCount] es el total DESPUÉS de agregar. Es el instante exacto en que
  /// un tope de días mordería, por eso se mide antes de que exista ninguno.
  /// Se emite también mientras la rutina todavía no se guardó: la fricción
  /// ocurre al agregar, no al guardar.
  Future<void> logRoutineDayAdded({
    required RoutineCreationSource source,
    required int daysCount,
  });

  /// Lo mismo que [logRoutineDayAdded], sobre el eje de semanas.
  ///
  /// [weeksCount] es el total DESPUÉS de agregar. En el editor web las semanas
  /// son un stepper numérico, así que un salto de 1 a 4 es UN evento con
  /// `weeks_count: 4`, no tres.
  Future<void> logRoutineWeekAdded({
    required RoutineCreationSource source,
    required int weeksCount,
  });

  /// `RoutineRepository.createAssigned` — un PF asignó un plan a un atleta.
  Future<void> logPlanAssigned({
    required String routineId,
    required String assignedBy,
    required String assignedTo,
  });

  /// `TrainerLinkRepository.request` — atleta pidió vínculo a un PF.
  Future<void> logLinkRequested({
    required String trainerId,
    required String athleteId,
  });

  /// `TrainerLinkRepository.accept` — PF aceptó un request de vínculo.
  Future<void> logLinkAccepted({required String linkId});

  /// `ChatRepository.sendMessage` — mensaje enviado en chat 1-1.
  Future<void> logChatMessageSent({
    required String chatId,
    required String senderId,
  });

  /// El PF agendó sesión(es) con un alumno.
  ///
  /// El docstring anterior decía `AppointmentRepository.book`, y eso apuntaba
  /// a un método MUERTO: `book()` es el auto-booking del atleta, sin
  /// llamadores en `lib/` desde #831 y con su rama de reactivación ya cerrada
  /// por reglas. Los dos creadores vivos son `createByTrainer` y
  /// `createRecurringByTrainer`.
  ///
  /// [appointmentId] es `null` para una serie recurrente: ahí no hay UNA cita,
  /// y `createRecurringByTrainer` devuelve sólo cuántas creó. Ese es también
  /// el motivo de [occurrences]: una serie de 8 semanas son 8 sesiones
  /// agendadas, y contarlas como 1 subreporta la adopción de la feature
  /// justo en el caso donde más se usa.
  Future<void> logAppointmentCreated({
    String? appointmentId,
    required String trainerId,
    required String athleteId,
    int occurrences = 1,
  });

  /// Una ruta quedó visible. Lo dispara `RouteAnalytics` en cada navegación.
  ///
  /// [route] es el PATRÓN de go_router (`/coach/exercise/:id`), no la ruta
  /// concreta (`/coach/exercise/abc123`). Mandar la concreta haría explotar la
  /// cardinalidad del evento: un valor distinto por cada id, y ningún reporte
  /// agregable.
  Future<void> logScreenViewed({required String route});

  /// Una página de sub-navegación quedó visible.
  ///
  /// El `screen_view` de rutas no alcanza para esto: FEED y
  /// RANKINGS son las dos la ruta `/feed`, y TU ENTRENO y PLANTILLAS las dos
  /// `/workout`. Son páginas de un `TabBarView`, no rutas — para el router
  /// serían la misma pantalla.
  ///
  /// [surface] es el contenedor (`feed`, `workout`, `feed_segments`) y [tab]
  /// la página dentro de él (`rankings`, `plantillas`, `gym`...).
  Future<void> logSubTabViewed({
    required String surface,
    required String tab,
  });

  /// Una escritura del PF rebotó con `permission-denied`.
  ///
  /// **Es la única señal server-visible que va a existir de esto.** Firestore
  /// no loguea en ningún lado consultable las denegaciones de reglas, y el
  /// Coach Hub web no inicializa Crashlytics (`main_coach_hub.dart`). Si este
  /// evento no lo cuenta, el primer incidente del enforcement es invisible y
  /// nos enteramos por WhatsApp.
  ///
  /// Por eso los campos son los que responden las preguntas del día del
  /// incidente, no los que salían gratis:
  ///
  /// - [trainerId] — CUÁNTOS PF distintos y CUÁLES. Va explícito porque la app
  ///   nunca llama a `setUserId`: el `user_pseudo_id` que Firebase agrega solo
  ///   identifica la INSTALACIÓN, así que sin este campo no se pueden contar
  ///   PF únicos ni cruzar el rebote contra su `subscription` en Firestore.
  /// - [athleteId] — sobre qué alumno rebotó. Distingue "un alumno puntual"
  ///   de "todos los del PF".
  /// - [collection] — qué se estaba escribiendo (`routines`, …). Separa "una
  ///   cláusula puntual quedó mal" de "el PF está frenado entero".
  /// - [operation] — `create` o `update`. No es lo mismo no poder tomar
  ///   trabajo nuevo que no poder tocar lo que ya tenía; lo segundo es mucho
  ///   más grave y la respuesta operativa es otra.
  /// - [surface] — desde dónde (`routine_editor_web`, …). La misma colección
  ///   se escribe desde web y desde móvil, y el arreglo no es el mismo.
  /// - [athleteEntitlement] — `blocked` si el alumno figuraba en
  ///   `users/{trainerId}.blockedAthleteIds` cuando rebotó, `entitled` si no,
  ///   `unknown` si ese doc todavía no había cargado, `not_applicable` si la
  ///   escritura no era sobre ningún alumno (una plantilla del PF). Es el
  ///   campo que dice si el paywall EXPLICA la denegación: un pico de
  ///   `entitled` no es un problema de cobro, es una regla rota, y ahí mirar
  ///   facturación es perder el día.
  Future<void> logPaywallWriteDenied({
    required String trainerId,
    required String athleteId,
    required String collection,
    required String operation,
    required String surface,
    required String athleteEntitlement,
  });
}

/// Quién creó la rutina y desde dónde — la dimensión `source` de los tres
/// eventos de forma de rutina (`routine_created`, `routine_day_added`,
/// `routine_week_added`).
///
/// No es `RoutineSource`: ese enum es el contrato del DOCUMENTO en Firestore y
/// colapsa "armada de cero" y "usar como base" en un mismo `user-created`.
/// Acá esa diferencia ES el dato: un alumno que copia una plantilla de 4 días
/// no chocaría contra un límite igual que uno que armó 4 días a mano.
///
/// Los valores van en snake_case como todo parámetro de este archivo.
enum RoutineCreationSource {
  /// Alumno, editor en blanco (`SelfCreating`).
  self('self'),

  /// Alumno, "Usar como base" sobre una plantilla (`SelfCustomizing`, #647).
  selfFromTemplate('self_from_template'),

  /// PF asignando a un alumno: editor móvil o web, preview de Excel, o
  /// "Asignar a alumno" sobre una plantilla propia.
  trainerAssigned('trainer_assigned'),

  /// PF guardando una plantilla propia sin alumno (`TrainerTemplating`).
  trainerTemplate('trainer_template');

  const RoutineCreationSource(this.wireName);

  /// Valor que viaja en el parámetro `source`.
  final String wireName;
}

/// El nombre del evento, en UN solo lugar.
///
/// El resto de los eventos de este archivo tiene el string escrito dos veces
/// —en [FirebaseAnalyticsService] y en el `FakeAnalyticsService` de los
/// tests— y sólo la copia del fake queda asserteada. Para los demás eso es un
/// riesgo tolerable; para éste no: es la ÚNICA señal server-visible del
/// enforcement, así que un typo en la copia que shipea lo deja fuera de
/// BigQuery con la suite entera en verde, y nadie se entera hasta el día del
/// incidente. Con la constante compartida, el test que pinea el literal pinea
/// también lo que se manda de verdad.
const String kPaywallWriteDeniedEvent = 'paywall_write_denied';

/// Implementación real basada en Firebase Analytics.
class FirebaseAnalyticsService implements AnalyticsService {
  FirebaseAnalyticsService(this._analytics);

  final FirebaseAnalytics _analytics;

  @override
  Future<void> logRoutineStarted({
    required String routineId,
    String? routineName,
  }) =>
      _analytics.logEvent(
        name: 'routine_started',
        parameters: {
          'routine_id': routineId,
          if (routineName != null) 'routine_name': routineName,
        },
      );

  @override
  Future<void> logRoutineFinished({
    required String routineId,
    required String sessionId,
    required int durationSeconds,
  }) =>
      _analytics.logEvent(
        name: 'routine_finished',
        parameters: {
          'routine_id': routineId,
          'session_id': sessionId,
          'duration_seconds': durationSeconds,
        },
      );

  @override
  Future<void> logRoutineCreated({
    required RoutineCreationSource source,
    required int daysCount,
    required int weeksCount,
  }) =>
      _analytics.logEvent(
        name: 'routine_created',
        parameters: {
          'source': source.wireName,
          'days_count': daysCount,
          'weeks_count': weeksCount,
        },
      );

  @override
  Future<void> logRoutineDayAdded({
    required RoutineCreationSource source,
    required int daysCount,
  }) =>
      _analytics.logEvent(
        name: 'routine_day_added',
        parameters: {
          'source': source.wireName,
          'days_count': daysCount,
        },
      );

  @override
  Future<void> logRoutineWeekAdded({
    required RoutineCreationSource source,
    required int weeksCount,
  }) =>
      _analytics.logEvent(
        name: 'routine_week_added',
        parameters: {
          'source': source.wireName,
          'weeks_count': weeksCount,
        },
      );

  @override
  Future<void> logPlanAssigned({
    required String routineId,
    required String assignedBy,
    required String assignedTo,
  }) =>
      _analytics.logEvent(
        name: 'plan_assigned',
        parameters: {
          'routine_id': routineId,
          'assigned_by': assignedBy,
          'assigned_to': assignedTo,
        },
      );

  @override
  Future<void> logLinkRequested({
    required String trainerId,
    required String athleteId,
  }) =>
      _analytics.logEvent(
        name: 'link_requested',
        parameters: {
          'trainer_id': trainerId,
          'athlete_id': athleteId,
        },
      );

  @override
  Future<void> logLinkAccepted({required String linkId}) => _analytics.logEvent(
        name: 'link_accepted',
        parameters: {'link_id': linkId},
      );

  @override
  Future<void> logChatMessageSent({
    required String chatId,
    required String senderId,
  }) =>
      _analytics.logEvent(
        name: 'chat_message_sent',
        parameters: {
          'chat_id': chatId,
          'sender_id': senderId,
        },
      );

  @override
  Future<void> logAppointmentCreated({
    String? appointmentId,
    required String trainerId,
    required String athleteId,
    int occurrences = 1,
  }) =>
      _analytics.logEvent(
        name: 'appointment_created',
        parameters: {
          if (appointmentId != null) 'appointment_id': appointmentId,
          'trainer_id': trainerId,
          'athlete_id': athleteId,
          'occurrences': occurrences,
          // Deriva de `occurrences`, pero se manda explícito para que
          // segmentar en la consola sea un filtro y no una fórmula.
          //
          // Y va como STRING, no como bool: `firebase_analytics` sólo acepta
          // `String` o `num` como valor de parámetro
          // (`_assertParameterTypesAreCorrect`, firebase_analytics 11.6.0).
          // Un bool rompía el evento entero — en debug por el assert, y en
          // release en silencio, porque los asserts se strippean.
          'booking_type': occurrences > 1 ? 'series' : 'single',
        },
      );

  /// Usa `logScreenView` y no `logEvent('screen_view')`: es el helper tipado
  /// del SDK y el que alimenta los reportes de pantallas de la consola.
  @override
  Future<void> logScreenViewed({required String route}) =>
      _analytics.logScreenView(screenName: route);

  @override
  Future<void> logSubTabViewed({
    required String surface,
    required String tab,
  }) =>
      _analytics.logEvent(
        name: 'sub_tab_viewed',
        parameters: {
          'surface': surface,
          'tab': tab,
        },
      );

  @override
  Future<void> logPaywallWriteDenied({
    required String trainerId,
    required String athleteId,
    required String collection,
    required String operation,
    required String surface,
    required String athleteEntitlement,
  }) =>
      _analytics.logEvent(
        name: kPaywallWriteDeniedEvent,
        parameters: {
          'trainer_id': trainerId,
          'athlete_id': athleteId,
          'collection': collection,
          'operation': operation,
          'surface': surface,
          'athlete_entitlement': athleteEntitlement,
        },
      );
}

/// [AnalyticsService] que no hace nada.
///
/// Se usa cuando no hay una app de Firebase inicializada, que en la práctica
/// significa `flutter test`. Ver [analyticsServiceProvider].
class NoopAnalyticsService implements AnalyticsService {
  const NoopAnalyticsService();

  @override
  Future<void> logRoutineStarted({
    required String routineId,
    String? routineName,
  }) async {}

  @override
  Future<void> logRoutineFinished({
    required String routineId,
    required String sessionId,
    required int durationSeconds,
  }) async {}

  @override
  Future<void> logRoutineCreated({
    required RoutineCreationSource source,
    required int daysCount,
    required int weeksCount,
  }) async {}

  @override
  Future<void> logRoutineDayAdded({
    required RoutineCreationSource source,
    required int daysCount,
  }) async {}

  @override
  Future<void> logRoutineWeekAdded({
    required RoutineCreationSource source,
    required int weeksCount,
  }) async {}

  @override
  Future<void> logPlanAssigned({
    required String routineId,
    required String assignedBy,
    required String assignedTo,
  }) async {}

  @override
  Future<void> logLinkRequested({
    required String trainerId,
    required String athleteId,
  }) async {}

  @override
  Future<void> logLinkAccepted({required String linkId}) async {}

  @override
  Future<void> logChatMessageSent({
    required String chatId,
    required String senderId,
  }) async {}

  @override
  Future<void> logAppointmentCreated({
    String? appointmentId,
    required String trainerId,
    required String athleteId,
    int occurrences = 1,
  }) async {}

  @override
  Future<void> logScreenViewed({required String route}) async {}

  @override
  Future<void> logSubTabViewed({
    required String surface,
    required String tab,
  }) async {}

  @override
  Future<void> logPaywallWriteDenied({
    required String trainerId,
    required String athleteId,
    required String collection,
    required String operation,
    required String surface,
    required String athleteEntitlement,
  }) async {}
}

/// Instancia de Firebase Analytics.
///
/// Existe como provider propio para que los tests puedan overridearla sin
/// tener que inicializar Firebase.
final firebaseAnalyticsProvider = Provider<FirebaseAnalytics>((ref) {
  return FirebaseAnalytics.instance;
});

/// Provider Riverpod — los call sites hacen
/// `ref.read(analyticsServiceProvider).logFoo(...)`.
///
/// Tests override con `FakeAnalyticsService` cuando quieren assertear sobre
/// los eventos. Los que NO se ocupan de analytics no necesitan hacer nada:
/// sin app de Firebase esto devuelve un [NoopAnalyticsService].
///
/// Ese fallback no es cosmético. `FirebaseAnalytics.instance` tira
/// `[core/no-app]` si no hay app inicializada, y en `flutter test` nunca la
/// hay. Antes daba igual, porque analytics sólo se tocaba desde acciones de
/// negocio que los widget tests no disparan. Desde #666 hay widgets que
/// loguean AL MONTARSE (`SubTabAnalytics`), así que sin esta guarda cualquier
/// test que pumpee Feed o Entrenar reventaría — fueron 82 de una.
///
/// En producción `main.dart` hace `Firebase.initializeApp()` bastante antes de
/// `runApp`, así que para cuando alguien lee este provider siempre hay app.
final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  if (Firebase.apps.isEmpty) return const NoopAnalyticsService();
  return FirebaseAnalyticsService(ref.watch(firebaseAnalyticsProvider));
});
