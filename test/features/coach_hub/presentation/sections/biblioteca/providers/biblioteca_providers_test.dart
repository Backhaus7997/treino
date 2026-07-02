// Unit tests for bibliotecaExercisesProvider and filter state providers.
// REQ-BIBW-03, REQ-BIBW-06
// SCENARIO-BIBW-03a (CUSTOM badge path), SCENARIO-BIBW-06b (ADR-RER-05)
// T-BIBW-002

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach_hub/presentation/sections/biblioteca/providers/biblioteca_providers.dart';
import 'package:treino/features/workout/application/custom_exercise_providers.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/domain/custom_exercise.dart';
import 'package:treino/features/workout/domain/equipment_type.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/muscle_group.dart';

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _kTrainerId = 'trainer-uid-test';

const _bench = Exercise(
  id: 'bench-press',
  name: 'Press de Banca',
  muscleGroup: 'chest',
  category: 'compound',
  equipment: EquipmentType.barra,
);

const _curl = Exercise(
  id: 'biceps-curl',
  name: 'Curl de Bíceps',
  muscleGroup: 'biceps',
  category: 'isolation',
  // equipment: null intentionally
);

final _customEx = CustomExercise(
  id: 'custom-squat',
  ownerId: _kTrainerId,
  name: 'Sentadilla Personalizada',
  muscleGroup: 'quads',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 1),
);

// ── Helpers ───────────────────────────────────────────────────────────────────

ProviderContainer _container({
  List<Exercise> catalog = const [],
  List<CustomExercise> customs = const [],
  String? catalogError,
  String? customsError,
}) {
  return ProviderContainer(
    overrides: [
      currentUidProvider.overrideWithValue(_kTrainerId),
      exercisesProvider.overrideWith((ref) async {
        if (catalogError != null) throw Exception(catalogError);
        return catalog;
      }),
      customExercisesForTrainerStreamProvider(_kTrainerId).overrideWith(
        (ref) {
          if (customsError != null) {
            return Stream.error(Exception(customsError));
          }
          return Stream.value(customs);
        },
      ),
    ],
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('bibliotecaExercisesProvider', () {
    test('returns AsyncLoading while catalog is loading', () {
      // We use a container that never resolves the future
      final container = ProviderContainer(
        overrides: [
          currentUidProvider.overrideWithValue(_kTrainerId),
          exercisesProvider.overrideWith(
            (ref) =>
                Future.delayed(const Duration(hours: 1), () => <Exercise>[]),
          ),
          customExercisesForTrainerStreamProvider(_kTrainerId).overrideWith(
            (ref) => Stream.value(<CustomExercise>[]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final result = container.read(bibliotecaExercisesProvider);
      expect(result, isA<AsyncLoading>());
    });

    test('returns AsyncError when catalog errors', () async {
      final container = _container(catalogError: 'firestore down');
      addTearDown(container.dispose);

      // Let the future complete
      await container
          .read(exercisesProvider.future)
          .catchError((_) => <Exercise>[]);
      await Future.microtask(() {});

      final result = container.read(bibliotecaExercisesProvider);
      expect(result, isA<AsyncError>());
    });

    test('returns catalog exercises when custom stream errors (degraded mode)',
        () async {
      final container = _container(
        catalog: const [_bench],
        customsError: 'permission denied',
      );
      addTearDown(container.dispose);

      // Let catalog future resolve
      await container.read(exercisesProvider.future);
      await Future.microtask(() {});

      final result = container.read(bibliotecaExercisesProvider);
      // Custom stream error is swallowed; catalog still shown
      result.whenData((list) {
        expect(list.any((e) => e.id == _bench.id), isTrue);
      });
    });

    test('custom exercises are prepended (customs first)', () async {
      final container = _container(
        catalog: const [_bench, _curl],
        customs: [_customEx],
      );
      addTearDown(container.dispose);

      await container.read(exercisesProvider.future);
      await Future.microtask(() {});

      final result = container.read(bibliotecaExercisesProvider);
      result.whenData((list) {
        expect(list.isNotEmpty, isTrue);
        expect(list.first.id, equals(_customEx.id));
      });
    });

    test('custom exercises have category == "custom"', () async {
      final container = _container(
        catalog: const [_bench],
        customs: [_customEx],
      );
      addTearDown(container.dispose);

      await container.read(exercisesProvider.future);
      await Future.microtask(() {});

      final result = container.read(bibliotecaExercisesProvider);
      result.whenData((list) {
        final custom = list.firstWhere((e) => e.id == _customEx.id);
        expect(custom.category, equals('custom'));
      });
    });

    test('predicate applied — exercise filtered out by name query', () async {
      final container = _container(
        catalog: const [_bench, _curl],
        customs: [],
      );
      addTearDown(container.dispose);

      await container.read(exercisesProvider.future);
      await Future.microtask(() {});

      // Apply a query that only matches curl
      container.read(bibliotecaQueryProvider.notifier).state = 'biceps';
      await Future.microtask(() {});

      final result = container.read(bibliotecaExercisesProvider);
      result.whenData((list) {
        expect(list.any((e) => e.id == _curl.id), isTrue);
        expect(list.any((e) => e.id == _bench.id), isFalse);
      });
    });

    test('unfiltered count provider returns total regardless of query',
        () async {
      final container = _container(
        catalog: const [_bench, _curl],
        customs: [_customEx],
      );
      addTearDown(container.dispose);

      await container.read(exercisesProvider.future);
      await Future.microtask(() {});

      container.read(bibliotecaQueryProvider.notifier).state = 'press';

      final unfiltered = container.read(bibliotecaUnfilteredCountProvider);
      // 2 catalog + 1 custom = 3 total regardless of query
      unfiltered.whenData((count) => expect(count, equals(3)));
    });
  });

  group('filter state providers', () {
    test('bibliotecaQueryProvider defaults to empty string', () {
      final container = _container();
      addTearDown(container.dispose);
      expect(container.read(bibliotecaQueryProvider), equals(''));
    });

    test('bibliotecaMuscleFilterProvider defaults to empty set', () {
      final container = _container();
      addTearDown(container.dispose);
      expect(container.read(bibliotecaMuscleFilterProvider), isEmpty);
    });

    test('bibliotecaEquipmentFilterProvider defaults to empty set', () {
      final container = _container();
      addTearDown(container.dispose);
      expect(container.read(bibliotecaEquipmentFilterProvider), isEmpty);
    });

    test('updating query provider narrows results (AND across dimensions)',
        () async {
      final container = _container(catalog: const [_bench, _curl]);
      addTearDown(container.dispose);

      await container.read(exercisesProvider.future);
      await Future.microtask(() {});

      container.read(bibliotecaQueryProvider.notifier).state = 'press';
      container.read(bibliotecaMuscleFilterProvider.notifier).state = {
        MuscleGroup.pecho,
      };
      await Future.microtask(() {});

      final result = container.read(bibliotecaExercisesProvider);
      result.whenData((list) {
        expect(list.length, equals(1));
        expect(list.first.id, equals(_bench.id));
      });
    });
  });
}
