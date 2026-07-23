import 'package:characters/characters.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../profile/application/user_providers.dart';
import '../domain/post.dart';
import '../domain/post_privacy.dart';
import '../domain/routine_tag.dart';
import 'feed_screen_providers.dart';
import 'post_actions_notifier.dart';
import 'post_providers.dart';

/// Maximum character count for a post (grapheme clusters).
const int kMaxPostChars = 280;

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

@immutable
class CreatePostState {
  const CreatePostState({
    this.text = '',
    this.privacy = PostPrivacy.friends,
    this.isSubmitting = false,
    this.errorMessage,
    this.editingPost,
    this.routineTag,
  });

  final String text;
  final PostPrivacy privacy;
  final bool isSubmitting;
  final String? errorMessage;

  /// The post being edited, or `null` when composing a brand-new post.
  /// Drives edit-mode UI (title/submit label) and routes [submit] to
  /// `PostActionsNotifier.updatePost` instead of `PostRepository.create`.
  final Post? editingPost;

  /// The routine the user chose to tag on this post, or `null` when none is
  /// attached. Rendered as a navigable accent chip on the published card
  /// (mirrors the share-workout flow).
  final RoutineTag? routineTag;

  bool get isEditing => editingPost != null;

  /// True when the post can be submitted: text is non-empty, within the char
  /// limit, and not already submitting.
  bool get canSubmit =>
      text.trim().isNotEmpty &&
      text.characters.length <= kMaxPostChars &&
      !isSubmitting;

  CreatePostState copyWith({
    String? text,
    PostPrivacy? privacy,
    bool? isSubmitting,
    String? errorMessage,
    bool clearError = false,
    Post? editingPost,
    RoutineTag? routineTag,
    bool clearRoutineTag = false,
  }) =>
      CreatePostState(
        text: text ?? this.text,
        privacy: privacy ?? this.privacy,
        isSubmitting: isSubmitting ?? this.isSubmitting,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        editingPost: editingPost ?? this.editingPost,
        routineTag: clearRoutineTag ? null : (routineTag ?? this.routineTag),
      );
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

/// Family keyed on the optional post being edited. `null` (the default,
/// via [createPostNotifierProvider]) is the compose-new-post flow; a non-null
/// [Post] pre-fills the form and routes [submit] to an update instead of a
/// create.
class CreatePostNotifier
    extends AutoDisposeFamilyAsyncNotifier<CreatePostState, Post?> {
  @override
  Future<CreatePostState> build(Post? existingPost) async {
    if (existingPost == null) return const CreatePostState();
    // Defense-in-depth: only the author may edit. If a post that isn't the
    // current viewer's arrives here (e.g. a future call site that forgets to
    // gate), fall back to compose-new mode instead of pre-filling someone
    // else's post. The 3-dot menu already gates this, and Firestore rules
    // reject the write — this guards the UI layer too.
    final viewerUid = (await ref.read(authStateChangesProvider.future))?.uid;
    if (viewerUid == null || viewerUid != existingPost.authorUid) {
      return const CreatePostState();
    }
    return CreatePostState(
      text: existingPost.text,
      privacy: existingPost.privacy,
      editingPost: existingPost,
      routineTag: existingPost.routineTag,
    );
  }

  void setText(String value) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(text: value, clearError: true));
  }

  void setPrivacy(PostPrivacy value) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(privacy: value, clearError: true));
  }

  /// Attaches [tag] to the post, or clears the attachment when [tag] is null.
  void setRoutineTag(RoutineTag? tag) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      tag == null
          ? current.copyWith(clearRoutineTag: true, clearError: true)
          : current.copyWith(routineTag: tag, clearError: true),
    );
  }

  /// Submits the post. Returns [true] on success, [false] on any failure.
  ///
  /// When [CreatePostState.isEditing] is true, updates the existing post
  /// (text/privacy/routineTag only) instead of creating a new one.
  ///
  /// Failure cases:
  /// - `canSubmit == false` (text empty / over limit / already submitting)
  /// - viewer not authenticated
  /// - gym privacy selected but user has no gym
  /// - `PostRepository.create()` / `PostActionsNotifier.updatePost()` throws
  Future<bool> submit() async {
    final current = state.valueOrNull;
    if (current == null || !current.canSubmit) return false;

    // Pin del notifier durante todo el envío (linaje #435): este family es
    // autoDispose y el composer puede popearse con el write en vuelo. Sin el
    // pin el notifier muere ahí, y quien vuelve al composer encuentra un
    // formulario vacío como si hubiera perdido el texto — además de que en
    // Riverpod 3.x el ref-después-del-dispose deja de ser un no-op tolerado y
    // pasa a ser error. El link se cierra en el finally: recién ahí vuelve a
    // regir el autoDispose.
    final keepAlive = ref.keepAlive();
    try {
      return await _runSubmit(current);
    } finally {
      keepAlive.close();
    }
  }

  /// Cuerpo del envío. Separado de [submit] para que el manejo del ciclo de
  /// vida (el pin de arriba) no se mezcle con la lógica de publicación.
  Future<bool> _runSubmit(CreatePostState current) async {
    // Mark as submitting immediately — prevents double-tap (SCENARIO-228)
    state = AsyncData(
      current.copyWith(isSubmitting: true, clearError: true),
    );

    // Auth gate
    final authUser = await ref.read(authStateChangesProvider.future);
    if (authUser == null) {
      state = AsyncData(
        current.copyWith(
          isSubmitting: false,
          errorMessage: 'No pudimos publicar tu post. Iniciá sesión.',
        ),
      );
      return false;
    }

    // Profile read (for author fields + gym gate)
    final profile = await ref.read(userProfileProvider.future);

    // Gym gate (defense-in-depth — UI already disables the pill)
    if (current.privacy == PostPrivacy.gym && (profile?.gymId == null)) {
      state = AsyncData(
        current.copyWith(
          isSubmitting: false,
          errorMessage: 'Asociate a un gym para postear acá.',
        ),
      );
      return false;
    }

    final editingPost = current.editingPost;
    if (editingPost != null) {
      try {
        await ref.read(postActionsProvider).updatePost(
              editingPost.copyWith(
                text: current.text.trim(),
                privacy: current.privacy,
                routineTag: current.routineTag,
              ),
            );
        state = AsyncData(current.copyWith(isSubmitting: false));
        return true;
      } catch (_) {
        state = AsyncData(
          current.copyWith(
            isSubmitting: false,
            errorMessage: 'No pudimos guardar los cambios. Intentá de nuevo.',
          ),
        );
        return false;
      }
    }

    try {
      final post = Post(
        id: '',
        authorUid: authUser.uid,
        authorDisplayName: profile?.displayName ?? 'Anónimo',
        authorAvatarUrl: profile?.avatarUrl,
        authorGymId: profile?.gymId,
        text: current.text.trim(),
        routineTag: current.routineTag,
        privacy: current.privacy,
        createdAt: DateTime.now().toUtc(),
      );

      await ref.read(postRepositoryProvider).create(post);

      // Invalidate all 3 feed providers unconditionally (ADR-CP-006)
      ref.invalidate(myFriendsFeedProvider);
      ref.invalidate(feedPublicProvider);
      ref.invalidate(myGymFeedProvider);

      // Reset state
      state = const AsyncData(CreatePostState());
      return true;
    } catch (_) {
      state = AsyncData(
        current.copyWith(
          isSubmitting: false,
          errorMessage: 'No pudimos publicar tu post. Intentá de nuevo.',
        ),
      );
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final createPostNotifierProvider = AutoDisposeAsyncNotifierProviderFamily<
    CreatePostNotifier, CreatePostState, Post?>(
  CreatePostNotifier.new,
);
