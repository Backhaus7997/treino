import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_background.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/exercise_asset_image.dart';
import 'package:treino/core/widgets/firebase_storage_video_player.dart';
import 'package:treino/core/widgets/motion/treino_shimmer.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/workout/application/exercise_progression_aggregator.dart';
import 'package:treino/features/workout/application/exercise_progression_providers.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/exercise_progression.dart';
import 'package:treino/features/workout/presentation/exercise_detail_screen.dart';
import 'package:treino/features/workout/presentation/widgets/personal_records_list.dart';
import 'package:treino/features/workout/presentation/widgets/stat_tile.dart';
import 'package:treino/features/workout/presentation/widgets/technique_instruction_item.dart';
import 'package:treino/l10n/app_l10n.dart';

/// [uid] feeds [currentUidProvider] — null (default) mirrors the signed-out
/// state, which makes the personal-stats providers short-circuit to empty
/// data without ever touching Firestore/Firebase (their empty-uid guard).
Widget _wrapWithOverrides(
  Widget w,
  List<Override> overrides, {
  String? uid,
}) =>
    ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue(uid),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(body: w),
      ),
    );

Exercise _makeExercise({
  String id = 'bench-press',
  String name = 'Bench Press',
  String muscleGroup = 'Pecho',
  String category = 'compound',
  List<String>? techniqueInstructions = const ['Cue 1', 'Cue 2', 'Cue 3'],
  String? videoUrl,
}) =>
    Exercise(
      id: id,
      name: name,
      muscleGroup: muscleGroup,
      category: category,
      techniqueInstructions: techniqueInstructions,
      videoUrl: videoUrl,
    );

/// A playable Firebase Storage URL — selects the [_VideoHeroStrip] path
/// (native inline player). Init never completes in the test environment (no
/// platform channel), which freezes tap-triggered loads in their loading
/// state.
const _kStorageUrl =
    'https://firebasestorage.googleapis.com/v0/b/x/o/video.mp4?alt=media';

/// The video-first reorder moved PROGRESIÓN/HISTORIAL below TÉCNICA, past the
/// default 800x600 test viewport — a lazy SliverList never builds them there.
/// A tall viewport mounts every section so content/order asserts see them all.
void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('ExerciseDetailScreen', () {
    testWidgets(
        'SCENARIO-097: AsyncData(exercise) renders without exception and shows name',
        (tester) async {
      final exercise = _makeExercise();
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press')
              .overrideWith((ref) async => exercise),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('BENCH'), findsAtLeastNWidgets(1));
    });

    testWidgets('SCENARIO-098: AsyncLoading shows skeleton, hides name',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press').overrideWith(
            (ref) => Completer<Exercise?>().future,
          ),
        ],
      ));
      await tester.pump();
      expect(find.textContaining('BENCH'), findsNothing);
      expect(find.byType(StatTile), findsNothing);
    });

    testWidgets('SCENARIO-099: AsyncError shows error widget without exception',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press').overrideWith(
            (ref) async => throw Exception('boom'),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('cargar'), findsAtLeastNWidgets(1));
    });

    testWidgets(
        'SCENARIO-100: AsyncData(null) shows "Ejercicio no encontrado" + back button',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press').overrideWith((ref) async => null),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('no encontrado'), findsOneWidget);
      // Back button MUST be present so the user can never dead-end.
      expect(find.byIcon(TreinoIcon.back), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-101: badge translates muscleGroup + category; title uppercase',
        (tester) async {
      // Data is stored in English (chest/compound) and translated at render.
      final exercise = _makeExercise(
        name: 'Press de Banca',
        muscleGroup: 'chest',
        category: 'compound',
      );
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press')
              .overrideWith((ref) async => exercise),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('PECHO · COMPUESTO'), findsOneWidget);
      expect(find.text('PRESS DE BANCA'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-102: exactly 3 StatTiles; with no personal data 1RM and '
        'PROGRESO keep the dash while SESIONES shows 0', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press')
              .overrideWith((ref) async => _makeExercise()),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      // Second pump: the personal-stats providers are only created once the
      // exercise data lands and the content mounts — one more frame lets
      // them resolve.
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(StatTile), findsNWidgets(3));
      // Signed-out/no-history: the progression resolves to empty data — a
      // real 0-session count, no 1RM and no computable delta.
      expect(find.text('—'), findsNWidgets(2));
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-103: techniqueInstructions renders TÉCNICA header and 3 items',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press').overrideWith(
            (ref) async => _makeExercise(
              techniqueInstructions: ['Cue 1', 'Cue 2', 'Cue 3'],
            ),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      // Video-first order puts TÉCNICA right under the hero (~340px), inside
      // the default viewport — scrollUntilVisible is a no-op kept as a guard
      // against future reorders.
      await tester.scrollUntilVisible(
        find.text('TÉCNICA'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('TÉCNICA'), findsOneWidget);
      expect(find.byType(TechniqueInstructionItem), findsNWidgets(3));
    });

    testWidgets('SCENARIO-104: techniqueInstructions null shows empty state',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press').overrideWith(
            (ref) async => _makeExercise(techniqueInstructions: null),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      // TÉCNICA sits right under the hero now — scroll kept as a guard.
      await tester.scrollUntilVisible(
        find.text('No hay instrucciones de técnica todavía'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('No hay instrucciones de técnica todavía'),
        findsOneWidget,
      );
      expect(find.byType(TechniqueInstructionItem), findsNothing);
    });

    testWidgets('SCENARIO-105: techniqueInstructions empty shows empty state',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press').overrideWith(
            (ref) async => _makeExercise(techniqueInstructions: []),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.scrollUntilVisible(
        find.text('No hay instrucciones de técnica todavía'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('No hay instrucciones de técnica todavía'),
        findsOneWidget,
      );
    });

    testWidgets(
        'SCENARIO-106: HISTORIAL section header and empty state always present',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press')
              .overrideWith((ref) async => _makeExercise()),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      // HISTORIAL is the last section in a CustomScrollView — outside the
      // default test viewport once the persistent back-bar takes ~48px off the
      // top. Scroll it into view before asserting.
      await tester.scrollUntilVisible(
        find.text('Aún no entrenaste este ejercicio'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('HISTORIAL'), findsOneWidget);
      expect(
        find.text('Aún no entrenaste este ejercicio'),
        findsOneWidget,
      );
    });

    testWidgets('SCENARIO-107: videoUrl null renders without exception',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press').overrideWith(
            (ref) async => _makeExercise(videoUrl: null),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'SCENARIO-108 (video-first): unplayable videoUrl keeps the photo hero '
        '— no play overlay, no VIDEO body section, no hole', (tester) async {
      // Only Firebase Storage / parseable YouTube URLs put the video in the
      // hero. A legacy URL like this one is unplayable → the hero stays the
      // photo strip exactly like a video-less exercise (graceful for the
      // athlete; the coach surfaces still expose the broken URL).
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press').overrideWith(
            (ref) async =>
                _makeExercise(videoUrl: 'https://example.com/video.mp4'),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(ExerciseAssetImage), findsOneWidget);
      expect(find.byType(VideoPlayOverlay), findsNothing);
      expect(find.text('VIDEO'), findsNothing);
    });

    testWidgets(
        'SCENARIO-109: no Scaffold/AppBackground/SafeArea inside screen subtree',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press')
              .overrideWith((ref) async => _makeExercise()),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(AppBackground), findsNothing);
      expect(find.byType(SafeArea), findsNothing);
    });
  });

  group('ExerciseDetailScreen — personal stats/history', () {
    ProgressionPoint pt(DateTime date, double value) =>
        ProgressionPoint(date: date, value: value);

    final d1 = DateTime.utc(2026, 7, 1, 12);
    final d2 = DateTime.utc(2026, 7, 20, 12);

    ExerciseProgression makeProgression({
      List<ProgressionPoint>? oneRepMaxSeries,
      List<PersonalRecord> personalRecords = const [],
      int frequencySessionCount = 0,
    }) =>
        ExerciseProgression(
          exerciseId: 'bench-press',
          exerciseName: 'Bench Press',
          heaviestWeightSeries: [pt(d1, 95), pt(d2, 100)],
          oneRepMaxSeries: oneRepMaxSeries ?? [pt(d1, 100), pt(d2, 110)],
          bestSetVolumeSeries: [pt(d1, 475), pt(d2, 500)],
          bestSessionVolumeSeries: [pt(d1, 1900), pt(d2, 2400)],
          personalRecords: personalRecords,
          frequencySessionCount: frequencySessionCount,
        );

    final historyEntries = <ExerciseSessionHistoryEntry>[
      (
        date: DateTime.utc(2026, 7, 22, 12),
        setCount: 4,
        bestWeightKg: 80.0,
        bestSetReps: 8,
        sessionVolume: 2400.0,
      ),
      (
        date: DateTime.utc(2026, 7, 20, 12),
        setCount: 1,
        bestWeightKg: 0.0,
        bestSetReps: 12,
        sessionVolume: 0.0,
      ),
    ];

    List<Override> statsOverrides({
      required ExerciseProgression progression,
      List<ExerciseSessionHistoryEntry> history = const [],
    }) =>
        [
          exerciseByIdProvider('bench-press')
              .overrideWith((ref) async => _makeExercise()),
          exerciseProgressionProvider
              .overrideWith((ref, key) async => progression),
          exerciseSessionHistoryProvider
              .overrideWith((ref, key) async => history),
        ];

    testWidgets(
        'with data: 1RM shows the period best (0.5kg rounding), SESIONES the '
        'frequency count and PROGRESO the first→last 1RM delta',
        (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        statsOverrides(
          progression: makeProgression(frequencySessionCount: 5),
          history: historyEntries,
        ),
        uid: 'user-1',
      ));
      await tester.pump(const Duration(milliseconds: 50));
      // Second pump: the personal-stats providers are only created once the
      // exercise data lands and the content mounts — one more frame lets
      // them resolve.
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('110 kg'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('+10%'), findsOneWidget);
      expect(find.text('—'), findsNothing);
    });

    testWidgets('regressing 1RM series renders a signed negative delta',
        (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        statsOverrides(
          progression: makeProgression(
            oneRepMaxSeries: [pt(d1, 100), pt(d2, 90)],
          ),
        ),
        uid: 'user-1',
      ));
      await tester.pump(const Duration(milliseconds: 50));
      // Second pump: the personal-stats providers are only created once the
      // exercise data lands and the content mounts — one more frame lets
      // them resolve.
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('-10%'), findsOneWidget);
    });

    testWidgets('with records: PersonalRecordsList renders below the chart',
        (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        statsOverrides(
          progression: makeProgression(
            personalRecords: [
              PersonalRecord(
                recordType: ProgressionRecordType.oneRepMax,
                value: 110,
                achievedAt: d2,
              ),
            ],
          ),
        ),
        uid: 'user-1',
      ));
      await tester.pump(const Duration(milliseconds: 50));
      // Second pump: the personal-stats providers are only created once the
      // exercise data lands and the content mounts — one more frame lets
      // them resolve.
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(PersonalRecordsList), findsOneWidget);
    });

    testWidgets(
        'history rows render most-recent first with best set, set count and '
        'session volume; bodyweight rows fall back to reps-only',
        (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        statsOverrides(
          progression: makeProgression(),
          history: historyEntries,
        ),
        uid: 'user-1',
      ));
      await tester.pump(const Duration(milliseconds: 50));
      // Second pump: the personal-stats providers are only created once the
      // exercise data lands and the content mounts — one more frame lets
      // them resolve.
      await tester.pump(const Duration(milliseconds: 50));

      await tester.scrollUntilVisible(
        find.text('80 kg × 8'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('80 kg × 8'), findsOneWidget);
      expect(find.text('4 series'), findsOneWidget);
      expect(find.text('2400 kg·reps'), findsOneWidget);
      // #368 bodyweight-only session: reps-only best set, no volume line.
      expect(find.text('12 reps'), findsOneWidget);
      expect(find.text('1 serie'), findsOneWidget);
      // Real rows replace the HISTORIAL empty state.
      expect(find.text('Aún no entrenaste este ejercicio'), findsNothing);
    });

    testWidgets(
        'never trained: dashes + 0 sessions, no records list, HISTORIAL '
        'keeps its empty state', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        statsOverrides(
          progression: ExerciseProgression.empty(
            exerciseId: 'bench-press',
            exerciseName: 'Bench Press',
          ),
        ),
        uid: 'user-1',
      ));
      await tester.pump(const Duration(milliseconds: 50));
      // Second pump: the personal-stats providers are only created once the
      // exercise data lands and the content mounts — one more frame lets
      // them resolve.
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('—'), findsNWidgets(2));
      expect(find.text('0'), findsOneWidget);
      expect(find.byType(PersonalRecordsList), findsNothing);

      await tester.scrollUntilVisible(
        find.text('Aún no entrenaste este ejercicio'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Aún no entrenaste este ejercicio'), findsOneWidget);
    });

    testWidgets(
        'coach context: athleteId overrides the signed-in uid for stats and '
        'history — the PF NEVER sees their own numbers', (tester) async {
      _useTallViewport(tester);
      ExerciseProgressionKey? receivedProgressionKey;
      ExerciseHistoryKey? receivedHistoryKey;

      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(
          exerciseId: 'bench-press',
          athleteId: 'athlete-x',
        ),
        [
          exerciseByIdProvider('bench-press')
              .overrideWith((ref) async => _makeExercise()),
          exerciseProgressionProvider.overrideWith((ref, key) async {
            receivedProgressionKey = key;
            return makeProgression(frequencySessionCount: 7);
          }),
          exerciseSessionHistoryProvider.overrideWith((ref, key) async {
            receivedHistoryKey = key;
            return const <ExerciseSessionHistoryEntry>[];
          }),
        ],
        // The signed-in user is the COACH — must not leak into the stats.
        uid: 'coach-uid',
      ));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(receivedProgressionKey?.athleteUid, 'athlete-x');
      expect(find.text('7'), findsOneWidget);

      // _HistorySection sits below the fold and SliverList builds lazily —
      // scroll it into view so its provider watch actually fires.
      await tester.scrollUntilVisible(
        find.text('Aún no entrenaste este ejercicio'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(receivedHistoryKey?.athleteUid, 'athlete-x');
    });

    testWidgets(
        'provider errors degrade to placeholders + muted copy, no crash',
        (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press')
              .overrideWith((ref) async => _makeExercise()),
          exerciseProgressionProvider
              .overrideWith((ref, key) async => throw Exception('boom')),
          exerciseSessionHistoryProvider
              .overrideWith((ref, key) async => throw Exception('boom')),
        ],
        uid: 'user-1',
      ));
      await tester.pump(const Duration(milliseconds: 50));
      // Second pump: the personal-stats providers are only created once the
      // exercise data lands and the content mounts — one more frame lets
      // them resolve.
      await tester.pump(const Duration(milliseconds: 50));

      expect(tester.takeException(), isNull);
      expect(find.byType(StatTile), findsNWidgets(3));
      expect(find.text('—'), findsNWidgets(3));
      expect(find.text('No pudimos cargar la progresión.'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('No pudimos cargar el historial.'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('No pudimos cargar el historial.'), findsOneWidget);
    });
  });

  group('ExerciseDetailScreen — video-first (pedido 2026-07-28)', () {
    testWidgets(
        'playable video: hero shows poster + play overlay (NO autoplay), body '
        'order is TÉCNICA → PROGRESIÓN → HISTORIAL with no VIDEO section',
        (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press').overrideWith(
            (ref) async => _makeExercise(videoUrl: _kStorageUrl),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      // Poster (photo cascade) + play affordance; nothing initialises on its
      // own — no spinner means no controller was created without a tap.
      expect(find.byType(ExerciseAssetImage), findsOneWidget);
      expect(find.byType(VideoPlayOverlay), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // The video lives in the hero now — VIDEO stopped being a body section.
      expect(find.text('VIDEO'), findsNothing);

      final playDy = tester.getTopLeft(find.byType(VideoPlayOverlay)).dy;
      final tecnicaDy = tester.getTopLeft(find.text('TÉCNICA')).dy;
      final progresionDy = tester.getTopLeft(find.text('PROGRESIÓN')).dy;
      final historialDy = tester.getTopLeft(find.text('HISTORIAL')).dy;
      expect(playDy, lessThan(tecnicaDy));
      expect(tecnicaDy, lessThan(progresionDy));
      expect(progresionDy, lessThan(historialDy));
    });

    testWidgets(
        'tap on the poster shows the #545 loading treatment (shimmer + accent '
        'spinner) — playback only ever starts from the tap', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press').overrideWith(
            (ref) async => _makeExercise(videoUrl: _kStorageUrl),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // The overlay sits over the hero's tap surface — tapping through it
      // starts the lazy init. Controller init never completes in the test
      // environment, freezing the strip in its loading state.
      await tester.tap(find.byType(VideoPlayOverlay));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(TreinoShimmer), findsAtLeastNWidgets(1));
    });

    testWidgets('YouTube URL: hero shows the poster + play overlay too',
        (tester) async {
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press').overrideWith(
            (ref) async => _makeExercise(
              videoUrl: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
            ),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(VideoPlayOverlay), findsOneWidget);
      expect(find.text('VIDEO'), findsNothing);
    });

    testWidgets(
        'no video: photo hero exactly like before — no play overlay, no VIDEO '
        'section, section order intact', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press').overrideWith(
            (ref) async => _makeExercise(videoUrl: null),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(ExerciseAssetImage), findsOneWidget);
      expect(find.byType(VideoPlayOverlay), findsNothing);
      expect(find.text('VIDEO'), findsNothing);

      final tecnicaDy = tester.getTopLeft(find.text('TÉCNICA')).dy;
      final progresionDy = tester.getTopLeft(find.text('PROGRESIÓN')).dy;
      final historialDy = tester.getTopLeft(find.text('HISTORIAL')).dy;
      expect(tecnicaDy, lessThan(progresionDy));
      expect(progresionDy, lessThan(historialDy));
    });

    testWidgets(
        'custom exercise: compact header keeps the VIDEO slot as the FIRST '
        'body section (video-first order for trainers too)', (tester) async {
      _useTallViewport(tester);
      await tester.pumpWidget(_wrapWithOverrides(
        const ExerciseDetailScreen(exerciseId: 'bench-press'),
        [
          exerciseByIdProvider('bench-press').overrideWith(
            (ref) async => _makeExercise(
              category: 'custom',
              videoUrl: _kStorageUrl,
            ),
          ),
        ],
      ));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      // No photo hero for custom → the inline player card hosts the video.
      expect(find.byType(FirebaseStorageVideoPlayer), findsOneWidget);
      expect(find.text('VIDEO'), findsOneWidget);

      final videoDy = tester.getTopLeft(find.text('VIDEO')).dy;
      final tecnicaDy = tester.getTopLeft(find.text('TÉCNICA')).dy;
      final progresionDy = tester.getTopLeft(find.text('PROGRESIÓN')).dy;
      expect(videoDy, lessThan(tecnicaDy));
      expect(tecnicaDy, lessThan(progresionDy));
    });
  });
}
