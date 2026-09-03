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

  /// Aplica la MISMA restricción que `firebase_analytics`: un valor de
  /// parámetro sólo puede ser `String` o `num`
  /// (`_assertParameterTypesAreCorrect`, 11.6.0).
  ///
  /// Sin esto el fake es más permisivo que la plataforma, y ahí el test verde
  /// deja de significar algo: un `bool` pasaba por acá y en el device rompía
  /// el evento entero. Pasó con `appointment_created` — lo agarró un review
  /// bot, no la suite. Un doble que no modela la restricción que importa es
  /// un doble que miente.
  void _registrar(String name, Map<String, Object?> params) {
    for (final e in params.entries) {
      assert(
        e.value is String || e.value is num,
        "firebase_analytics sólo acepta String o num: el parámetro "
        "'${e.key}' del evento '$name' es ${e.value.runtimeType}",
      );
    }
    events.add(name);
    calls.add((name: name, params: params));
  }

  @override
  Future<void> logRoutineStarted({
    required String routineId,
    String? routineName,
  }) async {
    events.add('routine_started');
    calls.add((
      name: 'routine_started',
      params: {
        'routine_id': routineId,
        if (routineName != null) 'routine_name': routineName,
      }
    ));
  }

  @override
  Future<void> logRoutineFinished({
    required String routineId,
    required String sessionId,
    required int durationSeconds,
  }) async {
    events.add('routine_finished');
    calls.add((
      name: 'routine_finished',
      params: {
        'routine_id': routineId,
        'session_id': sessionId,
        'duration_seconds': durationSeconds,
      }
    ));
  }

  @override
  Future<void> logRoutineCreated({
    required RoutineCreationSource source,
    required int daysCount,
    required int weeksCount,
  }) async {
    _registrar('routine_created', {
      'source': source.wireName,
      'days_count': daysCount,
      'weeks_count': weeksCount,
    });
  }

  @override
  Future<void> logRoutineDayAdded({
    required RoutineCreationSource source,
    required int daysCount,
  }) async {
    _registrar('routine_day_added', {
      'source': source.wireName,
      'days_count': daysCount,
    });
  }

  @override
  Future<void> logRoutineWeekAdded({
    required RoutineCreationSource source,
    required int weeksCount,
  }) async {
    _registrar('routine_week_added', {
      'source': source.wireName,
      'weeks_count': weeksCount,
    });
  }

  /// Los params de cada evento con nombre [name], en orden. Para los tres
  /// eventos de forma de rutina los tests assertean sobre `source` y los
  /// contadores, no solo sobre el nombre: un `routine_day_added` sin
  /// `days_count` no responde ninguna pregunta.
  List<Map<String, Object?>> paramsOf(String name) =>
      calls.where((c) => c.name == name).map((c) => c.params).toList();

  @override
  Future<void> logPlanAssigned({
    required String routineId,
    required String assignedBy,
    required String assignedTo,
  }) async {
    events.add('plan_assigned');
    calls.add((
      name: 'plan_assigned',
      params: {
        'routine_id': routineId,
        'assigned_by': assignedBy,
        'assigned_to': assignedTo,
      }
    ));
  }

  @override
  Future<void> logLinkRequested({
    required String trainerId,
    required String athleteId,
  }) async {
    events.add('link_requested');
    calls.add((
      name: 'link_requested',
      params: {
        'trainer_id': trainerId,
        'athlete_id': athleteId,
      }
    ));
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
    calls.add((
      name: 'chat_message_sent',
      params: {
        'chat_id': chatId,
        'sender_id': senderId,
      }
    ));
  }

  @override
  Future<void> logAppointmentCreated({
    String? appointmentId,
    required String trainerId,
    required String athleteId,
    int occurrences = 1,
  }) async {
    _registrar('appointment_created', {
      if (appointmentId != null) 'appointment_id': appointmentId,
      'trainer_id': trainerId,
      'athlete_id': athleteId,
      'occurrences': occurrences,
      'booking_type': occurrences > 1 ? 'series' : 'single',
    });
  }

  @override
  Future<void> logScreenViewed({required String route}) async {
    events.add('screen_view');
    calls.add((name: 'screen_view', params: {'route': route}));
  }

  /// Atajo para los tests de navegación: las rutas capturadas, en orden.
  List<String> get screenRoutes => calls
      .where((c) => c.name == 'screen_view')
      .map((c) => c.params['route']! as String)
      .toList();

  @override
  Future<void> logSubTabViewed({
    required String surface,
    required String tab,
  }) async {
    events.add('sub_tab_viewed');
    calls.add((
      name: 'sub_tab_viewed',
      params: {
        'surface': surface,
        'tab': tab,
      }
    ));
  }

  /// Atajo para los tests de sub-navegación: los `tab` capturados para una
  /// superficie, en orden. Evita repetir el filtro sobre `calls` en cada
  /// expect y hace que el fallo se lea solo (`['feed', 'rankings']` en vez de
  /// un dump de records).
  List<String> subTabsFor(String surface) => calls
      .where(
          (c) => c.name == 'sub_tab_viewed' && c.params['surface'] == surface)
      .map((c) => c.params['tab']! as String)
      .toList();

  @override
  Future<void> logPaywallWriteDenied({
    required String trainerId,
    required String athleteId,
    required String collection,
    required String operation,
    required String surface,
    required String athleteEntitlement,
  }) async {
    events.add(kPaywallWriteDeniedEvent);
    calls.add((
      name: kPaywallWriteDeniedEvent,
      params: {
        'trainer_id': trainerId,
        'athlete_id': athleteId,
        'collection': collection,
        'operation': operation,
        'surface': surface,
        'athlete_entitlement': athleteEntitlement,
      }
    ));
  }

  /// Los params del ÚLTIMO `paywall_write_denied`, o null si no hubo ninguno.
  ///
  /// Este evento es la única señal server-visible del enforcement, así que los
  /// tests assertean sobre los CAMPOS y no solo sobre el nombre: un evento que
  /// llega sin `trainer_id` no sirve para nada el día del incidente, y un
  /// `expect(events, contains('paywall_write_denied'))` pasaría igual.
  Map<String, Object?>? get lastPaywallWriteDenied {
    final matches =
        calls.where((c) => c.name == kPaywallWriteDeniedEvent).toList();
    return matches.isEmpty ? null : matches.last.params;
  }
}
