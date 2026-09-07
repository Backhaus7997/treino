import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/blocked_athletes_providers.dart';
import 'package:treino/features/coach_hub/presentation/sections/routine_editor/routine_editor_web_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/reviews/presentation/widgets/star_rating_display.dart';
import 'package:treino/features/workout/application/custom_exercise_providers.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/domain/custom_exercise.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../../../fixtures/exercises.dart';

const _trainerId = 'trainer-1';
const _athleteId = 'athlete-1';
const _templateId = 'template-1';
const _assignedId = 'assigned-1';

Future<FakeFirebaseFirestore> _seed({
  String visibility = 'private',
  int? ratingsCount,
  double? ratingAvg,
}) async {
  final firestore = FakeFirebaseFirestore();
  await firestore.collection('routines').doc(_templateId).set({
    'name': 'Fuerza base',
    'split': 'Full Body',
    'level': 'intermediate',
    'days': <Object?>[],
    'numWeeks': 1,
    'source': 'trainer-template',
    'assignedBy': _trainerId,
    'assignedTo': null,
    'visibility': visibility,
    'status': 'active',
    'goals': <Object?>[],
    if (ratingsCount != null) 'ratingsCount': ratingsCount,
    if (ratingAvg != null) 'ratingAvg': ratingAvg,
  });
  await firestore.collection('routines').doc(_assignedId).set({
    'name': 'Plan de Juan',
    'split': 'Full Body',
    'level': 'intermediate',
    'days': <Object?>[],
    'numWeeks': 1,
    'source': 'trainer-assigned',
    'assignedBy': _trainerId,
    'assignedTo': _athleteId,
    'visibility': 'private',
    'status': 'active',
    'goals': <Object?>[],
  });
  return firestore;
}

Future<void> _pump(
  WidgetTester tester,
  FakeFirebaseFirestore firestore, {
  required Widget screen,
}) async {
  tester.view.physicalSize = const Size(1400, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        currentUidProvider.overrideWith((ref) => _trainerId),
        blockedAthletesProvider.overrideWith(
          (ref) => Stream.value(BlockedAthletes.unpublished),
        ),
        exercisesProvider.overrideWith((ref) async => kExerciseSeed),
        customExercisesForTrainerStreamProvider(_trainerId).overrideWith(
          (ref) => Stream<List<CustomExercise>>.value(const []),
        ),
        userPublicProfileProvider(_athleteId).overrideWith(
          (ref) => Stream.value(
            const UserPublicProfile(
              uid: _athleteId,
              displayName: 'Juan Pérez',
            ),
          ),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(body: screen),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<String?> _visibility(FakeFirebaseFirestore firestore) async {
  final snapshot =
      await firestore.collection('routines').doc(_templateId).get();
  return snapshot.data()?['visibility'] as String?;
}

Finder _inDialog(String label) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text(label),
    );

void main() {
  final toggle = find.byKey(const Key('routine_editor_publish_toggle'));
  final badge = find.byKey(const Key('routine_editor_published_badge'));
  final aggregate = find.byKey(const Key('routine_editor_rating_aggregate'));

  // Cada caso monta UNA sola pantalla. Dos `pumpWidget` seguidos con el mismo
  // runtimeType y sin key reusan el State —`_loadedRoutine` sobrevive— y el
  // segundo assert termina mirando los datos del primero. Nos pasó: el caso de
  // "sin calificaciones" encontraba el agregado de la plantilla anterior.

  testWidgets('una plantilla existente ofrece publicación y su estado', (
    tester,
  ) async {
    final firestore = await _seed();
    await _pump(
      tester,
      firestore,
      screen: const RoutineEditorWebScreen.template(routineId: _templateId),
    );

    expect(toggle, findsOneWidget);
    expect(find.text('NO PUBLICADA'), findsOneWidget);
  });

  testWidgets('una plantilla nueva todavía no se puede publicar', (
    tester,
  ) async {
    final firestore = await _seed();
    await _pump(
      tester,
      firestore,
      screen: const RoutineEditorWebScreen.template(),
    );

    // firestore.rules exige `visibility == 'private'` al crear una
    // trainer-template: no puede nacer pública.
    expect(toggle, findsNothing);
  });

  testWidgets('un plan asignado nunca ofrece publicación', (tester) async {
    final firestore = await _seed();
    await _pump(
      tester,
      firestore,
      screen: const RoutineEditorWebScreen(
        athleteId: _athleteId,
        routineId: _assignedId,
      ),
    );

    // El flip de visibilidad exige `source == 'trainer-template'`.
    expect(toggle, findsNothing);
  });

  testWidgets('publica, actualiza el estado local y permite despublicar', (
    tester,
  ) async {
    final firestore = await _seed();
    await _pump(
      tester,
      firestore,
      screen: const RoutineEditorWebScreen.template(routineId: _templateId),
    );

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('Publicar plantilla'), findsOneWidget);
    await tester.tap(_inDialog('Publicar'));
    await tester.pumpAndSettle();

    expect(await _visibility(firestore), 'public');
    expect(badge, findsOneWidget);
    expect(find.text('PUBLICADA'), findsOneWidget);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('Despublicar plantilla'), findsOneWidget);
    await tester.tap(_inDialog('Despublicar'));
    await tester.pumpAndSettle();

    expect(await _visibility(firestore), 'private');
    expect(find.text('NO PUBLICADA'), findsOneWidget);
  });

  testWidgets('cancelar no cambia la visibilidad', (tester) async {
    final firestore = await _seed();
    await _pump(
      tester,
      firestore,
      screen: const RoutineEditorWebScreen.template(routineId: _templateId),
    );

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    // Acotado al diálogo a propósito: el pie del editor tiene su propio
    // "Cancelar" y un find.text suelto encuentra los dos.
    await tester.tap(_inDialog('Cancelar'));
    await tester.pumpAndSettle();

    expect(await _visibility(firestore), 'private');
    expect(find.text('NO PUBLICADA'), findsOneWidget);
  });

  testWidgets('muestra estrellas y cantidad cuando hay calificaciones', (
    tester,
  ) async {
    final firestore = await _seed(
      visibility: 'public',
      ratingsCount: 12,
      ratingAvg: 4.5,
    );
    await _pump(
      tester,
      firestore,
      screen: const RoutineEditorWebScreen.template(routineId: _templateId),
    );

    expect(badge, findsOneWidget);
    expect(aggregate, findsOneWidget);
    expect(
      find.descendant(of: aggregate, matching: find.byType(StarRatingDisplay)),
      findsOneWidget,
    );
    expect(find.text('4,5 · 12 calificaciones'), findsOneWidget);
  });

  testWidgets('sin calificaciones no muestra el agregado', (tester) async {
    final firestore = await _seed(visibility: 'public', ratingsCount: 0);
    await _pump(
      tester,
      firestore,
      screen: const RoutineEditorWebScreen.template(routineId: _templateId),
    );

    expect(badge, findsOneWidget);
    expect(aggregate, findsNothing);
  });

  testWidgets('bloquea la publicación cuando hay cambios sin guardar', (
    tester,
  ) async {
    final firestore = await _seed();
    await _pump(
      tester,
      firestore,
      screen: const RoutineEditorWebScreen.template(routineId: _templateId),
    );

    await tester.enterText(
      find.byKey(const Key('routine_editor_name_field')),
      'Fuerza base ajustada',
    );
    await tester.pump();

    // Publicar con cambios sin guardar mandaría la versión ANTERIOR a toda la
    // comunidad mientras la pantalla muestra la nueva.
    final button = tester.widget<OutlinedButton>(toggle);
    expect(button.onPressed, isNull);
    expect(find.text('Guardá los cambios antes de publicar.'), findsOneWidget);
  });
}
