// Tests del PostWorkoutNotifier REAL para la parte nueva de shareWorkout
// (share-composer PR1): foto opcional con id pre-alocado, cleanup del
// huérfano cuando create falla, y snapshot best-effort que jamás bloquea
// el share. Complementa post_workout_notifier_test.dart, cuyos escenarios
// legacy corren contra una fake que reimplementa shareWorkout.
//
// Mismo estilo de container que post_workout_share_refresh_test.dart:
// providers overrideados, notifier real.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/post_providers.dart';
import 'package:treino/features/feed/data/post_photo_upload_service.dart';
import 'package:treino/features/feed/data/post_repository.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/insights/domain/radar_axis.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/post_workout_notifier.dart';
import 'package:treino/features/workout/application/session_muscle_distribution.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';

class _MockUser extends Mock implements User {
  _MockUser({required String uid}) : _uid = uid;
  final String _uid;
  @override
  String get uid => _uid;
}

class _FakePostRepository extends Fake implements PostRepository {
  Post? capturedPost;
  bool shouldThrowOnCreate = false;
  int newPostIdCalls = 0;

  @override
  String newPostId() {
    newPostIdCalls++;
    return 'pre-id';
  }

  @override
  Future<Post> create(Post input) async {
    if (shouldThrowOnCreate) throw Exception('create failed');
    capturedPost = input.id.isEmpty ? input.copyWith(id: 'server-id') : input;
    return capturedPost!;
  }
}

class _FakePhotoService extends Fake implements PostPhotoUploadService {
  String? uploadedPath;
  String? uploadedPostId;
  String? deletedUrl;

  @override
  Future<String> upload(String localPath, {required String postId}) async {
    uploadedPath = localPath;
    uploadedPostId = postId;
    return 'https://fake.storage/photo.jpg';
  }

  @override
  Future<bool> deleteByDownloadUrl(String url) async {
    deletedUrl = url;
    return true;
  }
}

UserProfile _makeProfile() => UserProfile(
      uid: 'u1',
      email: 'ana@test.com',
      displayName: 'Ana',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

Session _makeSession() => Session(
      id: 's1',
      uid: 'u1',
      routineId: 'r1',
      routineName: 'Push',
      startedAt: DateTime.utc(2026, 7, 28, 10, 0),
      finishedAt: DateTime.utc(2026, 7, 28, 10, 30),
      totalVolumeKg: 1200.0,
      durationMin: 30,
      status: SessionStatus.finished,
      dayNumber: 1,
      wasFullyCompleted: true,
    );

SetLog _log(String exerciseName, int setNumber) => SetLog(
      id: '$exerciseName-$setNumber',
      exerciseId: 'e-$exerciseName',
      exerciseName: exerciseName,
      setNumber: setNumber,
      reps: 10,
      weightKg: 50,
      completedAt: DateTime.utc(2026, 7, 28, 10, 15),
    );

void main() {
  late _FakePostRepository repo;
  late _FakePhotoService photoService;

  setUp(() {
    repo = _FakePostRepository();
    photoService = _FakePhotoService();
  });

  ProviderContainer makeContainer({
    List<SetLog>? setLogs,
    bool summaryThrows = false,
    bool distributionThrows = false,
  }) {
    final container = ProviderContainer(
      overrides: [
        authStateChangesProvider.overrideWith(
          (ref) => Stream.value(_MockUser(uid: 'u1')),
        ),
        userProfileProvider.overrideWith(
          (ref) => Stream.value(_makeProfile()),
        ),
        postRepositoryProvider.overrideWithValue(repo),
        postPhotoUploadServiceProvider.overrideWithValue(photoService),
        sessionSummaryProvider.overrideWith((ref, key) async {
          if (summaryThrows) throw Exception('summary unavailable');
          return (
            session: _makeSession(),
            setLogs: setLogs ??
                [
                  _log('Press banca', 1),
                  _log('Press banca', 2),
                  _log('Sentadilla', 1)
                ],
          );
        }),
        sessionMuscleDistributionProvider.overrideWith((ref, key) async {
          if (distributionThrows) throw Exception('catálogo caído');
          return (
            setsByAxis: {RadarAxis.chest: 2, RadarAxis.legs: 1},
            volumeKgByAxis: {RadarAxis.chest: 1000.0, RadarAxis.legs: 500.0},
          );
        }),
      ],
    );
    addTearDown(container.dispose);
    container.listen(postWorkoutNotifierProvider, (_, __) {});
    return container;
  }

  Future<void> share(
    ProviderContainer container, {
    String? localPhotoPath,
  }) {
    return container.read(postWorkoutNotifierProvider.notifier).shareWorkout(
          _makeSession(),
          text: '¡Terminé mi entreno! 💪',
          exerciseCount: 2,
          privacy: PostPrivacy.friends,
          localPhotoPath: localPhotoPath,
        );
  }

  group('shareWorkout con foto', () {
    test('pre-aloca el id, sube la foto a ese id y persiste la photoUrl',
        () async {
      final container = makeContainer();

      await share(container, localPhotoPath: '/tmp/foto.jpg');

      expect(photoService.uploadedPath, '/tmp/foto.jpg');
      expect(photoService.uploadedPostId, 'pre-id');
      expect(repo.capturedPost!.id, 'pre-id');
      expect(repo.capturedPost!.photoUrl, 'https://fake.storage/photo.jpg');
      expect(photoService.deletedUrl, isNull);
    });

    test('si create falla después de subir, borra el huérfano y relanza',
        () async {
      repo.shouldThrowOnCreate = true;
      final container = makeContainer();

      await expectLater(
        () => share(container, localPhotoPath: '/tmp/foto.jpg'),
        throwsException,
      );

      expect(photoService.uploadedPostId, 'pre-id');
      expect(photoService.deletedUrl, 'https://fake.storage/photo.jpg');
      expect(container.read(postWorkoutNotifierProvider).hasError, isTrue);
    });
  });

  group('reentrancia', () {
    test('dos shareWorkout concurrentes publican UN solo post', () async {
      final container = makeContainer();

      // El gate del botón depende de que la UI vea el AsyncLoading, y eso
      // recién ocurre en el próximo frame: dos taps dentro de esa ventana
      // llegan acá antes de cualquier rebuild. Sin guard, esto subía dos
      // fotos y creaba dos posts.
      final first = share(container, localPhotoPath: '/tmp/foto.jpg');
      final second = share(container, localPhotoPath: '/tmp/foto.jpg');
      await Future.wait([first, second]);

      expect(repo.newPostIdCalls, 1);
      expect(repo.capturedPost, isNotNull);
    });

    test('un share posterior, ya resuelto el primero, sí procede', () async {
      final container = makeContainer();

      await share(container);
      expect(repo.capturedPost, isNotNull);

      repo.capturedPost = null;
      await share(container, localPhotoPath: '/tmp/foto.jpg');

      expect(repo.capturedPost, isNotNull);
      expect(repo.capturedPost!.photoUrl, 'https://fake.storage/photo.jpg');
    });
  });

  group('shareWorkout sin foto', () {
    test('no aloca id ni toca el servicio de fotos — flujo idéntico al viejo',
        () async {
      final container = makeContainer();

      await share(container);

      expect(repo.newPostIdCalls, 0);
      expect(photoService.uploadedPath, isNull);
      expect(repo.capturedPost!.id, 'server-id');
      expect(repo.capturedPost!.photoUrl, isNull);
    });
  });

  group('snapshot best-effort', () {
    test('arma el snapshot agrupado con la distribución muscular', () async {
      final container = makeContainer();

      await share(container);

      final snapshot = repo.capturedPost!.workoutSnapshot!;
      expect(snapshot.exercises, hasLength(2));
      expect(snapshot.exercises[0].exerciseName, 'Press banca');
      expect(snapshot.exercises[0].sets, hasLength(2));
      expect(snapshot.setsByAxis, {'chest': 2, 'legs': 1});
    });

    test('si la distribución muscular falla, el snapshot sale sin ejes',
        () async {
      final container = makeContainer(distributionThrows: true);

      await share(container);

      final snapshot = repo.capturedPost!.workoutSnapshot!;
      expect(snapshot.exercises, hasLength(2));
      expect(snapshot.setsByAxis, isEmpty);
    });

    test('si el summary falla, el share sale igual sin snapshot', () async {
      final container = makeContainer(summaryThrows: true);

      await share(container);

      expect(repo.capturedPost, isNotNull);
      expect(repo.capturedPost!.workoutSnapshot, isNull);
    });

    test('sesión sin sets → post sin snapshot', () async {
      final container = makeContainer(setLogs: const []);

      await share(container);

      expect(repo.capturedPost!.workoutSnapshot, isNull);
    });
  });
}
