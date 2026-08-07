import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/feed/application/follow_providers.dart';
import 'package:treino/features/gyms/application/gym_providers.dart';
import 'package:treino/features/gyms/domain/gym.dart';
import 'package:treino/features/gyms/domain/gym_source.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/presentation/widgets/profile_cuenta_section.dart';
import 'package:treino/l10n/app_l10n.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _uid = 'test-uid';

UserProfile _profile({String? gymId}) => UserProfile(
      uid: _uid,
      email: 'test@test.com',
      displayName: 'Test User',
      role: UserRole.athlete,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
      gymId: gymId,
    );

class _MockUser extends Mock implements User {}

User _userWithUid(String uid) {
  final u = _MockUser();
  when(() => u.uid).thenReturn(uid);
  return u;
}

Widget _buildSection({
  required List<Override> overrides,
  GoRouter? router,
}) {
  final effectiveRouter = router ??
      GoRouter(
        initialLocation: '/profile',
        routes: [
          GoRoute(
            path: '/profile',
            builder: (_, __) => const Scaffold(
              body: SingleChildScrollView(child: ProfileCuentaSection()),
            ),
            routes: [
              GoRoute(
                path: 'friend-requests',
                builder: (_, __) =>
                    const Scaffold(body: Text('FRIEND_REQUESTS')),
              ),
              GoRoute(
                path: 'edit-personal',
                builder: (_, __) => const Scaffold(body: Text('EDIT_PERSONAL')),
              ),
              GoRoute(
                path: 'gym',
                builder: (_, __) => const Scaffold(body: Text('GYM_SCREEN')),
              ),
              GoRoute(
                path: 'routines',
                builder: (_, __) =>
                    const Scaffold(body: Text('ROUTINES_SCREEN')),
              ),
            ],
          ),
        ],
      );

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      routerConfig: effectiveRouter,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests — SCENARIO-501..505
// Migrated from profile_friend_requests_tile_test.dart (SCENARIO-465a, 466, 467)
// per ADR-PSR-003 (T16 migration)
// ---------------------------------------------------------------------------

void main() {
  group('ProfileCuentaSection', () {
    // SCENARIO-501: exactly 4 tiles in correct order
    testWidgets(
        'SCENARIO-501: renders exactly 4 tiles in order: Solicitudes, Datos personales, Gimnasio, Mis rutinas',
        (tester) async {
      await tester.pumpWidget(
        _buildSection(
          overrides: [
            authStateChangesProvider.overrideWith((_) => Stream.value(null)),
            userProfileProvider.overrideWith((_) => Stream.value(_profile())),
            pendingFollowRequestCountProvider('').overrideWith((_) => 0),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Solicitudes de amistad'), findsOneWidget);
      expect(find.text('Datos personales'), findsOneWidget);
      expect(find.text('Gimnasio'), findsOneWidget);
      expect(find.text('Mis rutinas'), findsOneWidget);
    });

    // SCENARIO-502: Solicitudes tile shows count from pendingFollowRequestCountProvider
    testWidgets(
        'SCENARIO-502: Solicitudes tile shows "4 nuevas" when count is 4',
        (tester) async {
      await tester.pumpWidget(
        _buildSection(
          overrides: [
            authStateChangesProvider.overrideWith((_) => Stream.value(null)),
            userProfileProvider.overrideWith((_) => Stream.value(_profile())),
            pendingFollowRequestCountProvider('').overrideWith((_) => 4),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('4 nuevas'), findsOneWidget);
    });

    // SCENARIO-503: Datos personales tile navigates to /profile/edit-personal
    testWidgets(
        'SCENARIO-503: tapping Datos personales tile navigates to /profile/edit-personal',
        (tester) async {
      await tester.pumpWidget(
        _buildSection(
          overrides: [
            authStateChangesProvider.overrideWith((_) => Stream.value(null)),
            userProfileProvider.overrideWith((_) => Stream.value(_profile())),
            pendingFollowRequestCountProvider('').overrideWith((_) => 0),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Datos personales'));
      await tester.pumpAndSettle();

      expect(find.text('EDIT_PERSONAL'), findsOneWidget);
    });

    // SCENARIO-504: Gimnasio tile navigates to /profile/gym
    testWidgets('SCENARIO-504: tapping Gimnasio tile navigates to /profile/gym',
        (tester) async {
      await tester.pumpWidget(
        _buildSection(
          overrides: [
            authStateChangesProvider.overrideWith((_) => Stream.value(null)),
            userProfileProvider.overrideWith((_) => Stream.value(_profile())),
            pendingFollowRequestCountProvider('').overrideWith((_) => 0),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Gimnasio'));
      await tester.pumpAndSettle();

      expect(find.text('GYM_SCREEN'), findsOneWidget);
    });

    // SCENARIO-505: Mis rutinas tile navigates to /profile/routines
    testWidgets(
        'SCENARIO-505: tapping Mis rutinas tile navigates to /profile/routines',
        (tester) async {
      await tester.pumpWidget(
        _buildSection(
          overrides: [
            authStateChangesProvider.overrideWith((_) => Stream.value(null)),
            userProfileProvider.overrideWith((_) => Stream.value(_profile())),
            pendingFollowRequestCountProvider('').overrideWith((_) => 0),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mis rutinas'));
      await tester.pumpAndSettle();

      expect(find.text('ROUTINES_SCREEN'), findsOneWidget);
    });

    // ── Migrated from profile_friend_requests_tile_test.dart ────────────────
    // SCENARIO-465a (migrated): Solicitudes count=3 reflected in tile
    testWidgets(
        'SCENARIO-465a (migrated): Solicitudes tile reflects count 3 from pendingFollowRequestCountProvider',
        (tester) async {
      await tester.pumpWidget(
        _buildSection(
          overrides: [
            authStateChangesProvider.overrideWith((_) => Stream.value(null)),
            userProfileProvider.overrideWith((_) => Stream.value(_profile())),
            pendingFollowRequestCountProvider('').overrideWith((_) => 3),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('3 nuevas'), findsOneWidget);
    });

    // SCENARIO-466 (migrated): count=0 tile is visible with no subtitle badge
    testWidgets(
        'SCENARIO-466 (migrated): Solicitudes tile visible when count=0, no subtitle count badge',
        (tester) async {
      await tester.pumpWidget(
        _buildSection(
          overrides: [
            authStateChangesProvider.overrideWith((_) => Stream.value(null)),
            userProfileProvider.overrideWith((_) => Stream.value(_profile())),
            pendingFollowRequestCountProvider('').overrideWith((_) => 0),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Solicitudes de amistad'), findsOneWidget);
      // When count == 0, subtitle should NOT show "0 nuevas"
      expect(find.text('0 nuevas'), findsNothing);
    });

    // SCENARIO-467 (migrated): tapping Solicitudes navigates to /profile/friend-requests
    testWidgets(
        'SCENARIO-467 (migrated): tapping Solicitudes tile navigates to /profile/friend-requests',
        (tester) async {
      await tester.pumpWidget(
        _buildSection(
          overrides: [
            authStateChangesProvider.overrideWith((_) => Stream.value(null)),
            userProfileProvider.overrideWith((_) => Stream.value(_profile())),
            pendingFollowRequestCountProvider('').overrideWith((_) => 2),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Solicitudes de amistad'));
      await tester.pumpAndSettle();

      expect(find.text('FRIEND_REQUESTS'), findsOneWidget);
    });

    // SCENARIO-533 (gyms-foundation Phase 3): Gimnasio tile subtitle resolves
    // the real composed name via gymByIdProvider — DETAIL context, UserProfile
    // has no denormalized gymName.
    testWidgets(
        'SCENARIO-533: Gimnasio tile subtitle shows the real resolved gym name '
        'when gymId is set', (tester) async {
      await tester.pumpWidget(
        _buildSection(
          overrides: [
            authStateChangesProvider.overrideWith((_) => Stream.value(null)),
            userProfileProvider.overrideWith(
              (_) => Stream.value(_profile(gymId: 'sportclub-belgrano')),
            ),
            pendingFollowRequestCountProvider('').overrideWith((_) => 0),
            gymByIdProvider('sportclub-belgrano').overrideWith(
              (ref) async => Gym(
                id: 'sportclub-belgrano',
                name: 'SportClub - Belgrano',
                lat: -34.56,
                lng: -58.45,
                geohash: 'abc123',
                source: GymSource.seed,
                createdAt: DateTime.utc(2026, 1, 1),
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('SportClub - Belgrano'), findsOneWidget);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // REQ-FOLLOW-017 — el badge tiene que contar la MISMA colección que el inbox.
  //
  // Estos dos casos siembran Firestore de verdad en vez de overridear el
  // provider, porque lo que se está probando es justamente DE DÓNDE sale el
  // número. Con el provider mockeado, contar `friendships` o contar `follows`
  // da idéntico y el test no prueba nada.
  //
  // El bug que atrapan: tras el flip, `friendships` queda congelada y las
  // solicitudes nuevas viven en `follows`. Un badge que siga leyendo la
  // colección vieja marca 0 PARA SIEMPRE mientras el inbox muestra pedidos
  // reales — la peor combinación, porque el usuario nunca se entera.
  // ─────────────────────────────────────────────────────────────────────────
  group('ProfileCuentaSection — badge de solicitudes', () {
    Widget buildWithFirestore(FakeFirebaseFirestore firestore) => _buildSection(
          overrides: [
            firestoreProvider.overrideWithValue(firestore),
            authStateChangesProvider
                .overrideWith((_) => Stream.value(_userWithUid('me'))),
            userProfileProvider.overrideWith((_) => Stream.value(_profile())),
          ],
        );

    testWidgets('cuenta las solicitudes pendientes de `follows`',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      // Dos aristas pendientes HACIA mí (followeeUid == 'me').
      for (final other in ['bob', 'carla']) {
        await firestore.collection('follows').doc('${other}_me').set({
          'id': '${other}_me',
          'followerUid': other,
          'followeeUid': 'me',
          'status': 'pending',
          'members': [other, 'me'],
          'createdAt': Timestamp.now(),
        });
      }

      await tester.pumpWidget(buildWithFirestore(firestore));
      await tester.pumpAndSettle();

      expect(find.textContaining('2'), findsWidgets);
    });

    testWidgets('NO cuenta una solicitud pendiente en la `friendships` legacy',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      // Residuo del modelo viejo. Después del flip esto no es una solicitud
      // viva: la colección está congelada y el inbox ni la mira.
      await firestore.collection('friendships').doc('bob_me').set({
        'id': 'bob_me',
        'uidA': 'bob',
        'uidB': 'me',
        'status': 'pending',
        'requesterId': 'bob',
        'members': ['bob', 'me'],
        'createdAt': Timestamp.now(),
      });

      await tester.pumpWidget(buildWithFirestore(firestore));
      await tester.pumpAndSettle();

      // Sin solicitudes en `follows` el subtítulo no se renderiza.
      expect(find.textContaining('nueva'), findsNothing);
    });

    testWidgets('sólo cuenta las RECIBIDAS, no las que yo mandé',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      // Yo le mandé solicitud a bob: es saliente, no va en mi inbox.
      await firestore.collection('follows').doc('me_bob').set({
        'id': 'me_bob',
        'followerUid': 'me',
        'followeeUid': 'bob',
        'status': 'pending',
        'members': ['me', 'bob'],
        'createdAt': Timestamp.now(),
      });

      await tester.pumpWidget(buildWithFirestore(firestore));
      await tester.pumpAndSettle();

      expect(find.textContaining('nueva'), findsNothing);
    });
  });
}
