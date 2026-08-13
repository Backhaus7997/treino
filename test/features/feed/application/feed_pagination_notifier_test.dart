import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/application/feed_pagination_notifier.dart';
import 'package:treino/features/feed/application/post_providers.dart';
import 'package:treino/features/feed/data/post_repository.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_page.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';

Post _post(String id, int minute) => Post(
      id: id,
      authorUid: 'u1',
      authorDisplayName: 'Test User',
      authorAvatarUrl: null,
      authorGymId: null,
      text: id,
      routineTag: null,
      privacy: PostPrivacy.public,
      createdAt: DateTime.utc(2026, 7, 30, 12, minute),
    );

PostPage _page(
  List<Post> posts, {
  required bool hasMore,
  DateTime? nextCursor,
}) =>
    PostPage(
      posts: posts,
      nextCursor: nextCursor ?? (posts.isEmpty ? null : posts.last.createdAt),
      hasMore: hasMore,
    );

class _FakePostRepository extends PostRepository {
  _FakePostRepository() : super(firestore: FakeFirebaseFirestore());

  final List<DateTime?> requestedCursors = [];
  late Future<PostPage> Function(DateTime? after) onFeedPublic;

  @override
  Future<PostPage> feedPublic({int limit = 20, DateTime? after}) {
    requestedCursors.add(after);
    return onFeedPublic(after);
  }
}

void main() {
  late _FakePostRepository repository;
  late ProviderContainer container;

  setUp(() {
    repository = _FakePostRepository();
    container = ProviderContainer(
      overrides: [postRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
  });

  Future<FeedPaginationState> readInitial() {
    return container.read(
      feedPaginationProvider(publicFeedPaginationKey).future,
    );
  }

  PostFeedPaginationNotifier readNotifier() {
    return container.read(
      feedPaginationProvider(publicFeedPaginationKey).notifier,
    );
  }

  test('loadMore accumulates the first and second pages in order', () async {
    final first = _page([_post('p3', 3), _post('p2', 2)], hasMore: true);
    final second = _page([_post('p1', 1)], hasMore: false);
    repository.onFeedPublic = (after) async => after == null ? first : second;

    await readInitial();
    await readNotifier().loadMore();

    final state = container
        .read(feedPaginationProvider(publicFeedPaginationKey))
        .requireValue;
    expect(state.posts.map((post) => post.id), ['p3', 'p2', 'p1']);
  });

  test('loadMore deduplicates repeated post ids across pages', () async {
    final duplicate = _post('p2', 2);
    final first = _page([_post('p3', 3), duplicate], hasMore: true);
    final second = _page([duplicate, _post('p1', 1)], hasMore: false);
    repository.onFeedPublic = (after) async => after == null ? first : second;

    await readInitial();
    await readNotifier().loadMore();

    final state = container
        .read(feedPaginationProvider(publicFeedPaginationKey))
        .requireValue;
    expect(state.posts.map((post) => post.id), ['p3', 'p2', 'p1']);
  });

  test('concurrent loadMore calls issue only one repository request', () async {
    final secondPage = Completer<PostPage>();
    repository.onFeedPublic = (after) {
      if (after == null) {
        return Future.value(_page([_post('p2', 2)], hasMore: true));
      }
      return secondPage.future;
    };
    await readInitial();

    final notifier = readNotifier();
    final firstCall = notifier.loadMore();
    final secondCall = notifier.loadMore();
    expect(repository.requestedCursors, hasLength(2));

    secondPage.complete(_page([_post('p1', 1)], hasMore: false));
    await Future.wait([firstCall, secondCall]);
    expect(repository.requestedCursors, hasLength(2));
  });

  test('loadMore does not query when hasMore is false', () async {
    repository.onFeedPublic =
        (_) async => _page([_post('p1', 1)], hasMore: false);
    await readInitial();

    await readNotifier().loadMore();

    expect(repository.requestedCursors, [null]);
  });

  test('a second-page error preserves the first page', () async {
    repository.onFeedPublic = (after) async {
      if (after == null) {
        return _page([_post('p2', 2)], hasMore: true);
      }
      throw StateError('page 2 failed');
    };
    await readInitial();

    await readNotifier().loadMore();

    final state = container
        .read(feedPaginationProvider(publicFeedPaginationKey))
        .requireValue;
    expect(state.posts.map((post) => post.id), ['p2']);
    expect(state.isLoadingMore, isFalse);
    expect(state.hasMore, isTrue);
  });

  test('refresh replaces accumulated pages with a new first page', () async {
    var firstPageRequestCount = 0;
    repository.onFeedPublic = (after) async {
      if (after != null) {
        return _page([_post('old-1', 1)], hasMore: false);
      }
      firstPageRequestCount++;
      return firstPageRequestCount == 1
          ? _page([_post('old-2', 2)], hasMore: true)
          : _page([_post('new-3', 3)], hasMore: false);
    };
    await readInitial();
    final notifier = readNotifier();
    await notifier.loadMore();

    await notifier.refresh();

    final state = container
        .read(feedPaginationProvider(publicFeedPaginationKey))
        .requireValue;
    expect(state.posts.map((post) => post.id), ['new-3']);
    expect(state.hasMore, isFalse);
  });
}
