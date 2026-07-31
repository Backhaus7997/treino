import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/data/reaction_repository.dart';
import 'package:treino/features/feed/domain/reaction_type.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ReactionRepository repository;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repository = ReactionRepository(firestore: firestore);
  });

  test('react writes the reaction under posts/{postId}/reactions/{uid}',
      () async {
    await repository.react(
      postId: 'post-1',
      uid: 'user-1',
      type: ReactionType.fire,
    );

    final snap = await firestore
        .collection('posts')
        .doc('post-1')
        .collection('reactions')
        .doc('user-1')
        .get();

    expect(snap.exists, isTrue);
    expect(snap.id, 'user-1');
    expect(snap.data()?['type'], 'fire');
    expect(snap.data()?['createdAt'], isNotNull);
  });
}
