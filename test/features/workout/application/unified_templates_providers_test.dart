import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/unified_templates_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';

// ─── Fixtures ─────────────────────────────────────────────────────────────────

Routine makeRoutine({
  required String id,
  String name = 'Routine',
  ExperienceLevel level = ExperienceLevel.beginner,
}) =>
    Routine(
      id: id,
      name: name,
      split: 'Full Body',
      level: level,
      days: const [],
    );

TrainerLink makeLink({String trainerId = 'trainer-1'}) => TrainerLink(
      id: 'link-1',
      trainerId: trainerId,
      athleteId: 'athlete-1',
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 2),
    );

UserPublicProfile makeTrainerProfile({bool shared = true}) => UserPublicProfile(
      uid: 'trainer-1',
      displayName: 'Coach Vic',
      displayNameLowercase: 'coach vic',
      sharedTemplatesWithAthletes: shared,
    );

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Builds a container, keeps the unified providers alive (autoDispose needs a
/// listener), resolves the async chain, and returns the container.
Future<ProviderContainer> pumpContainer(List<Override> overrides) async {
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  container.listen(filteredUnifiedTemplatesProvider, (_, __) {});
  // Let the catalog future + link future + profile/template streams emit.
  await container.read(routinesProvider.future);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  return container;
}

void main() {
  final catalog = [
    makeRoutine(id: 'sys-1', level: ExperienceLevel.beginner),
    makeRoutine(id: 'sys-2', level: ExperienceLevel.advanced),
  ];
  final coachTemplates = [
    makeRoutine(id: 'coach-1', level: ExperienceLevel.beginner),
  ];

  List<Override> baseOverrides({
    TrainerLink? link,
    UserPublicProfile? profile,
    Object? templatesOrError,
  }) =>
      [
        routinesProvider.overrideWith((ref) async => catalog),
        currentAthleteLinkProvider.overrideWith((ref) async => link),
        if (link != null)
          userPublicProfileProvider(link.trainerId).overrideWith(
            (ref) => Stream.value(profile),
          ),
        if (link != null && templatesOrError != null)
          trainerTemplatesStreamProvider(link.trainerId).overrideWith(
            (ref) => templatesOrError is List<Routine>
                ? Stream.value(templatesOrError)
                : Stream<List<Routine>>.error(templatesOrError),
          ),
      ];

  group('unifiedTemplatesProvider — gating', () {
    test('sin link → sólo catálogo, todo fromCoach:false', () async {
      final container = await pumpContainer(baseOverrides(link: null));

      final value = container.read(unifiedTemplatesProvider);
      final entries = value.requireValue;
      expect(entries.map((e) => e.routine.id), ['sys-1', 'sys-2']);
      expect(entries.every((e) => !e.fromCoach), isTrue);
    });

    test('link activo pero trainer NO opt-in → sólo catálogo', () async {
      final container = await pumpContainer(
        baseOverrides(
          link: makeLink(),
          profile: makeTrainerProfile(shared: false),
          templatesOrError: coachTemplates,
        ),
      );

      final entries = container.read(unifiedTemplatesProvider).requireValue;
      expect(entries.map((e) => e.routine.id), ['sys-1', 'sys-2']);
    });

    test('link + opt-in + templates → coach PRIMERO con fromCoach:true',
        () async {
      final container = await pumpContainer(
        baseOverrides(
          link: makeLink(),
          profile: makeTrainerProfile(),
          templatesOrError: coachTemplates,
        ),
      );

      final entries = container.read(unifiedTemplatesProvider).requireValue;
      expect(
        entries.map((e) => e.routine.id),
        ['coach-1', 'sys-1', 'sys-2'],
      );
      expect(entries.first.fromCoach, isTrue);
      expect(entries.skip(1).every((e) => !e.fromCoach), isTrue);
    });

    test('stream del trainer en error → degrada a sólo catálogo (sin error)',
        () async {
      final container = await pumpContainer(
        baseOverrides(
          link: makeLink(),
          profile: makeTrainerProfile(),
          templatesOrError: Exception('permission-denied'),
        ),
      );

      final value = container.read(unifiedTemplatesProvider);
      expect(value.hasError, isFalse);
      expect(value.requireValue.map((e) => e.routine.id), ['sys-1', 'sys-2']);
    });

    test('catálogo en error → AsyncError (el grid entero muestra error)',
        () async {
      final container = ProviderContainer(
        overrides: [
          routinesProvider.overrideWith(
            (ref) async => throw Exception('network'),
          ),
          currentAthleteLinkProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(container.dispose);
      container.listen(unifiedTemplatesProvider, (_, __) {});
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(unifiedTemplatesProvider).hasError, isTrue);
    });
  });

  group('filteredUnifiedTemplatesProvider — filtro de nivel', () {
    test('filtro null → grid completo sin tocar', () async {
      final container = await pumpContainer(
        baseOverrides(
          link: makeLink(),
          profile: makeTrainerProfile(),
          templatesOrError: coachTemplates,
        ),
      );

      final entries =
          container.read(filteredUnifiedTemplatesProvider).requireValue;
      expect(entries.length, 3);
    });

    test('filtro aplica al grid COMPLETO — coach incluida', () async {
      final container = await pumpContainer(
        baseOverrides(
          link: makeLink(),
          profile: makeTrainerProfile(),
          templatesOrError: coachTemplates,
        ),
      );

      container.read(routinesLevelFilterProvider.notifier).state =
          ExperienceLevel.beginner;
      final beginners =
          container.read(filteredUnifiedTemplatesProvider).requireValue;
      // coach-1 (beginner) + sys-1 (beginner); sys-2 (advanced) queda afuera.
      expect(beginners.map((e) => e.routine.id), ['coach-1', 'sys-1']);

      container.read(routinesLevelFilterProvider.notifier).state =
          ExperienceLevel.advanced;
      final advanced =
          container.read(filteredUnifiedTemplatesProvider).requireValue;
      // La del coach también se filtra cuando no matchea el nivel.
      expect(advanced.map((e) => e.routine.id), ['sys-2']);
    });
  });
}
