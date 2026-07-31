// Cobertura de `invalidateAllFeedProviders` (bug share-workout, 2026-07-28):
// las families del feed (feedForFriendsProvider / feedForGymProvider) NO son
// autoDispose y cachean el resultado del query por key. `ref.invalidate` no
// cascada a las dependencias, así que invalidar sólo los wrappers dejaba el
// query cacheado hasta reiniciar la app. El helper debe tumbar families Y
// wrappers para que un post recién escrito aparezca de inmediato.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/create_post_notifier.dart';
import 'package:treino/features/feed/application/feed_screen_providers.dart';
import 'package:treino/features/feed/application/post_providers.dart';
import 'package:treino/features/feed/data/post_repository.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_page.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

class _MockUser extends Mock implements User {
  _MockUser({required String uid}) : _uid = uid;
  final String _uid;
  @override
  String get uid => _uid;
}

/// Repo fake in-memory que cuenta cuántas veces se emite cada query de feed,
/// para poder afirmar re-fetch real (y no caché servida por la family).
class _CountingPostRepository extends Fake implements PostRepository {
  final List<Post> store = [];
  int feedForFriendsCalls = 0;
  int feedForGymCalls = 0;
  int feedPublicCalls = 0;

  @override
  Future<Post> create(Post input) async {
    final post = input.copyWith(id: 'post-${store.length + 1}');
    store.add(post);
    return post;
  }

  @override
  Future<PostPage> feedForFriends(
    List<String> friendUids, {
    int limit = 20,
    DateTime? after,
  }) async {
    feedForFriendsCalls++;
    final posts = store
        .where((p) =>
            p.privacy == PostPrivacy.friends &&
            friendUids.contains(p.authorUid))
        .toList();
    return PostPage(posts: posts, nextCursor: null, hasMore: false);
  }

  @override
  Future<PostPage> feedForGym(
    String gymId, {
    int limit = 20,
    DateTime? after,
  }) async {
    feedForGymCalls++;
    final posts = store
        .where((p) => p.privacy == PostPrivacy.gym && p.authorGymId == gymId)
        .toList();
    return PostPage(posts: posts, nextCursor: null, hasMore: false);
  }

  @override
  Future<PostPage> feedPublic({int limit = 20, DateTime? after}) async {
    feedPublicCalls++;
    final posts = store.where((p) => p.privacy == PostPrivacy.public).toList();
    return PostPage(posts: posts, nextCursor: null, hasMore: false);
  }
}

/// Expone un [Ref] real del container para invocar el helper igual que lo
/// hacen los notifiers en producción (mismo patrón que `PostActionsNotifier`,
/// que retiene el Ref de su Provider).
final _probeRefProvider = Provider<Ref>((ref) => ref);

UserProfile _makeProfile({String? gymId}) => UserProfile(
      uid: 'u1',
      email: 'martin@test.com',
      displayName: 'Martín',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      gymId: gymId,
    );

void main() {
  late _CountingPostRepository repo;

  setUp(() {
    repo = _CountingPostRepository();
  });

  group('invalidateAllFeedProviders', () {
    test(
        're-fetchea las tres superficies del feed aunque las keys de las '
        'families no cambien', () async {
      final container = ProviderContainer(
        overrides: [postRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);

      // Instancias vivas con la MISMA key antes y después — el escenario del
      // bug: los amigos/gym del usuario no cambian, sólo hay un post nuevo.
      container.listen(feedForFriendsProvider('u1 u2'), (_, __) {});
      container.listen(feedForGymProvider('g1'), (_, __) {});
      container.listen(feedPublicProvider, (_, __) {});

      await container.read(feedForFriendsProvider('u1 u2').future);
      await container.read(feedForGymProvider('g1').future);
      await container.read(feedPublicProvider.future);
      expect(repo.feedForFriendsCalls, 1);
      expect(repo.feedForGymCalls, 1);
      expect(repo.feedPublicCalls, 1);

      invalidateAllFeedProviders(container.read(_probeRefProvider));

      await container.read(feedForFriendsProvider('u1 u2').future);
      await container.read(feedForGymProvider('g1').future);
      await container.read(feedPublicProvider.future);
      expect(
        repo.feedForFriendsCalls,
        2,
        reason: 'la family de amigos debe re-emitir el query con la misma key',
      );
      expect(
        repo.feedForGymCalls,
        2,
        reason: 'la family del gym debe re-emitir el query con la misma key',
      );
      expect(repo.feedPublicCalls, 2);
    });
  });

  group('CreatePostNotifier → feed refresh (sin reiniciar la app)', () {
    test(
        'un post nuevo con privacy=gym aparece en myGymFeedProvider '
        'inmediatamente después de submit', () async {
      final container = ProviderContainer(
        overrides: [
          authStateChangesProvider.overrideWith(
            (ref) => Stream.value(_MockUser(uid: 'u1')),
          ),
          userProfileProvider.overrideWith(
            (ref) => Stream.value(_makeProfile(gymId: 'g1')),
          ),
          postRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      container.listen(myGymFeedProvider, (_, __) {});
      container.listen(createPostNotifierProvider(null), (_, __) {});

      // El feed MI GYM ya cargó antes de publicar.
      final before = await container.read(myGymFeedProvider.future);
      expect(before, isEmpty);

      await container.read(createPostNotifierProvider(null).future);
      final notifier =
          container.read(createPostNotifierProvider(null).notifier);
      notifier.setText('Nuevo PR de sentadilla 140kg');
      notifier.setPrivacy(PostPrivacy.gym);
      final ok = await notifier.submit();
      expect(ok, isTrue);

      final after = await container.read(myGymFeedProvider.future);
      expect(after, isNotNull);
      expect(
        after!.map((p) => p.text),
        contains('Nuevo PR de sentadilla 140kg'),
        reason: 'el post recién publicado debe verse sin reiniciar la app',
      );
    });
  });
}
