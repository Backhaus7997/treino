import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/trainer_workout_view.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Publish / unpublish action on the trainer's own template cards
/// (workout redesign slice 3).

const _uid = 'trainer-1';
const _templateId = 'tpl-1';

Routine makeTemplate({
  RoutineVisibility visibility = RoutineVisibility.private,
}) =>
    Routine(
      id: _templateId,
      name: 'Plantilla PPL',
      split: 'PPL',
      level: ExperienceLevel.beginner,
      days: const [],
      source: RoutineSource.trainerTemplate,
      assignedBy: _uid,
      visibility: visibility,
    );

Future<FakeFirebaseFirestore> seed(RoutineVisibility visibility) async {
  final firestore = FakeFirebaseFirestore();
  await firestore.collection('routines').doc(_templateId).set({
    'name': 'Plantilla PPL',
    'split': 'PPL',
    'level': 'beginner',
    'days': <Object?>[],
    'numWeeks': 1,
    'source': 'trainer-template',
    'assignedBy': _uid,
    'assignedTo': null,
    'visibility': visibility.toJson(),
    'status': 'active',
  });
  return firestore;
}

Widget _wrap(FakeFirebaseFirestore firestore, Routine template) =>
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        currentUidProvider.overrideWith((ref) => _uid),
        trainerTemplatesStreamProvider(_uid)
            .overrideWith((ref) => Stream.value([template])),
        userPublicProfileProvider(_uid).overrideWith(
          (ref) => Stream.value(
            const UserPublicProfile(
              uid: _uid,
              displayName: 'Coach Vic',
              displayNameLowercase: 'coach vic',
            ),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(body: TrainerWorkoutView()),
      ),
    );

Future<String?> visibilityOf(FakeFirebaseFirestore firestore) async {
  final snap = await firestore.collection('routines').doc(_templateId).get();
  return snap.data()?['visibility'] as String?;
}

void main() {
  testWidgets('publishing a private template flips it to public',
      (tester) async {
    final firestore = await seed(RoutineVisibility.private);
    await tester.pumpWidget(_wrap(firestore, makeTemplate()));
    await tester.pumpAndSettle();

    // A private template shows no PUBLICADA marker.
    expect(
      find.byKey(const Key('template_published_badge_$_templateId')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const Key('template_publish_toggle_$_templateId')),
    );
    await tester.pumpAndSettle();

    // Confirmation dialog explains what publishing means.
    expect(find.text('Publicar plantilla'), findsOneWidget);
    expect(
      find.textContaining('visible para toda la comunidad'),
      findsOneWidget,
    );

    await tester.tap(find.text('Publicar'));
    await tester.pumpAndSettle();

    expect(await visibilityOf(firestore), 'public');
    expect(
      find.text('¡Tu plantilla ya está en el catálogo público!'),
      findsOneWidget,
    );
  });

  testWidgets('cancelling the dialog leaves the template untouched',
      (tester) async {
    final firestore = await seed(RoutineVisibility.private);
    await tester.pumpWidget(_wrap(firestore, makeTemplate()));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('template_publish_toggle_$_templateId')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(await visibilityOf(firestore), 'private');
  });

  testWidgets('a published template shows PUBLICADA and can be unpublished',
      (tester) async {
    final firestore = await seed(RoutineVisibility.public);
    await tester.pumpWidget(
      _wrap(firestore, makeTemplate(visibility: RoutineVisibility.public)),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('template_published_badge_$_templateId')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('template_publish_toggle_$_templateId')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Despublicar plantilla'), findsOneWidget);
    // The copy promises ratings survive an unpublish.
    expect(
      find.textContaining('calificaciones que ya recibió se conservan'),
      findsOneWidget,
    );

    await tester.tap(find.text('Despublicar'));
    await tester.pumpAndSettle();

    expect(await visibilityOf(firestore), 'private');
    expect(
      find.text('Tu plantilla salió del catálogo público.'),
      findsOneWidget,
    );
  });
}
