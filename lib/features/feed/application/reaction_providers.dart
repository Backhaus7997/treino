import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/reaction_repository.dart';
import '../domain/reaction.dart';
import '../domain/reaction_counts_converter.dart';
import '../domain/reaction_type.dart';

final reactionRepositoryProvider = Provider<ReactionRepository>(
  (ref) => ReactionRepository(firestore: ref.watch(firestoreProvider)),
);

final myReactionProvider =
    StreamProvider.autoDispose.family<Reaction?, String>((ref, postId) async* {
  final user = await ref.watch(authStateChangesProvider.future);
  if (user == null) {
    yield null;
    return;
  }
  yield* ref.watch(reactionRepositoryProvider).watchMyReaction(
        postId: postId,
        uid: user.uid,
      );
});

final reactionCountsProvider =
    StreamProvider.autoDispose.family<Map<ReactionType, int>, String>(
  (ref, postId) {
    const converter = ReactionCountsConverter();
    return ref
        .watch(firestoreProvider)
        .collection('posts')
        .doc(postId)
        .snapshots()
        .map((snap) => converter
            .fromJson(snap.data()?['reactionCounts'] as Map<String, dynamic>?));
  },
);

class ReactionActionsNotifier {
  ReactionActionsNotifier(this._ref);

  final Ref _ref;

  Future<void> toggle({
    required String postId,
    required ReactionType type,
  }) async {
    final user = await _ref.read(authStateChangesProvider.future);
    if (user == null) {
      throw StateError('A signed-in user is required to react');
    }

    final existing = await _ref.read(myReactionProvider(postId).future);
    final repository = _ref.read(reactionRepositoryProvider);

    if (existing?.type == type) {
      await repository.removeReaction(postId: postId, uid: user.uid);
      return;
    }

    await repository.react(postId: postId, uid: user.uid, type: type);
  }
}

final reactionActionsProvider = Provider<ReactionActionsNotifier>(
  (ref) => ReactionActionsNotifier(ref),
);
