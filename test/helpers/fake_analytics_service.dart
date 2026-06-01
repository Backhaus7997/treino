import 'package:treino/core/analytics/analytics_service.dart';

/// Fake AnalyticsService para widget tests — captura cada llamada en
/// `events` para que el test pueda assertear, sin hacer ningún I/O real
/// contra Firebase (que no está inicializado en `flutter test`).
///
/// Override de uso típico:
///
/// ```dart
/// final fakeAnalytics = FakeAnalyticsService();
/// ...
/// ProviderScope(
///   overrides: [analyticsServiceProvider.overrideWithValue(fakeAnalytics)],
///   ...
/// )
/// ...
/// expect(fakeAnalytics.events, contains('routine_started'));
/// ```
class FakeAnalyticsService implements AnalyticsService {
  /// Lista de event names capturados, en orden de invocación.
  final List<String> events = [];

  /// Lista de (eventName, params) capturados — útil cuando el test
  /// necesita assertear los parámetros además del nombre.
  final List<({String name, Map<String, Object?> params})> calls = [];

  @override
  Future<void> logRoutineStarted({
    required String routineId,
    String? routineName,
  }) async {
    events.add('routine_started');
    calls.add((name: 'routine_started', params: {
      'routine_id': routineId,
      if (routineName != null) 'routine_name': routineName,
    }));
  }

  @override
  Future<void> logRoutineFinished({
    required String routineId,
    required String sessionId,
    required int durationSeconds,
  }) async {
    events.add('routine_finished');
    calls.add((name: 'routine_finished', params: {
      'routine_id': routineId,
      'session_id': sessionId,
      'duration_seconds': durationSeconds,
    }));
  }

  @override
  Future<void> logPlanAssigned({
    required String routineId,
    required String assignedBy,
    required String assignedTo,
  }) async {
    events.add('plan_assigned');
    calls.add((name: 'plan_assigned', params: {
      'routine_id': routineId,
      'assigned_by': assignedBy,
      'assigned_to': assignedTo,
    }));
  }

  @override
  Future<void> logLinkRequested({
    required String trainerId,
    required String athleteId,
  }) async {
    events.add('link_requested');
    calls.add((name: 'link_requested', params: {
      'trainer_id': trainerId,
      'athlete_id': athleteId,
    }));
  }

  @override
  Future<void> logLinkAccepted({required String linkId}) async {
    events.add('link_accepted');
    calls.add((name: 'link_accepted', params: {'link_id': linkId}));
  }

  @override
  Future<void> logChatMessageSent({
    required String chatId,
    required String senderId,
  }) async {
    events.add('chat_message_sent');
    calls.add((name: 'chat_message_sent', params: {
      'chat_id': chatId,
      'sender_id': senderId,
    }));
  }

  @override
  Future<void> logAppointmentCreated({
    required String appointmentId,
    required String trainerId,
    required String athleteId,
  }) async {
    events.add('appointment_created');
    calls.add((name: 'appointment_created', params: {
      'appointment_id': appointmentId,
      'trainer_id': trainerId,
      'athlete_id': athleteId,
    }));
  }
}
