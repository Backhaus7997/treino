import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_analytics_service.dart';

/// Smoke test del contrato del [AnalyticsService] vía el fake.
///
/// No testea FirebaseAnalyticsService (requiere Firebase init real). Acá
/// validamos que cada método del contrato (1) emite el event name esperado,
/// y (2) propaga los parámetros correctos. Si en el futuro alguien cambia
/// un event name sin actualizar el resto del codebase, los call-site tests
/// arriba se rompen — pero ESTE test es la canary que falla primero.
void main() {
  group('AnalyticsService contract (via FakeAnalyticsService)', () {
    test('logRoutineStarted captura event + params', () async {
      final f = FakeAnalyticsService();
      await f.logRoutineStarted(routineId: 'r1', routineName: 'Mi Plan');
      expect(f.events, ['routine_started']);
      expect(f.calls.single.params,
          {'routine_id': 'r1', 'routine_name': 'Mi Plan'});
    });

    test('logRoutineStarted sin routineName omite la key', () async {
      final f = FakeAnalyticsService();
      await f.logRoutineStarted(routineId: 'r1');
      expect(f.calls.single.params, {'routine_id': 'r1'});
    });

    test('logRoutineFinished captura los 3 campos', () async {
      final f = FakeAnalyticsService();
      await f.logRoutineFinished(
        routineId: 'r1',
        sessionId: 's1',
        durationSeconds: 1234,
      );
      expect(f.events, ['routine_finished']);
      expect(f.calls.single.params, {
        'routine_id': 'r1',
        'session_id': 's1',
        'duration_seconds': 1234,
      });
    });

    test('logPlanAssigned captura assignedBy/assignedTo', () async {
      final f = FakeAnalyticsService();
      await f.logPlanAssigned(
        routineId: 'r1',
        assignedBy: 'trainer-1',
        assignedTo: 'athlete-2',
      );
      expect(f.events, ['plan_assigned']);
      expect(f.calls.single.params, {
        'routine_id': 'r1',
        'assigned_by': 'trainer-1',
        'assigned_to': 'athlete-2',
      });
    });

    test('logLinkRequested', () async {
      final f = FakeAnalyticsService();
      await f.logLinkRequested(trainerId: 't1', athleteId: 'a1');
      expect(f.events, ['link_requested']);
    });

    test('logLinkAccepted', () async {
      final f = FakeAnalyticsService();
      await f.logLinkAccepted(linkId: 'L1');
      expect(f.events, ['link_accepted']);
      expect(f.calls.single.params, {'link_id': 'L1'});
    });

    test('logChatMessageSent', () async {
      final f = FakeAnalyticsService();
      await f.logChatMessageSent(chatId: 'c1', senderId: 's1');
      expect(f.events, ['chat_message_sent']);
    });

    test('logAppointmentCreated', () async {
      final f = FakeAnalyticsService();
      await f.logAppointmentCreated(
        appointmentId: 'a1',
        trainerId: 't1',
        athleteId: 'al1',
      );
      expect(f.events, ['appointment_created']);
      expect(f.calls.single.params, {
        'appointment_id': 'a1',
        'trainer_id': 't1',
        'athlete_id': 'al1',
      });
    });

    test('multiple calls accumulate in order', () async {
      final f = FakeAnalyticsService();
      await f.logRoutineStarted(routineId: 'r1');
      await f.logChatMessageSent(chatId: 'c1', senderId: 's1');
      await f.logLinkAccepted(linkId: 'L1');
      expect(
          f.events, ['routine_started', 'chat_message_sent', 'link_accepted']);
    });
  });
}
