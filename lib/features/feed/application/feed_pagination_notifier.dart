import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/post.dart';
import '../domain/post_page.dart';

/// Accumulated state for one cursor-paginated feed query.
class FeedPaginationState {
  const FeedPaginationState({
    required this.posts,
    required this.nextCursor,
    required this.hasMore,
    required this.isLoadingMore,
  });

  const FeedPaginationState.empty()
      : posts = const <Post>[],
        nextCursor = null,
        hasMore = false,
        isLoadingMore = false;

  final List<Post> posts;
  final DateTime? nextCursor;
  final bool hasMore;
  final bool isLoadingMore;
}

/// Read-only list facade that preserves the existing `List<Post>` provider API
/// while carrying pagination metadata for feed presentation.
class PaginatedPostList extends UnmodifiableListView<Post> {
  PaginatedPostList(FeedPaginationState state)
      : nextCursor = state.nextCursor,
        hasMore = state.hasMore,
        isLoadingMore = state.isLoadingMore,
        super(state.posts);

  final DateTime? nextCursor;
  final bool hasMore;
  final bool isLoadingMore;
}

/// Shared cursor accumulation for every feed segment.
///
/// Subclasses only decide how a string query key maps to a repository call.
/// Initial loading, concurrent-call suppression, deduplication, refresh, and
/// page-error preservation stay centralized here.
abstract class FeedPaginationNotifier
    extends FamilyAsyncNotifier<FeedPaginationState, String> {
  String? _queryKey;
  bool _loadMoreInFlight = false;
  int _generation = 0;

  Future<PostPage> fetchPage(String queryKey, {DateTime? after});

  @override
  Future<FeedPaginationState> build(String arg) async {
    _queryKey = arg;
    _loadMoreInFlight = false;
    _generation++;
    final page = await fetchPage(arg);
    return _stateFromPage(page);
  }

  /// Loads and appends the next page.
  ///
  /// Concurrent calls are ignored. A later-page failure intentionally leaves
  /// [state] as [AsyncData] with all previously loaded posts intact.
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    final queryKey = _queryKey;
    if (_loadMoreInFlight ||
        current == null ||
        queryKey == null ||
        !current.hasMore) {
      return;
    }

    _loadMoreInFlight = true;
    final generation = _generation;
    state = AsyncData(
      FeedPaginationState(
        posts: current.posts,
        nextCursor: current.nextCursor,
        hasMore: current.hasMore,
        isLoadingMore: true,
      ),
    );

    try {
      final page = await fetchPage(queryKey, after: current.nextCursor);
      if (generation != _generation) return;

      final seenIds = current.posts.map((post) => post.id).toSet();
      final uniqueNextPosts = page.posts
          .where((post) => seenIds.add(post.id))
          .toList(growable: false);

      state = AsyncData(
        FeedPaginationState(
          posts: <Post>[...current.posts, ...uniqueNextPosts],
          nextCursor: page.nextCursor,
          hasMore: page.hasMore,
          isLoadingMore: false,
        ),
      );
    } catch (_) {
      if (generation != _generation) return;
      state = AsyncData(
        FeedPaginationState(
          posts: current.posts,
          nextCursor: current.nextCursor,
          hasMore: current.hasMore,
          isLoadingMore: false,
        ),
      );
    } finally {
      if (generation == _generation) {
        _loadMoreInFlight = false;
      }
    }
  }

  /// Re-fetches page one and discards all accumulated pages on success.
  Future<void> refresh() async {
    final queryKey = _queryKey;
    if (queryKey == null) return;

    final previous = state.valueOrNull;
    final generation = ++_generation;
    _loadMoreInFlight = true;

    try {
      final page = await fetchPage(queryKey);
      if (generation != _generation) return;
      state = AsyncData(_stateFromPage(page));
    } catch (error, stackTrace) {
      if (generation != _generation) return;
      if (previous != null) {
        state = AsyncData(
          FeedPaginationState(
            posts: previous.posts,
            nextCursor: previous.nextCursor,
            hasMore: previous.hasMore,
            isLoadingMore: false,
          ),
        );
        return;
      }
      state = AsyncError(error, stackTrace);
    } finally {
      if (generation == _generation) {
        _loadMoreInFlight = false;
      }
    }
  }

  FeedPaginationState _stateFromPage(PostPage page) {
    final seenIds = <String>{};
    return FeedPaginationState(
      posts: page.posts
          .where((post) => seenIds.add(post.id))
          .toList(growable: false),
      nextCursor: page.nextCursor,
      hasMore: page.hasMore,
      isLoadingMore: false,
    );
  }
}
