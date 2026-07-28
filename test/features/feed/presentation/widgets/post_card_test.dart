import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/post_providers.dart';
import 'package:treino/features/feed/data/post_repository.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/feed/domain/routine_tag.dart';
import 'package:treino/features/feed/domain/workout_snapshot.dart';
import 'package:treino/features/feed/domain/workout_stats.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/feed/presentation/widgets/post_card.dart';
import 'package:treino/features/feed/presentation/widgets/workout_snapshot_detail.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/features/gyms/application/gym_providers.dart';
import 'package:treino/features/gyms/domain/gym.dart';
import 'package:treino/features/gyms/domain/gym_source.dart';
import 'package:treino/l10n/app_l10n.dart';

class MockPostRepository extends Mock implements PostRepository {}

/// Snapshot mínimo con UN ejercicio identificable por nombre — sirve para
/// distinguir qué post está expandido en una lista.
WorkoutSnapshot _snapshotFor(String exerciseName) => WorkoutSnapshot(
      exercises: [
        WorkoutSnapshotExercise(
          exerciseName: exerciseName,
          sets: [
            SetLog(
              id: 's1',
              exerciseId: 'e1',
              exerciseName: exerciseName,
              setNumber: 1,
              reps: 10,
              weightKg: 50,
              completedAt: DateTime.utc(2026, 7, 28, 10),
            ),
          ],
        ),
      ],
    );

Gym _gym({required String id, required String name}) => Gym(
      id: id,
      name: name,
      lat: -34.56,
      lng: -58.45,
      geohash: 'abc123',
      source: GymSource.googlePlaces,
      createdAt: DateTime.utc(2026, 1, 1),
    );

class _MockUser extends Mock implements User {
  _MockUser({required String uid}) : _uid = uid;
  final String _uid;
  @override
  String get uid => _uid;
}

Post makePost({
  String id = 'p1',
  String authorUid = 'u1',
  String authorDisplayName = 'Tincho',
  String? authorAvatarUrl,
  String? authorGymId,
  String text = 'Gran sesión hoy',
  RoutineTag? routineTag,
  PostPrivacy privacy = PostPrivacy.friends,
  DateTime? createdAt,
  WorkoutStats? workoutStats,
}) =>
    Post(
      id: id,
      authorUid: authorUid,
      authorDisplayName: authorDisplayName,
      authorAvatarUrl: authorAvatarUrl,
      authorGymId: authorGymId,
      text: text,
      routineTag: routineTag,
      privacy: privacy,
      createdAt: createdAt ?? DateTime.now().subtract(const Duration(hours: 2)),
      workoutStats: workoutStats,
    );

/// Wraps [PostCard] with a viewer identity ([viewerUid], `null` = signed out)
/// so ownership-gated UI (the overflow menu) can be exercised.
Widget _wrap(
  Widget w, {
  String? viewerUid = 'u1',
  MockPostRepository? mockRepo,
  List<Override> overrides = const [],
}) {
  final user = viewerUid == null ? null : _MockUser(uid: viewerUid);
  return ProviderScope(
    overrides: [
      authStateChangesProvider.overrideWith((ref) => Stream.value(user)),
      if (mockRepo != null) postRepositoryProvider.overrideWithValue(mockRepo),
      ...overrides,
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      locale: const Locale('es', 'AR'),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: Scaffold(body: w),
    ),
  );
}

Widget _wrapRouter(
  Widget w, {
  String? viewerUid = 'u1',
  MockPostRepository? mockRepo,
  List<Override> overrides = const [],
}) {
  final user = viewerUid == null ? null : _MockUser(uid: viewerUid);
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(body: w),
      ),
      GoRoute(
        path: '/workout/routine/:id',
        builder: (_, state) =>
            Scaffold(body: Text('detail-${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/feed/create',
        builder: (_, state) => const Scaffold(body: Text('create-screen')),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      authStateChangesProvider.overrideWith((ref) => Stream.value(user)),
      if (mockRepo != null) postRepositoryProvider.overrideWithValue(mockRepo),
      ...overrides,
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      locale: const Locale('es', 'AR'),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      routerConfig: router,
    ),
  );
}

void main() {
  group('PostCard', () {
    // SCENARIO-166: author display name is rendered
    testWidgets('SCENARIO-166: renders authorDisplayName', (tester) async {
      final post = makePost(authorDisplayName: 'Tincho');
      await tester.pumpWidget(_wrap(PostCard(post: post)));
      await tester.pump();

      expect(find.text('Tincho'), findsOneWidget);
    });

    // SCENARIO-167 (rewritten for #549): the meta row shows the RESOLVED gym
    // name from the `gyms/` catalog, uppercased — never the raw id.
    testWidgets(
        'SCENARIO-167: resolves authorGymId to the gym name via '
        'gymByIdProvider', (tester) async {
      final post = makePost(authorGymId: 'gym-la-fuerza');
      await tester.pumpWidget(_wrap(
        PostCard(post: post),
        overrides: [
          gymByIdProvider('gym-la-fuerza').overrideWith(
            (ref) async => _gym(id: 'gym-la-fuerza', name: 'La Fuerza'),
          ),
        ],
      ));
      // Two pumps: one for the widget, one for the async gym resolution.
      await tester.pump();
      await tester.pump();

      final gymFinder = find.byWidgetPredicate(
        (w) => w is Text && w.data != null && w.data!.contains('LA FUERZA'),
      );
      expect(gymFinder, findsAtLeastNWidgets(1));
      // The raw id must never leak into the UI.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              w.data != null &&
              w.data!.toLowerCase().contains('gym-la-fuerza'),
        ),
        findsNothing,
      );
    });

    // Regression #549: a Google Places gym id (`ChIJ…`, opaque) whose doc is
    // missing from the catalog must NOT be printed raw — the gym segment is
    // omitted and only the timestamp remains.
    testWidgets(
        'regression #549: unresolvable Google Places id is never shown raw',
        (tester) async {
      const placeId = 'ChIJucMKes6dmpQR1rebv5azedo';
      final post = makePost(authorGymId: placeId);
      await tester.pumpWidget(_wrap(
        PostCard(post: post),
        overrides: [
          gymByIdProvider(placeId).overrideWith((ref) async => null),
        ],
      ));
      await tester.pump();
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              w.data != null &&
              w.data!.toLowerCase().contains(placeId.toLowerCase()),
        ),
        findsNothing,
      );
      // Meta row still shows the relative timestamp alone.
      final timestampFinder = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.data != null &&
            RegExp(r'^[Hh]ace\s+\d+\s*h$').hasMatch(w.data!),
      );
      expect(timestampFinder, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // Regression #549: while the catalog read is in flight the id must not
    // flash raw either — loading renders time-only, then upgrades in place.
    testWidgets('regression #549: no raw id flash while the gym doc loads',
        (tester) async {
      final post = makePost(authorGymId: 'gym-la-fuerza');
      await tester.pumpWidget(_wrap(
        PostCard(post: post),
        overrides: [
          gymByIdProvider('gym-la-fuerza').overrideWith(
            (ref) async => _gym(id: 'gym-la-fuerza', name: 'La Fuerza'),
          ),
        ],
      ));
      // First frame only — the future has not completed yet.
      await tester.pump();

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              w.data != null &&
              w.data!.toLowerCase().contains('gym-la-fuerza'),
        ),
        findsNothing,
      );
    });

    // SCENARIO-168: timestamp rendered as relative string
    testWidgets('SCENARIO-168: renders relative timestamp', (tester) async {
      final post = makePost(
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      );
      await tester.pumpWidget(_wrap(PostCard(post: post)));
      await tester.pump();

      final timestampFinder = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.data != null &&
            RegExp(r'[Hh]ace\s+\d+\s*h').hasMatch(w.data!),
      );
      expect(timestampFinder, findsAtLeastNWidgets(1));
    });

    // Regression #500: la fecha absoluta (>7d) se formatea en zona local.
    // createdAt viaja en UTC (Post.createdAt -> toUtc()); leer .day/.month
    // sobre el instante UTC adelanta un día todo post nocturno en zonas de
    // offset negativo — Argentina (UTC-3) es el mercado objetivo.
    testWidgets(
        'fecha absoluta (>7d) usa el día local, no el UTC '
        '[tz-local-date-regression]', (tester) async {
      // 02:30 UTC: en ART cae a las 23:30 del día ANTERIOR. Hora elegida a
      // propósito (no medianoche por inercia): es justo el caso que rompe.
      final utcInstant = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 10))
          .copyWith(hour: 2, minute: 30, second: 0, millisecond: 0);

      // El esperado sale del MISMO instante convertido a local, así el test
      // vale en cualquier zona del runner y solo se pone rojo donde el bug
      // realmente se manifiesta.
      final local = utcInstant.toLocal();
      final expected = '${local.day.toString().padLeft(2, '0')}/'
          '${local.month.toString().padLeft(2, '0')}';

      final post = makePost(createdAt: utcInstant);
      await tester.pumpWidget(_wrap(PostCard(post: post)));
      await tester.pump();

      final dateFinder = find.byWidgetPredicate(
        (w) => w is Text && w.data != null && w.data!.contains(expected),
      );
      expect(dateFinder, findsAtLeastNWidgets(1));
    });

    // SCENARIO-169: body text rendered
    testWidgets('SCENARIO-169: renders post body text', (tester) async {
      final post = makePost(text: 'Gran sesión hoy');
      await tester.pumpWidget(_wrap(PostCard(post: post)));
      await tester.pump();

      expect(find.text('Gran sesión hoy'), findsOneWidget);
    });

    // Regression #547: the theme's Barlow families carry no emoji glyphs, so
    // post content (e.g. "¡Terminé mi entreno! 💪") rendered tofu. The body
    // text style must pin the system emoji fonts — same fix as
    // post_workout_summary_screen.dart (PR #465), applied to the style so
    // manual-post emojis render too.
    testWidgets(
        'regression #547: body text style pins system emoji font fallbacks',
        (tester) async {
      final post = makePost(text: '¡Terminé mi entreno! 💪');
      await tester.pumpWidget(_wrap(PostCard(post: post)));
      await tester.pump();

      final body = tester.widget<Text>(find.text('¡Terminé mi entreno! 💪'));
      final fallback = body.style?.fontFamilyFallback ?? const [];
      expect(fallback, contains('Apple Color Emoji'));
      expect(fallback, contains('Noto Color Emoji'));
      // Appended, not replaced: google_fonts' own base-family fallback
      // ('Barlow') must survive ahead of the emoji fonts.
      expect(fallback, contains('Barlow'));
      expect(
        fallback.indexOf('Barlow'),
        lessThan(fallback.indexOf('Apple Color Emoji')),
      );
    });

    // SCENARIO-170: routine tag chip rendered when routineTag present
    testWidgets('SCENARIO-170: renders routine tag chip when routineTag is set',
        (tester) async {
      final post = makePost(
        routineTag:
            const RoutineTag(routineId: 'r1', routineName: 'Push · Día 4'),
      );
      await tester.pumpWidget(_wrap(PostCard(post: post)));
      await tester.pump();

      expect(find.text('Push · Día 4'), findsOneWidget);
    });

    // SCENARIO-171: tapping routine tag chip navigates to /workout/routine/:id
    testWidgets(
        'SCENARIO-171: tapping routine chip navigates to /workout/routine/:id',
        (tester) async {
      final post = makePost(
        routineTag:
            const RoutineTag(routineId: 'r1', routineName: 'Push · Día 4'),
      );
      await tester.pumpWidget(_wrapRouter(PostCard(post: post)));
      await tester.pump();

      await tester.tap(find.text('Push · Día 4'));
      await tester.pumpAndSettle();

      expect(find.text('detail-r1'), findsOneWidget);
    });

    // SCENARIO-172: no chip rendered when routineTag is null
    testWidgets('SCENARIO-172: no chip rendered when routineTag is null',
        (tester) async {
      final post = makePost(routineTag: null);
      await tester.pumpWidget(_wrap(PostCard(post: post)));
      await tester.pump();

      expect(find.text('Push · Día 4'), findsNothing);
      // No chip-like widget containing routine name text
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              w.data != null &&
              RegExp(r'Push|Día|routine').hasMatch(w.data!),
        ),
        findsNothing,
      );
    });

    // QA-FEED-364/389: the old always-empty "— kg / — min / — ej." stub is
    // gone. A post with no workout behind it (manual/legacy → workoutStats
    // null) shows NO stats row at all — not a permanent em-dash placeholder.
    testWidgets(
        'QA-FEED-364/389: no stats row (no em-dash stub) when workoutStats is null',
        (tester) async {
      final post = makePost();
      await tester.pumpWidget(_wrap(PostCard(post: post)));
      await tester.pump();

      expect(find.text('— kg'), findsNothing);
      expect(find.text('— min'), findsNothing);
      expect(find.text('— ej.'), findsNothing);
      // "ej." is unique to the stats row → its absence proves the row is gone.
      expect(find.textContaining('ej.'), findsNothing);
    });

    // QA-FEED-364/389: a share-a-workout post (workoutStats present) shows the
    // REAL volume / duration / exercise numbers instead of the em-dash stub.
    testWidgets(
        'QA-FEED-364/389: renders real volume/duration/exercise stats when '
        'workoutStats is present', (tester) async {
      final post = makePost(
        workoutStats: const WorkoutStats(
          volumeKg: 3.2,
          durationMin: 52,
          exerciseCount: 6,
        ),
      );
      await tester.pumpWidget(_wrap(PostCard(post: post)));
      await tester.pump();

      expect(find.text('3.2 kg'), findsOneWidget);
      expect(find.text('52 min'), findsOneWidget);
      expect(find.text('6 ej.'), findsOneWidget);
      // And never the old em-dash stub.
      expect(find.text('— kg'), findsNothing);
    });

    // SCENARIO-175: card container decoration — borderRadius, bgCard color, border
    testWidgets('SCENARIO-175: card has correct decoration', (tester) async {
      final post = makePost();
      await tester.pumpWidget(_wrap(PostCard(post: post)));
      await tester.pump();

      const palette = AppPalette.mintMagenta;

      final containers = tester.widgetList<Container>(find.byType(Container));
      bool foundCard = false;
      for (final container in containers) {
        final dec = container.decoration;
        if (dec is BoxDecoration) {
          if (dec.color == palette.bgCard &&
              dec.borderRadius == BorderRadius.circular(20) &&
              dec.border != null) {
            foundCard = true;
            break;
          }
        }
      }
      expect(foundCard, isTrue,
          reason:
              'Expected a Container with bgCard color, r-20 borderRadius and non-null border');
    });

    // SCENARIO-176: dotsThree icon present for the post's own author (owner)
    testWidgets('SCENARIO-176: dotsThree icon is present for the owner',
        (tester) async {
      final post = makePost(authorUid: 'u1');
      await tester.pumpWidget(_wrap(PostCard(post: post), viewerUid: 'u1'));
      await tester.pump();

      expect(find.byIcon(TreinoIcon.dotsThree), findsOneWidget);
    });

    // SCENARIO-177: menu button is absent for a non-owner viewer
    testWidgets('SCENARIO-177: overflow menu hidden when viewer is not owner',
        (tester) async {
      final post = makePost(authorUid: 'u1');
      await tester.pumpWidget(_wrap(PostCard(post: post), viewerUid: 'u2'));
      await tester.pump();

      expect(find.byIcon(TreinoIcon.dotsThree), findsNothing);
    });

    testWidgets('overflow menu hidden when viewer is unauthenticated',
        (tester) async {
      final post = makePost(authorUid: 'u1');
      await tester.pumpWidget(_wrap(PostCard(post: post), viewerUid: null));
      await tester.pump();

      expect(find.byIcon(TreinoIcon.dotsThree), findsNothing);
    });

    // SCENARIO-178: author tap no-op when onAuthorTap is null
    testWidgets('SCENARIO-178: author tap is no-op when onAuthorTap is null',
        (tester) async {
      final post = makePost(authorDisplayName: 'Tincho');
      await tester.pumpWidget(_wrap(PostCard(post: post, onAuthorTap: null)));
      await tester.pump();

      await tester.tap(find.text('Tincho'));
      await tester.pumpAndSettle();
      // No exception means pass
    });

    // SCENARIO-179: onAuthorTap callback fires when provided
    testWidgets('SCENARIO-179: onAuthorTap fires when tapped', (tester) async {
      var tapped = false;
      final post = makePost(authorDisplayName: 'Tincho');
      await tester.pumpWidget(
        _wrap(PostCard(post: post, onAuthorTap: () => tapped = true)),
      );
      await tester.pump();

      await tester.tap(find.text('Tincho'));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    // ── Owner overflow menu: Editar/Eliminar ──────────────────────────────

    group('overflow menu (owner)', () {
      testWidgets('tapping dotsThree opens a menu with Editar and Eliminar',
          (tester) async {
        final post = makePost(authorUid: 'u1');
        await tester.pumpWidget(_wrapRouter(PostCard(post: post)));
        await tester.pump();

        await tester.tap(find.byIcon(TreinoIcon.dotsThree));
        await tester.pumpAndSettle();

        expect(find.text('Editar'), findsOneWidget);
        expect(find.text('Eliminar'), findsOneWidget);
      });

      testWidgets('tapping Editar navigates to the create/edit route',
          (tester) async {
        final post = makePost(authorUid: 'u1');
        await tester.pumpWidget(_wrapRouter(PostCard(post: post)));
        await tester.pump();

        await tester.tap(find.byIcon(TreinoIcon.dotsThree));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Editar'));
        await tester.pumpAndSettle();

        expect(find.text('create-screen'), findsOneWidget);
      });

      testWidgets('tapping Eliminar shows a confirmation dialog',
          (tester) async {
        final post = makePost(authorUid: 'u1');
        await tester.pumpWidget(_wrapRouter(PostCard(post: post)));
        await tester.pump();

        await tester.tap(find.byIcon(TreinoIcon.dotsThree));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Eliminar'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('¿Eliminar este post?'), findsOneWidget);
        expect(find.text('Cancelar'), findsOneWidget);
      });

      testWidgets('confirming delete calls repository.delete with post.id',
          (tester) async {
        final repo = MockPostRepository();
        when(() => repo.delete(any())).thenAnswer((_) async {});
        final post = makePost(id: 'p-to-delete', authorUid: 'u1');

        await tester.pumpWidget(
          _wrapRouter(PostCard(post: post), mockRepo: repo),
        );
        await tester.pump();

        await tester.tap(find.byIcon(TreinoIcon.dotsThree));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Eliminar'));
        await tester.pumpAndSettle();

        // Dialog shows "Eliminar" as the confirm button too — tap the one
        // inside the AlertDialog specifically.
        final confirmButton = find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Eliminar'),
        );
        await tester.tap(confirmButton);
        await tester.pumpAndSettle();

        verify(() => repo.delete('p-to-delete')).called(1);
      });

      testWidgets(
          'cancelling the delete dialog does not call repository.delete',
          (tester) async {
        final repo = MockPostRepository();
        final post = makePost(id: 'p1', authorUid: 'u1');

        await tester.pumpWidget(
          _wrapRouter(PostCard(post: post), mockRepo: repo),
        );
        await tester.pump();

        await tester.tap(find.byIcon(TreinoIcon.dotsThree));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Eliminar'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();

        verifyNever(() => repo.delete(any()));
        expect(find.byType(AlertDialog), findsNothing);
      });
    });

    // ── Share-composer PR2: detalle del entreno y foto ────────────────────
    group('workout snapshot detail', () {
      WorkoutSnapshot snapshot(
              {int exerciseCount = 2, bool truncated = false}) =>
          WorkoutSnapshot(
            exercises: [
              for (var i = 0; i < exerciseCount; i++)
                WorkoutSnapshotExercise(
                  exerciseName: 'Ejercicio $i',
                  sets: [
                    SetLog(
                      id: 's$i',
                      exerciseId: 'e$i',
                      exerciseName: 'Ejercicio $i',
                      setNumber: 1,
                      reps: 10,
                      weightKg: 50,
                      completedAt: DateTime.utc(2026, 7, 28, 10),
                    ),
                  ],
                ),
            ],
            setsByAxis: const {'chest': 2, 'legs': 1},
            volumeKgByAxis: const {'chest': 1000, 'legs': 500},
            truncated: truncated,
          );

      testWidgets('un post SIN snapshot no muestra el control de detalle',
          (tester) async {
        await tester.pumpWidget(_wrap(PostCard(post: makePost())));
        await tester.pump();

        expect(find.text('VER DETALLE'), findsNothing);
        expect(find.byType(WorkoutSnapshotDetail), findsNothing);
      });

      testWidgets(
          'con snapshot muestra el control pero NO construye el detalle hasta expandir',
          (tester) async {
        await tester.pumpWidget(_wrap(
          PostCard(post: makePost().copyWith(workoutSnapshot: snapshot())),
        ));
        await tester.pump();

        expect(find.text('VER DETALLE'), findsOneWidget);
        // Lazy: colapsada, la card no paga los bloques de ejercicios ni el
        // mini-gráfico (hay N cards en el ListView del feed).
        expect(find.byType(WorkoutSnapshotDetail), findsNothing);
        expect(find.text('Ejercicio 0'), findsNothing);
      });

      testWidgets('al expandir renderiza ejercicios, sets y el mini-gráfico',
          (tester) async {
        await tester.pumpWidget(_wrap(
          PostCard(post: makePost().copyWith(workoutSnapshot: snapshot())),
        ));
        await tester.pump();

        await tester.tap(find.text('VER DETALLE'));
        await tester.pump();

        expect(find.byType(WorkoutSnapshotDetail), findsOneWidget);
        expect(find.byType(MuscleDistributionBars), findsOneWidget);
        expect(find.text('Ejercicio 0'), findsOneWidget);
        expect(find.text('Ejercicio 1'), findsOneWidget);
        expect(find.text('10 reps'), findsNWidgets(2));
        // Ejes del mini-gráfico, en el orden canónico del radar.
        expect(find.text('PECHO'), findsOneWidget);
        expect(find.text('PIERNAS'), findsOneWidget);
        // El control invierte su label para poder colapsar.
        expect(find.text('OCULTAR DETALLE'), findsOneWidget);
      });

      testWidgets('vuelve a colapsar y descarta el detalle', (tester) async {
        await tester.pumpWidget(_wrap(
          PostCard(post: makePost().copyWith(workoutSnapshot: snapshot())),
        ));
        await tester.pump();

        await tester.tap(find.text('VER DETALLE'));
        await tester.pump();
        await tester.tap(find.text('OCULTAR DETALLE'));
        await tester.pump();

        expect(find.byType(WorkoutSnapshotDetail), findsNothing);
        expect(find.text('VER DETALLE'), findsOneWidget);
      });

      testWidgets('un snapshot truncado avisa cuántos ejercicios muestra',
          (tester) async {
        await tester.pumpWidget(_wrap(
          PostCard(
            post: makePost().copyWith(
              workoutSnapshot: snapshot(truncated: true),
            ),
          ),
        ));
        await tester.pump();
        await tester.tap(find.text('VER DETALLE'));
        await tester.pump();

        expect(
          find.text('Se muestran los primeros $kMaxSnapshotExercises '
              'ejercicios.'),
          findsOneWidget,
        );
      });

      testWidgets('un snapshot sin ejes no renderiza el mini-gráfico',
          (tester) async {
        await tester.pumpWidget(_wrap(
          PostCard(
            post: makePost().copyWith(
              workoutSnapshot: snapshot().copyWith(
                setsByAxis: const {},
                volumeKgByAxis: const {},
              ),
            ),
          ),
        ));
        await tester.pump();
        await tester.tap(find.text('VER DETALLE'));
        await tester.pump();

        expect(find.byType(MuscleDistributionBars), findsNothing);
        expect(find.text('Ejercicio 0'), findsOneWidget);
      });
    });

    // Regresión: PostCard ganó estado local (el detalle expandido) al sumarse
    // el snapshot, así que los call sites del feed y del perfil DEBEN pasarle
    // una key estable por post. Sin eso, un post nuevo arriba (refresh, o el
    // propio usuario compartiendo) corre las posiciones y el estado expandido
    // queda pegado al índice, mostrando el detalle de OTRO post.
    testWidgets(
        'el estado expandido sigue al post, no a su posición en la lista',
        (tester) async {
      final viejo = makePost(id: 'viejo', text: 'post viejo')
          .copyWith(workoutSnapshot: _snapshotFor('Sentadilla'));
      final nuevo = makePost(id: 'nuevo', text: 'post nuevo')
          .copyWith(workoutSnapshot: _snapshotFor('Press banca'));

      Widget listOf(List<Post> posts) => _wrap(
            ListView(
              children: [
                for (final p in posts) PostCard(key: ValueKey(p.id), post: p),
              ],
            ),
          );

      // Un solo post, con su detalle expandido.
      await tester.pumpWidget(listOf([viejo]));
      await tester.pump();
      await tester.tap(find.text('VER DETALLE'));
      await tester.pump();
      expect(find.text('Sentadilla'), findsOneWidget);

      // Entra un post nuevo ARRIBA: el viejo pasa del índice 0 al 1.
      await tester.pumpWidget(listOf([nuevo, viejo]));
      await tester.pump();

      // El detalle sigue siendo el del post viejo, que es el que se expandió.
      expect(find.text('Sentadilla'), findsOneWidget);
      // Y el post nuevo NO heredó el estado expandido de la posición 0.
      expect(find.text('Press banca'), findsNothing);
      expect(find.text('VER DETALLE'), findsOneWidget);
      expect(find.text('OCULTAR DETALLE'), findsOneWidget);
    });

    group('post photo', () {
      testWidgets('un post sin photoUrl no renderiza imagen de red',
          (tester) async {
        await tester.pumpWidget(_wrap(PostCard(post: makePost())));
        await tester.pump();

        expect(find.byType(CachedNetworkImage), findsNothing);
      });

      testWidgets('con photoUrl renderiza la foto con memCacheWidth acotado',
          (tester) async {
        await tester.pumpWidget(_wrap(
          PostCard(
            post: makePost().copyWith(photoUrl: 'https://example.com/f.jpg'),
          ),
        ));
        await tester.pump();

        final image = tester.widget<CachedNetworkImage>(
          find.byType(CachedNetworkImage),
        );
        expect(image.imageUrl, 'https://example.com/f.jpg');
        expect(image.memCacheWidth, isNotNull);
      });

      testWidgets('photoUrl vacía se trata como sin foto', (tester) async {
        await tester.pumpWidget(_wrap(
          PostCard(post: makePost().copyWith(photoUrl: '')),
        ));
        await tester.pump();

        expect(find.byType(CachedNetworkImage), findsNothing);
      });
    });
  });
}
