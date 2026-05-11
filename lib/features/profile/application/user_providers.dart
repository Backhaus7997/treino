import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseFirestore;
import 'package:flutter_riverpod/flutter_riverpod.dart';

// carve-out: profile/application may import auth/application for authStateChangesProvider.
// The inverse (auth importing profile) is forbidden. See design section 4 + REQ-PROF-063.
import '../../auth/application/auth_providers.dart';
import '../data/user_repository.dart';
import '../domain/user_profile.dart';

final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepository(firestore: ref.watch(firestoreProvider)),
);

final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  final authState = ref.watch(authStateChangesProvider);
  return authState.when(
    data: (user) {
      if (user == null) return Stream<UserProfile?>.value(null);
      return ref.watch(userRepositoryProvider).watch(user.uid);
    },
    loading: () => const Stream<UserProfile?>.empty(),
    error: (_, __) => Stream<UserProfile?>.value(null),
  );
});
