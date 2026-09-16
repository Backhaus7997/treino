// Coach-isolation wiring test for the read-only SESSION detail route.
//
// Hermano de `router_coach_exercise_route_test.dart`, y la misma propiedad de
// seguridad: en `/coach/athlete/:athleteId/session/:sessionId` la sesión que se
// lee es la del ATLETA del path. El PF logueado no puede ver su propio
// entrenamiento adentro del contexto de un alumno.
//
// Acá el riesgo es más concreto que un refactor futuro: `SessionDetailScreen`
// nació como la pantalla del alumno y resolvía el uid con
// `currentUidProvider`. Si el modo PF no lo pisa, la pantalla carga en verde —
// con las series y los reportes DEL PF— y nada falla. Por eso cada aserción
// sobre el modo PF tiene al lado su control negativo sobre el modo dueño: sin
// eso, un test que pasara con las dos ramas idénticas no probaría nada.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_notifier.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/exercise_feedback_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/exercise_feedback.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/features/workout/presentation/session_detail_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockUser extends Mock implements User {}

class _StubAuthNotifier extends AuthNotifier {
  _StubAuthNotifier(this._fixedState);
  final AsyncValue<User?> _fixedState;

  @override
  Future<User?> build() async {
    state = _fixedState;
    return _fixedState.valueOrNull;
  }
}

const _kCoachUid = 'coach-uid';
const _kAthleteUid = 'athlete-1';
const _kSessionId = 'session-1';

final DateTime _kDate = DateTime.utc(2026, 1, 1);

UserProfile _profile() => UserProfile(
      uid: _kCoachUid,
      email: 'coach@example.com',
      displayName: 'coach',
      role: UserRole.athlete,
      createdAt: _kDate,
      updatedAt: _kDate,
    );

/// La sesión que devuelve el override, con el uid del dueño adentro para que
/// una aserción sobre el contenido no pueda confundir las dos.
Session _session({required String uid}) => Session(
      id: _kSessionId,
      uid: uid,
      routineId: 'r1',
      routineName: 'Pecho y tríceps',
      startedAt: DateTime.utc(2026, 5, 19, 13, 30),
      finishedAt: DateTime.utc(2026, 5, 19, 14, 15),
      totalVolumeKg: 1800,
      durationMin: 45,
      status: SessionStatus.finished,
      dayNumber: 1,
      wasFullyCompleted: true,
    );

/// Lo que cada corrida observó. Un record en vez de variables sueltas para que
/// el caso PF y el caso dueño no puedan leerse cruzados por accidente.
typedef _Observed = ({
  List<({String uid, String sessionId})> summaryKeys,
  List<({String athleteUid, String sessionId})> coachFeedbackKeys,
  List<({String uid, String sessionId})> ownerFeedbackKeys,
});

/// Levanta el router REAL en [location] y devuelve qué claves recibió cada
/// provider. No stubea la pantalla: lo que se pinea es el cableado de
/// `buildRouter()`.
Future<_Observed> _pumpRoute(WidgetTester tester, String location) async {
  final summaryKeys = <({String uid, String sessionId})>[];
  final coachFeedbackKeys = <({String athleteUid, String sessionId})>[];
  final ownerFeedbackKeys = <({String uid, String sessionId})>[];

  final container = ProviderContainer(
    overrides: [
      authNotifierProvider.overrideWith(
        () => _StubAuthNotifier(AsyncData(_MockUser())),
      ),
      userProfileProvider.overrideWith(
        (ref) => Stream<UserProfile?>.value(_profile()),
      ),
      authStateChangesProvider.overrideWith((_) => Stream.value(null)),
      // El PF logueado. Es el uid que la pantalla usaría si el modo PF no
      // pisara nada — o sea, exactamente el valor equivocado.
      currentUidProvider.overrideWithValue(_kCoachUid),
      sessionSummaryProvider.overrideWith((ref, key) async {
        summaryKeys.add(key);
        return (session: _session(uid: key.uid), setLogs: <SetLog>[]);
      }),
      coachSessionExerciseFeedbackProvider.overrideWith((ref, key) async {
        coachFeedbackKeys.add(key);
        return const <ExerciseFeedback>[];
      }),
      sessionExerciseFeedbackProvider.overrideWith((ref, key) {
        ownerFeedbackKeys.add(key);
        return Stream.value(const <ExerciseFeedback>[]);
      }),
    ],
  );
  addTearDown(container.dispose);
  await container.read(authNotifierProvider.future);
  await container.read(userProfileProvider.future);

  final router = buildRouter(
    refreshListenable: ValueNotifier<int>(0),
    read: container.read,
  );
  router.go(location);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  return (
    summaryKeys: summaryKeys,
    coachFeedbackKeys: coachFeedbackKeys,
    ownerFeedbackKeys: ownerFeedbackKeys,
  );
}

void main() {
  testWidgets(
      'la ruta del PF existe y monta SessionDetailScreen con el athleteId del '
      'path', (tester) async {
    await _pumpRoute(
      tester,
      '/coach/athlete/$_kAthleteUid/session/$_kSessionId',
    );

    final screen = tester.widget<SessionDetailScreen>(
      find.byType(SessionDetailScreen),
    );
    expect(screen.sessionId, _kSessionId);
    expect(screen.coachAthleteId, _kAthleteUid,
        reason: 'la ruta tiene que reenviar el athleteId del path a la '
            'pantalla, o el modo PF no se activa');
  });

  testWidgets(
      'modo PF: la sesión se pide para el ALUMNO del path, no para el PF '
      'logueado', (tester) async {
    final observed = await _pumpRoute(
      tester,
      '/coach/athlete/$_kAthleteUid/session/$_kSessionId',
    );

    expect(observed.summaryKeys, isNotEmpty,
        reason: 'si nadie pidió la sesión, las aserciones de abajo son vacías');
    expect(
      observed.summaryKeys.map((k) => k.uid).toSet(),
      {_kAthleteUid},
      reason: 'la sesión es del alumno; pedirla con el uid del PF le muestra '
          'SU propio entrenamiento adentro de la ficha del alumno',
    );
    expect(observed.summaryKeys.map((k) => k.sessionId).toSet(), {_kSessionId});
  });

  testWidgets(
      'CONTROL NEGATIVO — modo dueño: la MISMA pantalla pide la sesión con el '
      'uid del que mira', (tester) async {
    final observed =
        await _pumpRoute(tester, '/workout/historial/$_kSessionId');

    final screen = tester.widget<SessionDetailScreen>(
      find.byType(SessionDetailScreen),
    );
    expect(screen.coachAthleteId, isNull,
        reason: 'la ruta del alumno no activa el modo PF');
    expect(
      observed.summaryKeys.map((k) => k.uid).toSet(),
      {_kCoachUid},
      reason: 'sin este control, un test donde las dos ramas resolvieran el '
          'mismo uid pasaría igual y no probaría nada',
    );
  });

  testWidgets(
      'modo PF: los reportes salen del provider del PF, y el del dueño no se '
      'toca', (tester) async {
    final observed = await _pumpRoute(
      tester,
      '/coach/athlete/$_kAthleteUid/session/$_kSessionId',
    );

    expect(
      observed.coachFeedbackKeys.map((k) => k.athleteUid).toSet(),
      {_kAthleteUid},
      reason: 'los reportes de #628 tienen que pedirse por la variante del PF, '
          'que es la que las reglas habilitan para un uid ajeno',
    );
    expect(observed.ownerFeedbackKeys, isEmpty,
        reason: 'el provider del dueño leería la subcolección del PF: lista '
            'vacía, y el PF concluye que el alumno no reportó nada');
  });

  testWidgets(
      'CONTROL NEGATIVO — modo dueño: los reportes salen del provider del '
      'dueño, y el del PF no se toca', (tester) async {
    final observed =
        await _pumpRoute(tester, '/workout/historial/$_kSessionId');

    expect(
      observed.ownerFeedbackKeys.map((k) => k.uid).toSet(),
      {_kCoachUid},
      reason: 'el alumno relee lo suyo por el stream de dueño',
    );
    expect(observed.coachFeedbackKeys, isEmpty);
  });
}
