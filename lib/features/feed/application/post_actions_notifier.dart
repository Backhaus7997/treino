import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/post.dart';
import 'feed_screen_providers.dart';
import 'post_providers.dart';

/// Post-level mutations (edit/delete) that a post's own author can trigger
/// from [PostCard]'s overflow menu.
///
/// Kept separate from [post_providers.dart] (read-only feed providers) and
/// [create_post_notifier.dart] (compose-screen state) since these are
/// one-shot fire-and-forget actions with no owned state of their own.
class PostActionsNotifier {
  PostActionsNotifier(this._ref);

  final Ref _ref;

  /// Deletes [postId] and invalidates every feed provider so the post
  /// disappears from any screen currently rendering it.
  Future<void> deletePost(String postId) async {
    await _ref.read(postRepositoryProvider).delete(postId);
    invalidateAllFeedProviders(_ref);
  }

  /// Updates [post] (text/privacy/routineTag only — see
  /// `PostRepository.update`) and invalidates every feed provider so the
  /// change shows up wherever the post is rendered.
  Future<Post> updatePost(Post post) async {
    final updated = await _ref.read(postRepositoryProvider).update(post);
    invalidateAllFeedProviders(_ref);
    return updated;
  }
}

final postActionsProvider = Provider<PostActionsNotifier>(
  (ref) => PostActionsNotifier(ref),
);
