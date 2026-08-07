// Regresión del pull-to-refresh del feed (2026-07-28): _AmigosBody y
// _MiGymBody refrescaban SOLO el wrapper (myFollowingFeedProvider /
// myGymFeedProvider), pero las families subyacentes (feedForFriendsProvider /
// feedForGymProvider) NO son autoDispose y cachean el query por key —
// y ref.refresh/invalidate no cascada a dependencias. Con la misma key
// (mismos amigos / mismo gym) el gesto servía la lista cacheada: el query a
// Firestore no se re-emitía y los posts nuevos de otros jamás aparecían.
//
// Estos tests montan el FeedScreen REAL (wrappers y families de producción)
// contra un repo fake con contador y afirman que el pull-to-refresh — y el
// Reintentar tras error, mismo agujero — re-emiten el query con la MISMA key.

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/feed/application/feed_screen_providers.dart';
import 'package:treino/features/feed/application/follow_providers.dart';
import 'package:treino/features/feed/application/post_providers.dart';
import 'package:treino/features/feed/data/post_repository.dart';
import 'package:treino/features/feed/domain/feed_segment.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_page.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/feed/feed_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockUser extends Mock implements User {
  _MockUser({required String uid}) : _uid = uid;
  final String _uid;
  @override
  String get uid => _uid;
}

/// Repo fake in-memory que registra cada emisión de query con su key, para
/// poder afirmar re-fetch real con key idéntica (y no caché servida por la
/// family). `feedForGym` no filtra por `authorGymId` a propósito: los posts
/// del test lo dejan en null para que PostCard no watchee `gymByIdProvider`.
class _CountingPostRepository extends Fake implements PostRepository {
  final List<Post> store = [];
  final List<List<String>> friendsQueryUids = [];
  final List<String> gymQueryIds = [];
  bool failNextFriendsQuery = false;

  @override
  Future<PostPage> feedForFriends(
    List<String> friendUids, {
    int limit = 20,
    DateTime? after,
  }) async {
    friendsQueryUids.add(List.of(friendUids));
    if (failNextFriendsQuery) {
      failNextFriendsQuery = false;
      throw Exception('feed down');
    }
    final posts = store
        .where(
          (p) =>
              p.privacy == PostPrivacy.followers &&
              friendUids.contains(p.authorUid),
        )
        .toList();
    return PostPage(posts: posts, nextCursor: null, hasMore: false);
  }

  @override
  Future<PostPage> feedForGym(
    String gymId, {
    int limit = 20,
    DateTime? after,
  }) async {
    gymQueryIds.add(gymId);
    final posts = store.where((p) => p.privacy == PostPrivacy.gym).toList();
    return PostPage(posts: posts, nextCursor: null, hasMore: false);
  }
}

Post _makePost({
  String id = 'p1',
  String authorUid = 'u2',
  String text = 'Hola mundo',
  PostPrivacy privacy = PostPrivacy.followers,
}) =>
    Post(
      id: id,
      authorUid: authorUid,
      authorDisplayName: 'Tincho',
      authorAvatarUrl: null,
      authorGymId: null,
      text: text,
      routineTag: null,
      privacy: privacy,
      createdAt: DateTime.utc(2026, 7, 27, 12),
    );

UserProfile _makeProfile({String? gymId}) => UserProfile(
      uid: 'u1',
      email: 'tincho@test.com',
      displayName: 'Tincho',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      gymId: gymId,
    );

List<Override> _overrides(
  _CountingPostRepository repo, {
  required FeedSegment segment,
  String? gymId,
}) =>
    [
      feedSegmentProvider.overrideWith((ref) => segment),
      authStateChangesProvider.overrideWith(
        (ref) => Stream.value(_MockUser(uid: 'u1')),
      ),
      followingProvider('u1').overrideWith((ref) => Stream.value(const ['u2'])),
      userProfileProvider.overrideWith(
        (ref) => Stream.value(_makeProfile(gymId: gymId)),
      ),
      unreadFromFriendsProvider.overrideWith((ref) => 0),
      postRepositoryProvider.overrideWithValue(repo),
    ];

Widget _wrap(List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('es', 'AR'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: const Scaffold(body: FeedScreen()),
      ),
    );

void main() {
  group('AMIGOS: pull-to-refresh re-emite el query', () {
    testWidgets(
        'feed cargado → refresh → segunda emisión con la MISMA key y el '
        'post nuevo visible', (tester) async {
      final repo = _CountingPostRepository();
      await tester.pumpWidget(
        _wrap(_overrides(repo, segment: FeedSegment.amigos)),
      );
      await tester.pumpAndSettle();

      // Feed cargado (vacío): una sola emisión del query.
      expect(find.text('Todavía no hay posts de a quienes seguís'),
          findsOneWidget);
      expect(repo.friendsQueryUids, hasLength(1));

      // Un amigo publica DESPUÉS de la carga — la key (u1+u2) no cambia.
      repo.store.add(
        _makePost(authorUid: 'u2', text: 'PR de peso muerto 180kg'),
      );

      await tester.fling(
        find.text('Todavía no hay posts de a quienes seguís'),
        const Offset(0, 300),
        1000,
      );
      await tester.pumpAndSettle();

      expect(
        repo.friendsQueryUids,
        hasLength(2),
        reason: 'el pull-to-refresh debe re-emitir el query aunque la key '
            'de la family no cambie',
      );
      expect(
        repo.friendsQueryUids.last,
        equals(repo.friendsQueryUids.first),
        reason: 'misma key: mismos amigos antes y después del gesto',
      );
      expect(find.text('PR de peso muerto 180kg'), findsOneWidget);
    });

    testWidgets(
        'Reintentar tras error re-emite el query en vez de servir el error '
        'cacheado por la family', (tester) async {
      final repo = _CountingPostRepository()..failNextFriendsQuery = true;
      await tester.pumpWidget(
        _wrap(_overrides(repo, segment: FeedSegment.amigos)),
      );
      await tester.pumpAndSettle();

      expect(repo.friendsQueryUids, hasLength(1));
      final retry = find.widgetWithText(TextButton, 'Reintentar');
      expect(retry, findsOneWidget);

      repo.store.add(_makePost(authorUid: 'u2', text: 'Volvimos al feed'));
      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(
        repo.friendsQueryUids,
        hasLength(2),
        reason: 'el retry debe tumbar la family: sin eso re-usa el error '
            'cacheado y nunca se recupera',
      );
      expect(find.text('Volvimos al feed'), findsOneWidget);
    });
  });

  group('MI GYM: pull-to-refresh re-emite el query', () {
    testWidgets(
        'feed cargado → refresh → segunda emisión con el MISMO gymId y el '
        'post nuevo visible', (tester) async {
      final repo = _CountingPostRepository();
      await tester.pumpWidget(
        _wrap(_overrides(repo, segment: FeedSegment.gym, gymId: 'g1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Tu gym todavía no tiene posts'), findsOneWidget);
      expect(repo.gymQueryIds, equals(const ['g1']));

      repo.store.add(
        _makePost(
          authorUid: 'u3',
          privacy: PostPrivacy.gym,
          text: 'Nueva máquina de remo en el box',
        ),
      );

      await tester.fling(
        find.text('Tu gym todavía no tiene posts'),
        const Offset(0, 300),
        1000,
      );
      await tester.pumpAndSettle();

      expect(
        repo.gymQueryIds,
        equals(const ['g1', 'g1']),
        reason: 'mismo gym (misma key) y el query igual debe re-emitirse',
      );
      expect(find.text('Nueva máquina de remo en el box'), findsOneWidget);
    });
  });
}
