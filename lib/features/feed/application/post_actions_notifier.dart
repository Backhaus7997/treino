import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/post_photo_upload_service.dart';
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

  /// Deletes [post] and invalidates every feed provider so it disappears
  /// from any screen currently rendering it.
  ///
  /// If [post] has a photo, the Storage object is deleted FIRST, before the
  /// Firestore doc. Deleting the doc without confirming the photo is gone
  /// would drop the post from every feed while `postPhotos/{uid}/{postId}`
  /// stays live and downloadable by any authenticated user (storage.rules)
  /// — the same failure mode documented for account deletion in
  /// `functions/src/cascade/storage.ts`.
  ///
  /// [PostPhotoUploadService.deleteByDownloadUrl] already tells apart the two
  /// cases that matter here: it returns `false` (NOT a failure) when the
  /// object is simply already gone (`object-not-found` — e.g. a legacy post
  /// whose photo was removed some other way), and rethrows for anything else
  /// (permission, network — a real failure). This method lets that rethrow
  /// propagate and deliberately never reaches `PostRepository.delete` in that
  /// case: the post stays intact so the author can retry, instead of a
  /// silent partial delete (post gone, photo still exposed) — that silence
  /// is the bug this guards against. `PostCard._confirmDelete` already turns
  /// any thrown error here into its existing "no pudimos borrar" SnackBar,
  /// so no UI change was needed for the author to find out.
  Future<void> deletePost(Post post) async {
    final photoUrl = post.photoUrl;
    if (photoUrl != null) {
      await _ref
          .read(postPhotoUploadServiceProvider)
          .deleteByDownloadUrl(photoUrl);
    }
    await _ref.read(postRepositoryProvider).delete(post.id);
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
