import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/reaction_providers.dart';
import 'package:treino/features/feed/data/reaction_repository.dart';
import 'package:treino/features/feed/domain/reaction.dart';
import 'package:treino/features/feed/domain/reaction_type.dart';

class MockReactionRepository extends Mock implements ReactionRepository {}

class MockUser extends Mock implements User {
  MockUser(this._uid);

  final String _uid;

  @override
  String get uid => _uid;
}

void main() {
  late MockReactionRepository repository;
  late MockUser user;

  setUpAll(() {
    registerFallbackValue(ReactionType.strong);
  });

  setUp(() {
    repository = MockReactionRepository();
    user = MockUser('user-1');
    when(
      () => repository.react(
        postId: any(named: 'postId'),
        uid: any(named: 'uid'),
        type: any(named: 'type'),
      ),
    ).thenAnswer((_) async {});
    when(
      () => repository.removeReaction(
        postId: any(named: 'postId'),
        uid: any(named: 'uid'),
      ),
    ).thenAnswer((_) async {});
  });

  ProviderContainer containerWith(Reaction? existing) {
    return ProviderContainer(
      overrides: [
        authStateChangesProvider.overrideWith((ref) => Stream.value(user)),
        reactionRepositoryProvider.overrideWithValue(repository),
        myReactionProvider.overrideWith(
          (ref, postId) => Stream.value(existing),
        ),
      ],
    );
  }

  test('toggle creates a reaction when none exists', () async {
    final container = containerWith(null);
    addTearDown(container.dispose);

    await container.read(reactionActionsProvider).toggle(
          postId: 'post-1',
          type: ReactionType.strong,
        );

    verify(
      () => repository.react(
        postId: 'post-1',
        uid: 'user-1',
        type: ReactionType.strong,
      ),
    ).called(1);
    verifyNever(
      () => repository.removeReaction(
        postId: any(named: 'postId'),
        uid: any(named: 'uid'),
      ),
    );
  });

  test('toggle removes a reaction when the selected type matches', () async {
    final container = containerWith(
      Reaction(
        uid: 'user-1',
        type: ReactionType.fire,
        createdAt: DateTime.utc(2026),
      ),
    );
    addTearDown(container.dispose);

    await container.read(reactionActionsProvider).toggle(
          postId: 'post-1',
          type: ReactionType.fire,
        );

    verify(
      () => repository.removeReaction(postId: 'post-1', uid: 'user-1'),
    ).called(1);
    verifyNever(
      () => repository.react(
        postId: any(named: 'postId'),
        uid: any(named: 'uid'),
        type: any(named: 'type'),
      ),
    );
  });

  test('toggle changes type when a different reaction exists', () async {
    final container = containerWith(
      Reaction(
        uid: 'user-1',
        type: ReactionType.clap,
        createdAt: DateTime.utc(2026),
      ),
    );
    addTearDown(container.dispose);

    await container.read(reactionActionsProvider).toggle(
          postId: 'post-1',
          type: ReactionType.strong,
        );

    verify(
      () => repository.react(
        postId: 'post-1',
        uid: 'user-1',
        type: ReactionType.strong,
      ),
    ).called(1);
    verifyNever(
      () => repository.removeReaction(
        postId: any(named: 'postId'),
        uid: any(named: 'uid'),
      ),
    );
  });
}
