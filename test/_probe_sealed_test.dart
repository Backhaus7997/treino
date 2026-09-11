import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mocktail/mocktail.dart';

class MockCollectionReference extends Mock
    implements CollectionReference<Map<String, Object?>> {}

class MockQuery extends Mock implements Query<Map<String, Object?>> {}

class MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, Object?>> {}

class MockQueryDocumentSnapshot extends Mock
    implements QueryDocumentSnapshot<Map<String, Object?>> {}

class MockDocumentSnapshot extends Mock
    implements DocumentSnapshot<Map<String, Object?>> {}

class MockSnapshotMetadata extends Mock implements SnapshotMetadata {}

class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

void main() {}
