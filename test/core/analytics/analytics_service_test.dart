import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/analytics/analytics_service.dart';

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

    test('logAppointmentCreated — cita suelta', () async {
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
        'occurrences': 1,
        'booking_type': 'single',
      });
    });

    test('logAppointmentCreated — serie recurrente: sin id, con occurrences',
        () async {
      // `createRecurringByTrainer` devuelve un conteo y ningún id: no hay UNA
      // cita que nombrar. El evento igual tiene que contar N y no 1, o la
      // adopción de la feature se subreporta justo donde más se usa.
      final f = FakeAnalyticsService();
      await f.logAppointmentCreated(
        trainerId: 't1',
        athleteId: 'al1',
        occurrences: 8,
      );
      expect(f.calls.single.params, {
        'trainer_id': 't1',
        'athlete_id': 'al1',
        'occurrences': 8,
        'booking_type': 'series',
      });
      expect(f.calls.single.params.containsKey('appointment_id'), isFalse);
    });

    test('logPaywallWriteDenied captura los 6 campos del incidente', () async {
      // Entrada en la canary porque este evento es la unica senal
      // server-visible del enforcement: Firestore no loguea las denegaciones
      // de reglas en ningun lado consultable y el Coach Hub web no inicializa
      // Crashlytics. Un campo que se cae en silencio no lo agarra nadie hasta
      // el dia del incidente, que es tarde.
      final f = FakeAnalyticsService();
      await f.logPaywallWriteDenied(
        trainerId: 't1',
        athleteId: 'a1',
        collection: 'routines',
        operation: 'create',
        surface: 'routine_editor_web',
        athleteEntitlement: 'blocked',
      );
      // El literal se assertea a proposito, y no `kPaywallWriteDeniedEvent`:
      // la constante la comparten el fake y `FirebaseAnalyticsService`, asi
      // que pinear el string aca pinea tambien el nombre que llega a BigQuery.
      // Con la constante de los dos lados el assert se cumpliria solo.
      expect(f.events, ['paywall_write_denied']);
      expect(kPaywallWriteDeniedEvent, 'paywall_write_denied');
      expect(f.calls.single.params, {
        'trainer_id': 't1',
        'athlete_id': 'a1',
        'collection': 'routines',
        'operation': 'create',
        'surface': 'routine_editor_web',
        'athlete_entitlement': 'blocked',
      });
    });

    // ── Forma de rutina: los tres eventos que alimentan la decisión del
    // paywall del alumno suelto. Se assertean los params completos y no sólo
    // el nombre: un `routine_created` sin `days_count` no responde la única
    // pregunta para la que existe.
    test('logRoutineCreated captura source + days_count + weeks_count',
        () async {
      final f = FakeAnalyticsService();
      await f.logRoutineCreated(
        source: RoutineCreationSource.self,
        daysCount: 3,
        weeksCount: 8,
      );
      expect(f.events, ['routine_created']);
      expect(f.calls.single.params, {
        'source': 'self',
        'days_count': 3,
        'weeks_count': 8,
      });
    });

    test('RoutineCreationSource — un wireName distinto por variante', () {
      // El enum existe para que `source` no sea un String suelto. Si dos
      // variantes colapsaran en el mismo valor, la segmentación que separa al
      // alumno suelto del PF dejaría de existir sin que ningún test lo note.
      final wires = RoutineCreationSource.values.map((s) => s.wireName);
      expect(wires.toSet().length, RoutineCreationSource.values.length);
      expect(RoutineCreationSource.self.wireName, 'self');
      expect(
        RoutineCreationSource.selfFromTemplate.wireName,
        'self_from_template',
      );
      expect(
        RoutineCreationSource.trainerAssigned.wireName,
        'trainer_assigned',
      );
      expect(
        RoutineCreationSource.trainerTemplate.wireName,
        'trainer_template',
      );
    });

    test('logRoutineDayAdded captura source + days_count', () async {
      final f = FakeAnalyticsService();
      await f.logRoutineDayAdded(
        source: RoutineCreationSource.selfFromTemplate,
        daysCount: 4,
      );
      expect(f.events, ['routine_day_added']);
      expect(f.calls.single.params, {
        'source': 'self_from_template',
        'days_count': 4,
      });
    });

    test('logRoutineWeekAdded captura source + weeks_count', () async {
      final f = FakeAnalyticsService();
      await f.logRoutineWeekAdded(
        source: RoutineCreationSource.trainerAssigned,
        weeksCount: 2,
      );
      expect(f.events, ['routine_week_added']);
      expect(f.calls.single.params, {
        'source': 'trainer_assigned',
        'weeks_count': 2,
      });
    });

    test('paramsOf filtra por nombre y conserva el orden', () async {
      final f = FakeAnalyticsService();
      await f.logRoutineDayAdded(
        source: RoutineCreationSource.self,
        daysCount: 2,
      );
      await f.logRoutineWeekAdded(
        source: RoutineCreationSource.self,
        weeksCount: 2,
      );
      await f.logRoutineDayAdded(
        source: RoutineCreationSource.self,
        daysCount: 3,
      );
      expect(
        f.paramsOf('routine_day_added').map((p) => p['days_count']),
        [2, 3],
      );
      expect(f.paramsOf('routine_created'), isEmpty);
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
