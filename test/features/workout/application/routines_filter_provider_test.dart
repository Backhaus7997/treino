import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';

Routine makeRoutine({
  required String id,
  required ExperienceLevel level,
}) =>
    Routine(
      id: id,
      name: 'Routine $id',
      split: 'Full Body',
      level: level,
      days: const [],
    );

final _routineA = makeRoutine(id: 'a', level: ExperienceLevel.beginner);
final _routineB = makeRoutine(id: 'b', level: ExperienceLevel.intermediate);
final _routineC = makeRoutine(id: 'c', level: ExperienceLevel.advanced);

ProviderContainer _makeContainer({
  required List<Routine> routines,
}) =>
    ProviderContainer(
      overrides: [
        routinesProvider.overrideWith((ref) async => routines),
      ],
    );

ProviderContainer _makeLoadingContainer() => ProviderContainer(
      overrides: [
        // Never-completing future — provider stays in AsyncLoading indefinitely.
        routinesProvider.overrideWith(
          (ref) => Completer<List<Routine>>().future,
        ),
      ],
    );

ProviderContainer _makeErrorContainer() => ProviderContainer(
      overrides: [
        routinesProvider.overrideWith(
          (ref) async => throw Exception('network error'),
        ),
      ],
    );

void main() {
  group('routinesLevelFilterProvider', () {
    test('default is null', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(routinesLevelFilterProvider), isNull);
    });

    test('state can be mutated', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      container.read(routinesLevelFilterProvider.notifier).state =
          ExperienceLevel.beginner;
      expect(
        container.read(routinesLevelFilterProvider),
        equals(ExperienceLevel.beginner),
      );
    });
  });

  group('filteredRoutinesProvider', () {
    test('returns full list when filter is null', () async {
      final container = _makeContainer(
        routines: [_routineA, _routineB, _routineC],
      );
      addTearDown(container.dispose);

      // Wait for routinesProvider to resolve
      await container.read(routinesProvider.future);

      final result = container.read(filteredRoutinesProvider);
      expect(result.valueOrNull, hasLength(3));
    });

    test('filters to beginner only', () async {
      final container = _makeContainer(
        routines: [_routineA, _routineB, _routineC],
      );
      addTearDown(container.dispose);
      await container.read(routinesProvider.future);

      container.read(routinesLevelFilterProvider.notifier).state =
          ExperienceLevel.beginner;

      final result = container.read(filteredRoutinesProvider);
      expect(result.valueOrNull, hasLength(1));
      expect(result.valueOrNull?.first.id, equals('a'));
    });

    test('filters to intermediate only', () async {
      final container = _makeContainer(
        routines: [_routineA, _routineB, _routineC],
      );
      addTearDown(container.dispose);
      await container.read(routinesProvider.future);

      container.read(routinesLevelFilterProvider.notifier).state =
          ExperienceLevel.intermediate;

      final result = container.read(filteredRoutinesProvider);
      expect(result.valueOrNull, hasLength(1));
      expect(result.valueOrNull?.first.id, equals('b'));
    });

    test('filters to advanced only', () async {
      final container = _makeContainer(
        routines: [_routineA, _routineB, _routineC],
      );
      addTearDown(container.dispose);
      await container.read(routinesProvider.future);

      container.read(routinesLevelFilterProvider.notifier).state =
          ExperienceLevel.advanced;

      final result = container.read(filteredRoutinesProvider);
      expect(result.valueOrNull, hasLength(1));
      expect(result.valueOrNull?.first.id, equals('c'));
    });

    test('passes through AsyncLoading (never-completing future override)', () {
      final container = _makeLoadingContainer();
      addTearDown(container.dispose);

      final result = container.read(filteredRoutinesProvider);
      expect(result, isA<AsyncLoading<List<Routine>>>());
    });

    test('passes through AsyncError (throwing future override)', () async {
      final container = _makeErrorContainer();
      addTearDown(container.dispose);

      // Subscribe to both providers so they are both active
      container.listen<AsyncValue<List<Routine>>>(
        routinesProvider,
        (_, __) {},
        fireImmediately: true,
      );
      container.listen<AsyncValue<List<Routine>>>(
        filteredRoutinesProvider,
        (_, __) {},
        fireImmediately: true,
      );

      // Wait for routinesProvider future to reject — expect the throw
      try {
        await container.read(routinesProvider.future);
      } catch (_) {
        // expected — the FutureProvider throws
      }

      // Multiple microtask ticks so filteredRoutinesProvider re-derives
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      final result = container.read(filteredRoutinesProvider);
      expect(result, isA<AsyncError<List<Routine>>>());
    });
  });
}
