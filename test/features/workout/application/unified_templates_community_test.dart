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
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';

/// The community source of the unified PLANTILLAS grid (slice 3). The
/// coach/system composition of slice 2 is covered by
/// unified_templates_providers_test.dart.

Routine system(String id) => Routine(
      id: id,
      name: 'System $id',
      level: ExperienceLevel.beginner,
      days: const [],
    );

Routine template(String id, {String assignedBy = 'trainer-9'}) => Routine(
      id: id,
      name: 'Template $id',
      level: ExperienceLevel.beginner,
      days: const [],
      source: RoutineSource.trainerTemplate,
      assignedBy: assignedBy,
      visibility: RoutineVisibility.public,
    );

TrainerLink link() => TrainerLink(
      id: 'link-1',
      trainerId: 'trainer-1',
      athleteId: 'athlete-1',
      status: TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 2),
    );

Future<ProviderContainer> pumpContainer(List<Override> overrides) async {
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);
  container.listen(unifiedTemplatesProvider, (_, __) {});
  await container.read(routinesProvider.future);
  await container.read(publishedTemplatesProvider.future);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  return container;
}

List<Override> baseOverrides({
  List<Routine> catalog = const [],
  List<Routine> published = const [],
  List<Routine> coachTemplates = const [],
  bool linked = false,
}) =>
    [
      currentAthleteLinkProvider
          .overrideWith((ref) async => linked ? link() : null),
      routinesProvider.overrideWith((ref) async => catalog),
      publishedTemplatesProvider.overrideWith((ref) async => published),
      if (linked) ...[
        userPublicProfileProvider('trainer-1').overrideWith(
          (ref) => Stream.value(
            const UserPublicProfile(
              uid: 'trainer-1',
              displayName: 'Coach Vic',
              displayNameLowercase: 'coach vic',
              sharedTemplatesWithAthletes: true,
            ),
          ),
        ),
        trainerTemplatesStreamProvider('trainer-1')
            .overrideWith((ref) => Stream.value(coachTemplates)),
      ],
    ];

void main() {
  test('community templates land between coach and system', () async {
    final container = await pumpContainer(
      baseOverrides(
        catalog: [system('sys-1')],
        published: [template('pub-1')],
        coachTemplates: [template('coach-1', assignedBy: 'trainer-1')],
        linked: true,
      ),
    );

    final entries = container.read(unifiedTemplatesProvider).requireValue;
    expect(
      entries.map((e) => (e.routine.id, e.origin)).toList(),
      [
        ('coach-1', TemplateOrigin.coach),
        ('pub-1', TemplateOrigin.community),
        ('sys-1', TemplateOrigin.system),
      ],
    );
  });

  test('a template that is BOTH my coach\'s and published appears once',
      () async {
    final shared = template('shared-1', assignedBy: 'trainer-1');
    final container = await pumpContainer(
      baseOverrides(
        published: [shared, template('pub-2')],
        coachTemplates: [shared],
        linked: true,
      ),
    );

    final entries = container.read(unifiedTemplatesProvider).requireValue;
    expect(entries.length, 2);
    expect(
      entries.map((e) => (e.routine.id, e.origin)).toList(),
      [
        ('shared-1', TemplateOrigin.coach),
        ('pub-2', TemplateOrigin.community),
      ],
    );
  });

  test('fromCoach stays true ONLY for my coach entries', () async {
    final container = await pumpContainer(
      baseOverrides(
        catalog: [system('sys-1')],
        published: [template('pub-1')],
        coachTemplates: [template('coach-1', assignedBy: 'trainer-1')],
        linked: true,
      ),
    );

    final entries = container.read(unifiedTemplatesProvider).requireValue;
    expect(entries.where((e) => e.fromCoach).map((e) => e.routine.id), [
      'coach-1',
    ]);
  });

  test('community templates show up for an athlete with NO linked coach',
      () async {
    final container = await pumpContainer(
      baseOverrides(
        catalog: [system('sys-1')],
        published: [template('pub-1')],
      ),
    );

    final entries = container.read(unifiedTemplatesProvider).requireValue;
    expect(
      entries.map((e) => (e.routine.id, e.origin)).toList(),
      [
        ('pub-1', TemplateOrigin.community),
        ('sys-1', TemplateOrigin.system),
      ],
    );
  });

  test('a failing community query leaves the catalog intact', () async {
    final container = ProviderContainer(
      overrides: [
        currentAthleteLinkProvider.overrideWith((ref) async => null),
        routinesProvider.overrideWith((ref) async => [system('sys-1')]),
        publishedTemplatesProvider
            .overrideWith((ref) async => throw Exception('boom')),
      ],
    );
    addTearDown(container.dispose);
    container.listen(unifiedTemplatesProvider, (_, __) {});
    await container.read(routinesProvider.future);
    await expectLater(
      container.read(publishedTemplatesProvider.future),
      throwsException,
    );
    await Future<void>.delayed(Duration.zero);

    final value = container.read(unifiedTemplatesProvider);
    expect(value.hasError, isFalse);
    expect(value.requireValue.map((e) => e.routine.id).toList(), ['sys-1']);
  });
}
