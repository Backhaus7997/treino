// Tests del composer del post de entreno (share-composer PR2): precarga del
// texto default, edición, cap de 280, preview del snapshot y wiring de
// publicar. El picker de fotos no se ejercita acá — depende de un platform
// channel; lo que sí se pinea es que shareWorkout recibe el texto editado y
// el localPhotoPath (null cuando no se adjuntó nada).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/presentation/widgets/workout_snapshot_detail.dart';
import 'package:treino/features/workout/application/post_workout_notifier.dart';
import 'package:treino/features/workout/application/session_muscle_distribution.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/features/workout/presentation/share_workout_composer_screen.dart';
import 'package:treino/features/insights/domain/radar_axis.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:firebase_auth/firebase_auth.dart';

class _MockUser extends Mock implements User {
  _MockUser({required String uid}) : _uid = uid;
  final String _uid;
  @override
  String get uid => _uid;
}

/// Notifier stub que captura los argumentos de shareWorkout.
class _CapturingNotifier extends PostWorkoutNotifier {
  String? capturedText;
  String? capturedPhotoPath;
  int? capturedExerciseCount;
  int calls = 0;
  bool shouldThrow = false;

  @override
  Future<void> shareWorkout(
    Session session, {
    required String text,
    required int exerciseCount,
    String? localPhotoPath,
  }) async {
    calls++;
    capturedText = text;
    capturedExerciseCount = exerciseCount;
    capturedPhotoPath = localPhotoPath;
    if (shouldThrow) {
      final err = Exception('fail');
      state = AsyncError(err, StackTrace.empty);
      throw err;
    }
    state = const AsyncData(null);
  }
}

Session _session() => Session(
      id: 's1',
      uid: 'u1',
      routineId: 'r1',
      routineName: 'Push',
      startedAt: DateTime.utc(2026, 7, 28, 10, 0),
      finishedAt: DateTime.utc(2026, 7, 28, 10, 30),
      totalVolumeKg: 1200,
      durationMin: 30,
      status: SessionStatus.finished,
      dayNumber: 1,
      wasFullyCompleted: true,
    );

SetLog _log(String name, {String id = 'e1', int setNumber = 1}) => SetLog(
      id: '$name-$setNumber',
      exerciseId: id,
      exerciseName: name,
      setNumber: setNumber,
      reps: 10,
      weightKg: 50,
      completedAt: DateTime.utc(2026, 7, 28, 10, 15),
    );

const _defaultText = '¡Terminé mi entreno! 💪';

Widget _wrap({
  required _CapturingNotifier notifier,
  List<SetLog>? setLogs,
  Session? session,
}) {
  final router = GoRouter(
    initialLocation: '/composer',
    routes: [
      GoRoute(
        path: '/composer',
        builder: (_, __) => const ShareWorkoutComposerScreen(sessionId: 's1'),
      ),
      GoRoute(
        path: '/workout',
        builder: (_, __) => const Scaffold(body: Text('workout-screen')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authStateChangesProvider.overrideWith(
        (ref) => Stream.value(_MockUser(uid: 'u1')),
      ),
      sessionSummaryProvider.overrideWith((ref, key) async => (
            session: session ?? _session(),
            setLogs: setLogs ??
                [
                  _log('Press banca', id: 'e1', setNumber: 1),
                  _log('Press banca', id: 'e1', setNumber: 2),
                  _log('Sentadilla', id: 'e2'),
                ],
          )),
      sessionMuscleDistributionProvider.overrideWith((ref, key) async => (
            setsByAxis: {RadarAxis.chest: 2, RadarAxis.legs: 1},
            volumeKgByAxis: {RadarAxis.chest: 1000.0, RadarAxis.legs: 500.0},
          )),
      postWorkoutNotifierProvider.overrideWith(() => notifier),
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      locale: const Locale('es', 'AR'),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      routerConfig: router,
    ),
  );
}

void main() {
  late _CapturingNotifier notifier;

  setUp(() => notifier = _CapturingNotifier());

  group('ShareWorkoutComposerScreen', () {
    testWidgets('precarga el texto default editable', (tester) async {
      await tester.pumpWidget(_wrap(notifier: notifier));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, _defaultText);
      expect(find.text('COMPARTIR ENTRENO'), findsOneWidget);
    });

    testWidgets('acota el texto a 280 caracteres', (tester) async {
      await tester.pumpWidget(_wrap(notifier: notifier));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.maxLength, 280);
    });

    testWidgets('publica el texto EDITADO, no el default', (tester) async {
      await tester.pumpWidget(_wrap(notifier: notifier));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Rompí todo hoy');
      await tester.pump();
      await tester.tap(find.text('PUBLICAR'));
      await tester.pumpAndSettle();

      expect(notifier.calls, 1);
      expect(notifier.capturedText, 'Rompí todo hoy');
      // Sin foto adjuntada, el flujo viejo queda intacto.
      expect(notifier.capturedPhotoPath, isNull);
    });

    testWidgets('publica el default si el usuario no edita nada',
        (tester) async {
      await tester.pumpWidget(_wrap(notifier: notifier));
      await tester.pumpAndSettle();

      await tester.tap(find.text('PUBLICAR'));
      await tester.pumpAndSettle();

      expect(notifier.capturedText, _defaultText);
    });

    testWidgets('pasa la cuenta de ejercicios DISTINTOS', (tester) async {
      await tester.pumpWidget(_wrap(notifier: notifier));
      await tester.pumpAndSettle();

      await tester.tap(find.text('PUBLICAR'));
      await tester.pumpAndSettle();

      // 3 sets, 2 exerciseId distintos.
      expect(notifier.capturedExerciseCount, 2);
    });

    testWidgets('con el texto vacío no publica', (tester) async {
      await tester.pumpWidget(_wrap(notifier: notifier));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      await tester.tap(find.text('PUBLICAR'));
      await tester.pump();

      expect(notifier.calls, 0);
    });

    testWidgets('previsualiza el detalle que verá el resto', (tester) async {
      await tester.pumpWidget(_wrap(notifier: notifier));
      await tester.pumpAndSettle();

      expect(find.byType(WorkoutSnapshotDetail), findsOneWidget);
      expect(find.byType(MuscleDistributionBars), findsOneWidget);
      expect(find.text('Press banca'), findsOneWidget);
      expect(find.text('Sentadilla'), findsOneWidget);
      expect(find.text('PECHO'), findsOneWidget);
    });

    testWidgets('ofrece adjuntar una foto', (tester) async {
      await tester.pumpWidget(_wrap(notifier: notifier));
      await tester.pumpAndSettle();

      expect(find.text('AGREGAR FOTO'), findsOneWidget);
    });

    testWidgets('al publicar OK navega a /workout', (tester) async {
      await tester.pumpWidget(_wrap(notifier: notifier));
      await tester.pumpAndSettle();

      await tester.tap(find.text('PUBLICAR'));
      await tester.pumpAndSettle();

      expect(find.text('workout-screen'), findsOneWidget);
    });

    testWidgets('si publicar falla se queda en el composer con el texto',
        (tester) async {
      notifier.shouldThrow = true;
      await tester.pumpWidget(_wrap(notifier: notifier));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Mi entreno');
      await tester.pump();
      await tester.tap(find.text('PUBLICAR'));
      await tester.pumpAndSettle();

      expect(find.text('workout-screen'), findsNothing);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'Mi entreno');
    });
  });
}
