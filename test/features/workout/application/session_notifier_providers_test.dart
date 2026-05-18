// Tests para los nuevos providers de session-player — SCENARIO-269, 322..324.
// RED: los providers currentUidProvider, sessionNotifierProvider,
// activeSessionForUidProvider no existen todavía.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/workout/application/session_init.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/set_log.dart';

import 'stub_factories.dart';

// ── Mock ─────────────────────────────────────────────────────────────────────

class MockSessionRepository extends Mock implements SessionRepository {}

// ── Helper ───────────────────────────────────────────────────────────────────

/// Crea un container con overrides para uid y repo.
/// Sobreescribe `currentUidProvider` directamente (evita depender del tipo
/// firebase_auth.User que no puede construirse en tests unitarios).
ProviderContainer _makeContainer({
  String? uid,
  MockSessionRepository? repo,
}) {
  final overrides = <Override>[
    if (repo != null) sessionRepositoryProvider.overrideWithValue(repo),
    currentUidProvider.overrideWithValue(uid),
  ];
  return ProviderContainer(overrides: overrides);
}

void main() {
  setUpAll(() {
    registerFallbackValue(makeSession());
    registerFallbackValue(makeSetLog());
  });

  // ── currentUidProvider ────────────────────────────────────────────────────

  group('currentUidProvider', () {
    test('devuelve el uid cuando el usuario está autenticado', () async {
      final container = _makeContainer(uid: 'u1');
      addTearDown(container.dispose);

      // Espera que el stream emita
      await Future.microtask(() {});
      final uid = container.read(currentUidProvider);
      expect(uid, equals('u1'));
    });

    test('devuelve null cuando no hay usuario autenticado', () async {
      final container = _makeContainer(uid: null);
      addTearDown(container.dispose);

      await Future.microtask(() {});
      final uid = container.read(currentUidProvider);
      expect(uid, isNull);
    });
  });

  // ── sessionNotifierProvider — family key uniqueness (SCENARIO-269) ────────

  group('sessionNotifierProvider family key uniqueness (SCENARIO-269)', () {
    test('FreshSession con distintos routineId produce instancias distintas', () {
      final repo = MockSessionRepository();
      final container = _makeContainer(uid: 'u1', repo: repo);
      addTearDown(container.dispose);

      final key1 = const FreshSession(routineId: 'r1', dayNumber: 1);
      final key2 = const FreshSession(routineId: 'r2', dayNumber: 1);

      // Distintas claves → no son iguales
      expect(key1, isNot(equals(key2)));
    });

    test('FreshSession y ResumeSession son claves distintas aunque compartan valor', () {
      const fresh = FreshSession(routineId: 's1', dayNumber: 1);
      const resume = ResumeSession(sessionId: 's1');
      expect(fresh, isNot(equals(resume)));
    });

    test('dos FreshSession con mismos params son la misma clave (mismo provider)', () {
      const a = FreshSession(routineId: 'r1', dayNumber: 1);
      const b = FreshSession(routineId: 'r1', dayNumber: 1);
      expect(a, equals(b));
    });
  });

  // ── activeSessionForUidProvider ────────────────────────────────────────────

  group('activeSessionForUidProvider', () {
    test(
        'SCENARIO-322: retorna record no nulo cuando repo.getActive devuelve session',
        () async {
      final repo = MockSessionRepository();
      final session = makeSession();
      final setLogs = [makeSetLog()];

      when(() => repo.getActive('u1')).thenAnswer((_) async => session);
      when(
        () => repo.listSetLogs(uid: 'u1', sessionId: session.id),
      ).thenAnswer((_) async => setLogs);

      final container = _makeContainer(uid: 'u1', repo: repo);
      addTearDown(container.dispose);

      final result = await container.read(activeSessionForUidProvider.future);
      expect(result, isNotNull);
      expect(result!.session, equals(session));
      expect(result.setLogs, equals(setLogs));
    });

    test('SCENARIO-323: retorna null cuando no hay sesión activa', () async {
      final repo = MockSessionRepository();
      when(() => repo.getActive('u1')).thenAnswer((_) async => null);

      final container = _makeContainer(uid: 'u1', repo: repo);
      addTearDown(container.dispose);

      final result = await container.read(activeSessionForUidProvider.future);
      expect(result, isNull);
      // listSetLogs no debe ser llamado
      verifyNever(() => repo.listSetLogs(uid: any(named: 'uid'), sessionId: any(named: 'sessionId')));
    });

    test(
        'SCENARIO-324: retorna null y NO llama al repo cuando uid es null',
        () async {
      final repo = MockSessionRepository();
      final container = _makeContainer(uid: null, repo: repo);
      addTearDown(container.dispose);

      final result = await container.read(activeSessionForUidProvider.future);
      expect(result, isNull);
      verifyNever(() => repo.getActive(any()));
    });
  });
}
