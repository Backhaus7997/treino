import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/feed/application/suggested_users_providers.dart';
import 'package:treino/features/feed/domain/follow.dart';
import 'package:treino/features/feed/domain/follow_status.dart';
import 'package:treino/features/feed/presentation/widgets/feed_empty_state.dart';
import 'package:treino/features/feed/presentation/widgets/public_profile_follow_button.dart';
import 'package:treino/features/feed/presentation/widgets/suggested_users_section.dart';
import 'package:treino/features/gyms/domain/gym.dart' show kNoGymId;
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/l10n/app_l10n_es.dart';

const _emptyMessage = 'Todavía no hay posts de quienes seguís';

UserPublicProfile profile({
  required String uid,
  required String displayName,
  bool isProfilePublic = true,
}) =>
    UserPublicProfile(
      uid: uid,
      displayName: displayName,
      displayNameLowercase: displayName.toLowerCase(),
      gymId: 'gym-a',
      isProfilePublic: isProfilePublic,
    );

Widget wrap({
  required String? gymId,
  required List<UserPublicProfile> suggestions,
  String? viewerUid,
  FakeFirebaseFirestore? firestore,
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                const FeedEmptyState(message: _emptyMessage),
                SuggestedUsersSection(gymId: gymId),
              ],
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/feed/profile/:uid',
        builder: (_, state) => Scaffold(
          body: Text('profile-${state.pathParameters['uid']}'),
        ),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      if (viewerUid != null) currentUidProvider.overrideWithValue(viewerUid),
      if (firestore != null) firestoreProvider.overrideWithValue(firestore),
      if (gymId != null && gymId.isNotEmpty && gymId != kNoGymId)
        suggestedUsersProvider(gymId).overrideWith(
          (ref) async => suggestions,
        ),
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
  testWidgets('no-gym users do not render the suggestions section', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        gymId: null,
        suggestions: [profile(uid: 'candidate', displayName: 'Ana')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('suggested_users_section')), findsNothing);

    await tester.pumpWidget(
      wrap(
        gymId: kNoGymId,
        suggestions: [profile(uid: 'candidate', displayName: 'Ana')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('suggested_users_section')), findsNothing);
  });

  testWidgets(
      'zero suggestions render no section and no empty-suggestions copy',
      (tester) async {
    await tester.pumpWidget(
      wrap(gymId: 'gym-a', suggestions: const []),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('suggested_users_section')), findsNothing);
    // El título sale del l10n, NO de un literal copiado acá. Con el literal,
    // renombrar el copy volvía esta línea trivialmente cierta —el string viejo
    // ya no existe en ningún lado— y la aserción quedaba viva pero muerta.
    expect(find.text(AppL10nEs().suggestedUsersTitle), findsNothing);
  });

  testWidgets('tapping a suggestion opens the matching public profile', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      wrap(
        gymId: 'gym-a',
        suggestions: [profile(uid: 'ana-uid', displayName: 'Ana Pérez')],
      ),
    );
    await tester.pumpAndSettle();

    final row = find.byKey(const Key('suggested_user_ana-uid'));
    expect(row, findsOneWidget);
    expect(tester.getSemantics(row).label, contains('Ana Pérez'));

    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.text('profile-ana-uid'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('keeps the existing Friends empty state above suggestions', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        gymId: 'gym-a',
        suggestions: [profile(uid: 'candidate', displayName: 'Ana')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FeedEmptyState), findsOneWidget);
    expect(find.text(_emptyMessage), findsOneWidget);
    expect(find.byKey(const Key('suggested_users_section')), findsOneWidget);
  });

  group('filas', () {
    List<UserPublicProfile> people(int n) => [
          for (var index = 0; index < n; index++)
            profile(uid: 'uid-$index', displayName: 'Persona $index'),
        ];

    Finder row(int i) => find.byKey(Key('suggested_users_row_$i'));
    Finder cardIn(int r, int person) => find.descendant(
        of: row(r), matching: find.byKey(Key('suggested_user_uid-$person')));

    test(
        'alterna: 1ª arriba, 2ª abajo, 3ª arriba… (las mejores a la '
        'izquierda de las dos)', () {
      final rows = splitSuggestionRows(people(7));
      expect(rows, hasLength(2));
      expect(rows[0].map((p) => p.uid), ['uid-0', 'uid-2', 'uid-4', 'uid-6']);
      expect(rows[1].map((p) => p.uid), ['uid-1', 'uid-3', 'uid-5']);
    });

    test('con menos de 4 queda una sola fila', () {
      expect(splitSuggestionRows(people(3)), hasLength(1));
      expect(splitSuggestionRows(people(4)), hasLength(2));
    });

    testWidgets('con varias sugerencias: dos filas horizontales', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(gymId: 'gym-a', suggestions: people(kSuggestedUsersLimit)),
      );
      await tester.pumpAndSettle();

      final lists = tester.widgetList<ListView>(find.byType(ListView));
      expect(lists, hasLength(2));
      expect(lists.every((l) => l.scrollDirection == Axis.horizontal), isTrue);
      // La 1ª y la 2ª a la vista, una en cada fila.
      expect(cardIn(0, 0), findsOneWidget);
      expect(cardIn(1, 1), findsOneWidget);
      expect(tester.getTopLeft(row(1)).dy,
          greaterThan(tester.getTopLeft(row(0)).dy));
    });

    testWidgets('cada fila scrollea sola: mover una no mueve la otra', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(gymId: 'gym-a', suggestions: people(kSuggestedUsersLimit)),
      );
      await tester.pumpAndSettle();

      double offsetOf(int r) => tester
          .state<ScrollableState>(
              find.descendant(of: row(r), matching: find.byType(Scrollable)))
          .position
          .pixels;

      await tester.drag(row(0), const Offset(-200, 0));
      await tester.pumpAndSettle();

      expect(offsetOf(0), greaterThan(0));
      expect(offsetOf(1), 0);
    });

    testWidgets('con pocas sugerencias: una sola fila', (tester) async {
      await tester.pumpWidget(wrap(gymId: 'gym-a', suggestions: people(3)));
      await tester.pumpAndSettle();

      expect(find.byType(ListView), findsOneWidget);
      expect(row(1), findsNothing);
    });
  });

  group('botón Seguir en la tarjeta', () {
    testWidgets('sin sesión no se ofrece Seguir', (tester) async {
      await tester.pumpWidget(
        wrap(
          gymId: 'gym-a',
          suggestions: [profile(uid: 'ana-uid', displayName: 'Ana')],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SEGUIR'), findsNothing);
    });

    testWidgets('cada tarjeta ofrece SEGUIR y no desborda con nombre largo', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          gymId: 'gym-a',
          viewerUid: 'me',
          firestore: FakeFirebaseFirestore(),
          suggestions: [
            profile(uid: 'ana-uid', displayName: 'Ana'),
            profile(
              uid: 'long-uid',
              displayName: 'Maria de los Angeles Fernandez Gonzalez',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SEGUIR'), findsNWidgets(2));
      expect(tester.takeException(), isNull);

      // El pill va pegado al fondo de la tarjeta (12 de padding + 1 de borde):
      // sin hueco vacío abajo.
      final rowRect = tester.getRect(find.byType(ListView));
      final pill = find.byType(PublicProfileFollowButton).first;
      expect(rowRect.bottom - tester.getRect(pill).bottom, closeTo(13, 1));
    });

    testWidgets('tocar SEGUIR crea la arista, pasa a SIGUIENDO y no navega', (
      tester,
    ) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(
        wrap(
          gymId: 'gym-a',
          viewerUid: 'me',
          firestore: firestore,
          suggestions: [profile(uid: 'ana-uid', displayName: 'Ana')],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SEGUIR'));
      await tester.pumpAndSettle();

      final edge = await firestore
          .collection('follows')
          .doc(Follow.edgeId('me', 'ana-uid'))
          .get();
      expect(edge.exists, isTrue);
      expect(edge.data()!['status'], FollowStatus.accepted.name);
      expect(find.text('SIGUIENDO'), findsOneWidget);
      expect(find.text('profile-ana-uid'), findsNothing);
    });

    testWidgets(
        'tocar SIGUIENDO en la tarjeta abre la hoja con el NOMBRE de la '
        'sugerencia, no "Usuario anónimo"', (tester) async {
      final firestore = FakeFirebaseFirestore();
      // El perfil existe en Firestore, como en el device: lo que falta es que
      // nadie lo haya cargado todavía (a diferencia del perfil público, donde
      // `publicProfileViewProvider` ya lo está mirando).
      await firestore.collection('userPublicProfiles').doc('ana-uid').set({
        'uid': 'ana-uid',
        'displayName': 'Ana Pérez',
        'displayNameLowercase': 'ana pérez',
        'gymId': 'gym-a',
      });
      await tester.pumpWidget(
        wrap(
          gymId: 'gym-a',
          viewerUid: 'me',
          firestore: firestore,
          suggestions: [profile(uid: 'ana-uid', displayName: 'Ana Pérez')],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SEGUIR'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SIGUIENDO'));
      await tester.pumpAndSettle();

      expect(find.text('¿Dejar de seguir a Ana Pérez?'), findsOneWidget);
      expect(find.textContaining('Usuario anónimo'), findsNothing);
    });

    testWidgets(
        'cuenta privada: la hoja de cancelar solicitud también lleva el '
        'nombre', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('userPublicProfiles').doc('priv-uid').set({
        'uid': 'priv-uid',
        'displayName': 'Priv Ada',
        'displayNameLowercase': 'priv ada',
        'gymId': 'gym-a',
        'isProfilePublic': false,
      });
      await tester.pumpWidget(
        wrap(
          gymId: 'gym-a',
          viewerUid: 'me',
          firestore: firestore,
          suggestions: [
            profile(
              uid: 'priv-uid',
              displayName: 'Priv Ada',
              isProfilePublic: false,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SEGUIR'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SOLICITUD ENVIADA'));
      await tester.pumpAndSettle();

      expect(
        find.text('¿Cancelar la solicitud a Priv Ada?'),
        findsOneWidget,
      );
      expect(find.textContaining('Usuario anónimo'), findsNothing);
    });

    testWidgets('cuenta privada: SOLICITUD ENVIADA entra en la tarjeta', (
      tester,
    ) async {
      final firestore = FakeFirebaseFirestore();
      await tester.pumpWidget(
        wrap(
          gymId: 'gym-a',
          viewerUid: 'me',
          firestore: firestore,
          suggestions: [
            profile(
                uid: 'priv-uid', displayName: 'Priv', isProfilePublic: false),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('SEGUIR'));
      await tester.pumpAndSettle();

      final edge = await firestore
          .collection('follows')
          .doc(Follow.edgeId('me', 'priv-uid'))
          .get();
      expect(edge.data()!['status'], FollowStatus.pending.name);
      expect(find.text('SOLICITUD ENVIADA'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tocar el resto de la tarjeta sigue abriendo el perfil', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          gymId: 'gym-a',
          viewerUid: 'me',
          firestore: FakeFirebaseFirestore(),
          suggestions: [profile(uid: 'ana-uid', displayName: 'Ana Pérez')],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('suggested_user_ana-uid')));
      await tester.pumpAndSettle();

      expect(find.text('profile-ana-uid'), findsOneWidget);
    });
  });
}
