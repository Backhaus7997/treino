import 'package:firebase_analytics/firebase_analytics.dart';
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
/// `session_start`, `screen_view`, `app_open`, `first_open`, etc.
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
}

/// Provider Riverpod — los call sites hacen
/// `ref.read(analyticsServiceProvider).logFoo(...)`.
///
/// Tests override con `FakeAnalyticsService`.
final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  return FirebaseAnalyticsService(FirebaseAnalytics.instance);
});
