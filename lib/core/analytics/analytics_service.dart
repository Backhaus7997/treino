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

  /// `AppointmentRepository.book` — cita propuesta/confirmada.
  Future<void> logAppointmentCreated({
    required String appointmentId,
    required String trainerId,
    required String athleteId,
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
}

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
    required String appointmentId,
    required String trainerId,
    required String athleteId,
  }) =>
      _analytics.logEvent(
        name: 'appointment_created',
        parameters: {
          'appointment_id': appointmentId,
          'trainer_id': trainerId,
          'athlete_id': athleteId,
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
    required String appointmentId,
    required String trainerId,
    required String athleteId,
  }) async {}

  @override
  Future<void> logScreenViewed({required String route}) async {}

  @override
  Future<void> logSubTabViewed({
    required String surface,
    required String tab,
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
