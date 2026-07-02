import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../data/athlete_file_repository.dart';
import '../domain/athlete_file.dart';

/// Wraps [FirebaseStorage.instance] so tests can inject a fake. Mismo
/// approach que el resto del stack (`firestoreProvider`).
final firebaseStorageProvider = Provider<FirebaseStorage>(
  (ref) => FirebaseStorage.instance,
);

final athleteFileRepositoryProvider = Provider<AthleteFileRepository>(
  (ref) => AthleteFileRepository(
    firestore: ref.watch(firestoreProvider),
    storage: ref.watch(firebaseStorageProvider),
  ),
);

typedef AthleteFileKey = ({String trainerId, String athleteId});

/// Stream reactivo de archivos privados del PF sobre un alumno. Ordenados
/// más nuevos arriba (server-side).
final athleteFilesProvider =
    StreamProvider.autoDispose.family<List<AthleteFile>, AthleteFileKey>(
  (ref, key) => ref
      .watch(athleteFileRepositoryProvider)
      .watch(key.trainerId, key.athleteId),
);
