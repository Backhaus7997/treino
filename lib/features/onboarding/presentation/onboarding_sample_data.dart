/// Representative data for the onboarding previews.
///
/// The tour renders the app's REAL screen widgets rather than mock-ups, so the
/// previews cannot drift from the product. Those widgets read their data from
/// providers, so the previews run inside a nested `ProviderScope` seeded with
/// [onboardingSampleOverrides].
///
/// ⚠️ The override list must cover EVERY provider the previewed widgets read.
/// A nested `ProviderScope` re-creates any provider it does not override, so a
/// missing entry does not fall back to the parent's value — it builds a fresh
/// one, which for these providers means a live Firestore read on behalf of a
/// user who has not finished onboarding yet. When you add a widget to a
/// preview, add its providers here in the same commit.
///
/// The data is deliberately fictional. Nothing here is read from, or written
/// to, the signed-in account.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../chat/application/chat_providers.dart';
import '../../coach/application/trainer_link_providers.dart';
import '../../coach/domain/trainer_link.dart';
import '../../coach/domain/trainer_link_status.dart';
import '../../feed/application/feed_screen_providers.dart';
import '../../feed/domain/feed_segment.dart';
import '../../feed/domain/post.dart';
import '../../feed/domain/post_privacy.dart';
import '../../feed/domain/reaction_type.dart';
import '../../home/application/todays_routine_provider.dart';
import '../../insights/application/insights_providers.dart';
import '../../payments/application/mi_cuota_provider.dart';
import '../../insights/domain/muscle_group.dart';
import '../../insights/domain/weekly_insights.dart';
import '../../profile/application/user_providers.dart';
import '../../profile/application/user_public_profile_providers.dart';
import '../../profile/domain/experience_level.dart';
import '../../profile/domain/user_profile.dart';
import '../../profile/domain/user_public_profile.dart';
import '../../profile/domain/user_role.dart';
import '../../workout/application/session_providers.dart';
import '../../workout/application/unified_routines_providers.dart';
import '../../workout/domain/routine.dart';
import '../../workout/domain/routine_day.dart';
import '../../workout/domain/routine_slot.dart';
import '../../workout/domain/routine_source.dart';
import '../../workout/domain/routine_visibility.dart';
import '../../workout/domain/session.dart';
import '../../workout/domain/session_status.dart';

// ── Fixed clock ─────────────────────────────────────────────────────────────
// A hardcoded date, never DateTime.now(): the previews must render identically
// on every run, and "hace 2 h" drifting to "hace 3 h" between rebuilds would be
// a flaky widget test waiting to happen.
final _now = DateTime(2026, 3, 12, 18, 30);

const _kUid = 'onboarding-preview-athlete';
const _kTrainerId = 'onboarding-preview-trainer';

// ── Slide 1 — Resumen del día ───────────────────────────────────────────────

/// Six slots, ordered pecho → hombros → tríceps.
///
/// The order is load-bearing: `_muscleSubtitle` dedupes muscle groups in order
/// of appearance, so this is what produces the mock's "Pecho · Hombros ·
/// Tríceps" instead of an alphabetised or arbitrary list.
///
/// The rest/rep numbers are chosen so the card's own estimator lands on the
/// mock's "~52 min". `EmpezarEntrenamientoCard` ignores
/// `Routine.estimatedMinutesPerDay` and computes from the slots:
/// 3 × (12·3 + 90)·4 = 1512 s, plus 3 × (10·3 + 105)·4 = 1620 s → 3132 s ≈ 52.
const _pushSlots = <RoutineSlot>[
  RoutineSlot(
    exerciseId: 'bench-press',
    exerciseName: 'Press de banca',
    muscleGroup: 'chest',
    targetSets: 4,
    targetRepsMin: 8,
    targetRepsMax: 12,
    restSeconds: 90,
  ),
  RoutineSlot(
    exerciseId: 'incline-press',
    exerciseName: 'Press inclinado',
    muscleGroup: 'chest',
    targetSets: 4,
    targetRepsMin: 8,
    targetRepsMax: 12,
    restSeconds: 90,
  ),
  RoutineSlot(
    exerciseId: 'chest-fly',
    exerciseName: 'Aperturas con mancuernas',
    muscleGroup: 'chest',
    targetSets: 4,
    targetRepsMin: 10,
    targetRepsMax: 12,
    restSeconds: 90,
  ),
  RoutineSlot(
    exerciseId: 'overhead-press',
    exerciseName: 'Press militar',
    muscleGroup: 'shoulders',
    targetSets: 4,
    targetRepsMin: 6,
    targetRepsMax: 10,
    restSeconds: 105,
  ),
  RoutineSlot(
    exerciseId: 'lateral-raise',
    exerciseName: 'Elevaciones laterales',
    muscleGroup: 'shoulders',
    targetSets: 4,
    targetRepsMin: 10,
    targetRepsMax: 10,
    restSeconds: 105,
  ),
  RoutineSlot(
    exerciseId: 'triceps-pushdown',
    exerciseName: 'Extensión en polea',
    muscleGroup: 'triceps',
    targetSets: 4,
    targetRepsMin: 8,
    targetRepsMax: 10,
    restSeconds: 105,
  ),
];

const _sampleDay = RoutineDay(
  dayNumber: 1,
  name: 'Push A',
  slots: _pushSlots,
);

const _coachRoutine = Routine(
  id: 'onboarding-preview-coach-routine',
  name: 'Plan de fuerza',
  split: 'PPL',
  level: ExperienceLevel.intermediate,
  days: [_sampleDay],
  estimatedMinutesPerDay: 52,
  source: RoutineSource.trainerAssigned,
  assignedBy: _kTrainerId,
  assignedTo: _kUid,
  visibility: RoutineVisibility.private,
);

const _ownRoutine = Routine(
  id: 'onboarding-preview-own-routine',
  name: 'Full body express',
  split: 'Full body',
  level: ExperienceLevel.intermediate,
  days: [_sampleDay],
  estimatedMinutesPerDay: 40,
  source: RoutineSource.userCreated,
  visibility: RoutineVisibility.private,
  createdBy: _kUid,
);

/// Mid-week on purpose: a streak that is neither zero nor a full week reads as
/// real progress, and it exercises the day-strip's mixed filled/empty state.
final _sampleInsights = WeeklyInsights(
  weekStart: DateTime(2026, 3, 9),
  weekEnd: DateTime(2026, 3, 15, 23, 59, 59, 999),
  daysTrained: const [true, true, false, true, false, false, false],
  sessionsCount: 3,
  plannedSessionsCount: 5,
  setsByGroup: const {
    MuscleGroupDisplay.pecho: 12,
    MuscleGroupDisplay.espalda: 14,
    MuscleGroupDisplay.hombros: 8,
    MuscleGroupDisplay.cuadriceps: 10,
    MuscleGroupDisplay.biceps: 6,
    MuscleGroupDisplay.triceps: 6,
  },
  targetByGroup: const {
    MuscleGroupDisplay.pecho: 16,
    MuscleGroupDisplay.espalda: 16,
    MuscleGroupDisplay.hombros: 12,
    MuscleGroupDisplay.cuadriceps: 16,
    MuscleGroupDisplay.biceps: 10,
    MuscleGroupDisplay.triceps: 10,
  },
  streak: 4,
  monthSessionsCount: 11,
  hasEverCompletedAnyWorkout: true,
);

/// The profile the previews render — also what `HomeHeader` greets.
final sampleProfile = UserProfile(
  uid: _kUid,
  email: 'octi@treino.app',
  displayName: 'Octi',
  role: UserRole.athlete,
  createdAt: DateTime(2025, 11, 2),
  updatedAt: _now,
  experienceLevel: ExperienceLevel.intermediate,
  activeRoutineId: _ownRoutine.id,
);

// ── Slide 2 — Entrenar ──────────────────────────────────────────────────────

final _sampleSessions = <Session>[
  Session(
    id: 'onboarding-preview-session-1',
    uid: _kUid,
    routineId: _coachRoutine.id,
    routineName: _coachRoutine.name,
    startedAt: _now.subtract(const Duration(days: 1, hours: 2)),
    finishedAt: _now.subtract(const Duration(days: 1, hours: 1)),
    totalVolumeKg: 4820,
    durationMin: 62,
    status: SessionStatus.finished,
    wasFullyCompleted: true,
  ),
  Session(
    id: 'onboarding-preview-session-2',
    uid: _kUid,
    routineId: _ownRoutine.id,
    routineName: _ownRoutine.name,
    startedAt: _now.subtract(const Duration(days: 3, hours: 3)),
    finishedAt: _now.subtract(const Duration(days: 3, hours: 2)),
    totalVolumeKg: 3140,
    durationMin: 45,
    status: SessionStatus.finished,
    wasFullyCompleted: true,
  ),
];

// ── Slide 3 — Feed ──────────────────────────────────────────────────────────

final _samplePost = Post(
  id: 'onboarding-preview-post',
  authorUid: 'onboarding-preview-friend',
  authorDisplayName: 'Sofi',
  authorAvatarUrl: null,
  authorGymId: null,
  text: 'Cerré la semana con PR en sentadilla. Vamos que se puede 💪',
  routineTag: null,
  privacy: PostPrivacy.friends,
  createdAt: _now.subtract(const Duration(hours: 2)),
  reactionCounts: const {ReactionType.like: 7, ReactionType.fire: 3},
);

final _samplePostTwo = Post(
  id: 'onboarding-preview-post-2',
  authorUid: 'onboarding-preview-friend-2',
  authorDisplayName: 'Lucas Ferrari',
  authorAvatarUrl: null,
  authorGymId: null,
  text: 'Push A cerrado. Las dominadas por fin salen limpias.',
  routineTag: null,
  privacy: PostPrivacy.friends,
  createdAt: _now.subtract(const Duration(hours: 5)),
  reactionCounts: const {ReactionType.like: 4, ReactionType.fire: 2},
);

final _samplePostThree = Post(
  id: 'onboarding-preview-post-3',
  authorUid: 'onboarding-preview-friend-3',
  authorDisplayName: 'Martín Aguirre',
  authorAvatarUrl: null,
  authorGymId: null,
  text: 'Legs day. Foto obligatoria antes de que me fallen las piernas.',
  routineTag: null,
  privacy: PostPrivacy.friends,
  createdAt: _now.subtract(const Duration(hours: 8)),
  reactionCounts: const {
    ReactionType.like: 12,
    ReactionType.fire: 6,
    ReactionType.clap: 3,
  },
);

// ── Slide 4 — Coach ─────────────────────────────────────────────────────────

final _sampleLink = TrainerLink(
  id: 'onboarding-preview-link',
  trainerId: _kTrainerId,
  athleteId: _kUid,
  status: TrainerLinkStatus.active,
  requestedAt: _now.subtract(const Duration(days: 45)),
  acceptedAt: _now.subtract(const Duration(days: 44)),
  sharedWithTrainer: true,
);

const _sampleTrainerProfile = UserPublicProfile(
  uid: _kTrainerId,
  displayName: 'Martín Río',
  gymName: 'Gimnasio Central',
);

// ── The overrides ───────────────────────────────────────────────────────────

/// Seeds every provider the preview widgets read.
///
/// Ordered by slide so the list can be audited against the previews. Family
/// providers use `overrideWith` so the value is returned for ANY argument —
/// the previews pass the sample uid, but pinning the argument would silently
/// fall through to a real fetch the day a widget starts passing something else.
List<Override> onboardingSampleOverrides() => [
      // Shared — everything else derives from this one.
      currentUidProvider.overrideWithValue(_kUid),
      userProfileProvider.overrideWith((ref) => Stream.value(sampleProfile)),

      // Slide 1 — Resumen del día.
      todaysRoutineProvider.overrideWith(
        (ref) async => (
          routine: _coachRoutine,
          day: _sampleDay,
          dayNumber: 1,
          weekNumber: 0,
        ),
      ),
      weeklyInsightsProvider.overrideWith((ref) async => _sampleInsights),

      // Slide 2 — Entrenar.
      unifiedRoutinesProvider.overrideWith(
        (ref, uid) async => [
          (routine: _coachRoutine, fromCoach: true),
          (routine: _ownRoutine, fromCoach: false),
        ],
      ),
      sessionsByUidProvider.overrideWith((ref, uid) async => _sampleSessions),
      currentAthleteLinkProvider.overrideWith((ref) async => _sampleLink),

      // Slide 3 — Feed.
      feedSegmentProvider.overrideWith((ref) => FeedSegment.amigos),

      // Slide 4 — Coach.
      currentAthleteLinkAnyStatusProvider
          .overrideWith((ref) async => _sampleLink),
      userPublicProfileProvider.overrideWith(
        (ref, uid) => Stream.value(_sampleTrainerProfile),
      ),
      hasUnreadFromProvider.overrideWith((ref, uid) => false),
      // miCuotaProvider derives from currentAthleteLinkProvider, which IS
      // overridden here. Riverpod refuses that combination — a provider whose
      // dependency is overridden must either be overridden too or declare
      // `dependencies` — and it fails LOUDLY, painting a red assertion box in
      // the middle of the slide. That is what shipped to the device.
      //
      // This is the exhaustiveness rule at the top of the file biting in
      // practice: the audit has to follow the providers a widget reads
      // TRANSITIVELY, not just the ones it watches directly.
      miCuotaProvider.overrideWithValue(const AsyncValue.data(null)),
    ];

/// The single post slide 3 renders.
Post get samplePost => _samplePost;

/// The other two posts slide 3 renders.
Post get samplePostTwo => _samplePostTwo;
Post get samplePostThree => _samplePostThree;

/// The active trainer link slide 4 renders.
TrainerLink get sampleTrainerLink => _sampleLink;
