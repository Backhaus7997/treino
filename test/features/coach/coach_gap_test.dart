// Automated GAP tests for the `coach` module.
//
// These cover P0/P1 (and a couple of high-value P2) cases from
// docs/test-plan-2026-06-16.md that were NOT yet exercised by the existing
// suite under test/features/coach/. Each test follows the conventions already
// in use by the module's tests:
//   - fake_cloud_firestore for repository data tests
//   - ProviderContainer + overrides for provider logic tests
//   - pure-function calls for domain logic tests
//
// Cases covered (see test-plan ids):
//   coach-36  TrainerLinkRepository.cancel sets reason 'cancelled-by-athlete'
//             (vs decline 'declined') — analytics differentiation.
//   coach-37  currentAthleteLinkProvider returns most recent active link / null.
//   coach-44  computeFreeSlots matches rules by ISO weekday only.
//   coach-47  computeFreeSlots window too small for one slot → zero slots.
//   coach-48  computeFreeSlots ignores overrides/appointments on other days.
//   coach-66  createByTrainer uses auto-id (overlap allowed) + trims/nulls note.
//   coach-68  createRecurringByTrainer returns 0 and writes nothing when all
//             occurrences are in the past.
//   PriceFilter.matches boundary semantics (supports coach-103 family).
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:treino/features/coach/application/trainer_discovery_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/appointment_repository.dart';
import 'package:treino/features/coach/data/trainer_link_repository.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach/domain/availability_override.dart';
import 'package:treino/features/coach/domain/availability_rule.dart';
import 'package:treino/features/coach/domain/compute_free_slots.dart';
import 'package:treino/features/coach/domain/discovery_filters.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/domain/trainer_public_profile.dart';
import 'package:treino/features/coach/domain/trainer_specialty.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

void main() {
  // ────────────────────────────────────────────────────────────────────────
  // coach-36 — TrainerLinkRepository.cancel terminationReason differentiation
  // ────────────────────────────────────────────────────────────────────────
  group('coach-36 · TrainerLinkRepository.cancel', () {
    late FakeFirebaseFirestore firestore;
    late TrainerLinkRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = TrainerLinkRepository(firestore: firestore);
    });

    Future<String> seedPending() async {
      final ref = firestore.collection('trainer_links').doc();
      final link = TrainerLink(
        id: ref.id,
        trainerId: 'trainer-1',
        athleteId: 'athlete-1',
        status: TrainerLinkStatus.pending,
        requestedAt: DateTime.utc(2026, 6, 1, 10, 0),
      );
      await ref.set(link.toJson());
      return ref.id;
    }

    test(
      'cancel on pending → terminated with reason "cancelled-by-athlete"; '
      'decline on a sibling pending → reason "declined" (analytics split)',
      () async {
        final cancelId = await seedPending();
        final declineId = await seedPending();

        await repo.cancel(cancelId);
        await repo.decline(declineId);

        final cancelled =
            await firestore.collection('trainer_links').doc(cancelId).get();
        final declined =
            await firestore.collection('trainer_links').doc(declineId).get();

        expect(cancelled.data()!['status'], 'terminated');
        expect(cancelled.data()!['terminationReason'], 'cancelled-by-athlete');
        expect(declined.data()!['status'], 'terminated');
        expect(declined.data()!['terminationReason'], 'declined');
      },
    );

    test('cancel rejects non-pending status with StateError', () async {
      final ref = firestore.collection('trainer_links').doc();
      await ref.set(
        TrainerLink(
          id: ref.id,
          trainerId: 'trainer-1',
          athleteId: 'athlete-1',
          status: TrainerLinkStatus.active,
          requestedAt: DateTime.utc(2026, 6, 1, 10, 0),
          acceptedAt: DateTime.utc(2026, 6, 1, 11, 0),
        ).toJson(),
      );

      expect(() => repo.cancel(ref.id), throwsA(isA<StateError>()));

      // Doc untouched — still active.
      final after = await firestore.collection('trainer_links').doc(ref.id).get();
      expect(after.data()!['status'], 'active');
    });

    test('cancel on missing doc throws StateError', () async {
      expect(() => repo.cancel('ghost'), throwsA(isA<StateError>()));
    });
  });

  // ────────────────────────────────────────────────────────────────────────
  // coach-37 — currentAthleteLinkProvider selection logic
  // ────────────────────────────────────────────────────────────────────────
  group('coach-37 · currentAthleteLinkProvider', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    ProviderContainer makeContainer({String? uid}) {
      return ProviderContainer(
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
          currentUidProvider.overrideWithValue(uid),
        ],
      );
    }

    Future<void> seedLink({
      required String id,
      required TrainerLinkStatus status,
      required DateTime requestedAt,
      String athleteId = 'me',
    }) async {
      await firestore.collection('trainer_links').doc(id).set(
            TrainerLink(
              id: id,
              trainerId: 'trainer-$id',
              athleteId: athleteId,
              status: status,
              requestedAt: requestedAt,
              acceptedAt: status == TrainerLinkStatus.active
                  ? requestedAt.add(const Duration(hours: 1))
                  : null,
            ).toJson(),
          );
    }

    test('returns null when uid is null', () async {
      final container = makeContainer(uid: null);
      addTearDown(container.dispose);

      final result = await container.read(currentAthleteLinkProvider.future);
      expect(result, isNull);
    });

    test('returns null when athlete has no ACTIVE links', () async {
      // A pending and a terminated link exist, but none active.
      await seedLink(
        id: 'p',
        status: TrainerLinkStatus.pending,
        requestedAt: DateTime.utc(2026, 6, 1),
      );
      await seedLink(
        id: 't',
        status: TrainerLinkStatus.terminated,
        requestedAt: DateTime.utc(2026, 6, 2),
      );

      final container = makeContainer(uid: 'me');
      addTearDown(container.dispose);

      final result = await container.read(currentAthleteLinkProvider.future);
      expect(result, isNull);
    });

    test(
      'returns the most recent ACTIVE link (requestedAt DESC) when several exist',
      () async {
        await seedLink(
          id: 'old',
          status: TrainerLinkStatus.active,
          requestedAt: DateTime.utc(2026, 5, 1),
        );
        await seedLink(
          id: 'new',
          status: TrainerLinkStatus.active,
          requestedAt: DateTime.utc(2026, 6, 10),
        );
        // A more-recent but non-active link must NOT win.
        await seedLink(
          id: 'pending-newer',
          status: TrainerLinkStatus.pending,
          requestedAt: DateTime.utc(2026, 6, 20),
        );

        final container = makeContainer(uid: 'me');
        addTearDown(container.dispose);

        final result = await container.read(currentAthleteLinkProvider.future);
        expect(result, isNotNull);
        expect(result!.id, 'new');
        expect(result.status, TrainerLinkStatus.active);
      },
    );
  });

  // ────────────────────────────────────────────────────────────────────────
  // computeFreeSlots gaps (coach-44 / coach-47 / coach-48)
  // ────────────────────────────────────────────────────────────────────────
  group('computeFreeSlots gaps', () {
    // 2026-06-01 is a Monday (ISO weekday == 1).
    final monday = DateTime.utc(2026, 6, 1);

    AvailabilityRule rule({
      required int dayOfWeek,
      int startHour = 9,
      int startMinute = 0,
      int endHour = 11,
      int endMinute = 0,
      int slotDurationMin = 60,
      String id = 'r',
    }) =>
        AvailabilityRule(
          id: id,
          trainerId: 'tA',
          dayOfWeek: dayOfWeek,
          startHour: startHour,
          startMinute: startMinute,
          endHour: endHour,
          endMinute: endMinute,
          slotDurationMin: slotDurationMin,
        );

    test('coach-44: only rules matching the ISO weekday contribute slots', () {
      final slots = computeFreeSlots(
        rules: [
          rule(dayOfWeek: 1, id: 'mon'), // Monday → applies
          rule(dayOfWeek: 2, id: 'tue', startHour: 14, endHour: 16), // ignored
        ],
        overrides: const [],
        existingAppointments: const [],
        forDate: monday,
      );

      // Only the Monday rule's two 60-min slots (09:00, 10:00).
      expect(slots, hasLength(2));
      expect(slots[0], DateTime.utc(2026, 6, 1, 9, 0));
      expect(slots[1], DateTime.utc(2026, 6, 1, 10, 0));
      // Tuesday's afternoon window must not leak in.
      expect(
        slots.any((s) => s.hour >= 14),
        isFalse,
        reason: 'Tuesday rule must not contribute slots on a Monday',
      );
    });

    test('coach-47: window too small for one slot yields zero slots', () {
      // 09:00–09:30 window with 60-min slots → cannot fit a single slot.
      final slots = computeFreeSlots(
        rules: [
          rule(
            dayOfWeek: 1,
            startHour: 9,
            startMinute: 0,
            endHour: 9,
            endMinute: 30,
            slotDurationMin: 60,
          ),
        ],
        overrides: const [],
        existingAppointments: const [],
        forDate: monday,
      );
      expect(slots, isEmpty);
    });

    test(
      'coach-48: overrides and appointments dated on OTHER days are ignored',
      () {
        final otherDay = DateTime.utc(2026, 6, 2); // Tuesday

        final blockOnOtherDay = AvailabilityOverride.block(
          id: 'block-other',
          trainerId: 'tA',
          date: otherDay,
        );
        final extraOnOtherDay = AvailabilityOverride.extra(
          id: 'extra-other',
          trainerId: 'tA',
          date: otherDay,
          startHour: 7,
          startMinute: 0,
          endHour: 8,
          endMinute: 0,
          slotDurationMin: 60,
        );
        final apptOnOtherDay = Appointment(
          id: 'tA_other',
          trainerId: 'tA',
          athleteId: 'aB',
          athleteDisplayName: 'Other',
          startsAt: DateTime.utc(2026, 6, 2, 9, 0),
          durationMin: 60,
          status: AppointmentStatus.confirmed,
        );

        final slots = computeFreeSlots(
          rules: [rule(dayOfWeek: 1)], // Monday 09:00 & 10:00
          overrides: [blockOnOtherDay, extraOnOtherDay],
          existingAppointments: [apptOnOtherDay],
          forDate: monday,
        );

        // Block on Tuesday must NOT clear Monday's slots; extra on Tuesday must
        // NOT add a 07:00 slot to Monday; appointment on Tuesday must NOT remove
        // Monday's 09:00 slot.
        expect(slots, hasLength(2));
        expect(slots[0], DateTime.utc(2026, 6, 1, 9, 0));
        expect(slots[1], DateTime.utc(2026, 6, 1, 10, 0));
      },
    );
  });

  // ────────────────────────────────────────────────────────────────────────
  // coach-66 / coach-68 — AppointmentRepository.createByTrainer / recurring
  // ────────────────────────────────────────────────────────────────────────
  group('coach-66/68 · AppointmentRepository trainer scheduling', () {
    late FakeFirebaseFirestore firestore;
    late AppointmentRepository repo;

    const trainerId = 'trainer-1';

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = AppointmentRepository(firestore: firestore);
    });

    test(
      'coach-66: createByTrainer uses an auto-id, allowing two sessions at the '
      'SAME startsAt; blank noteBefore is normalised to null',
      () async {
        final startsAt = DateTime.utc(2030, 1, 1, 18, 0);

        final a = await repo.createByTrainer(
          trainerId: trainerId,
          athleteId: 'ath-A',
          athleteDisplayName: 'Athlete A',
          startsAt: startsAt,
          durationMin: 60,
          noteBefore: '   ', // whitespace-only → should null out
        );
        final b = await repo.createByTrainer(
          trainerId: trainerId,
          athleteId: 'ath-B',
          athleteDisplayName: 'Athlete B',
          startsAt: startsAt, // identical time — overlap allowed by design
          durationMin: 45,
        );

        // Two distinct docs (auto-id, not the deterministic slot id).
        expect(a.id, isNot(equals(b.id)));
        expect(a.id, isNot(equals('${trainerId}_${startsAt.millisecondsSinceEpoch}')));

        final all = await firestore.collection('appointments').get();
        expect(all.docs, hasLength(2));
        expect(
          all.docs.every((d) => d.data()['status'] == 'confirmed'),
          isTrue,
        );

        // Blank note nulled; both confirmed at the same startsAt.
        expect(a.noteBefore, isNull);
        expect(a.status, AppointmentStatus.confirmed);
        expect(b.status, AppointmentStatus.confirmed);
        expect(a.startsAt, startsAt);
        expect(b.startsAt, startsAt);
      },
    );

    test(
      'coach-66: createByTrainer trims a non-blank noteBefore',
      () async {
        final appt = await repo.createByTrainer(
          trainerId: trainerId,
          athleteId: 'ath-A',
          athleteDisplayName: 'Athlete A',
          startsAt: DateTime.utc(2030, 2, 1, 9, 0),
          durationMin: 60,
          noteBefore: '  llevar banda elástica  ',
        );
        expect(appt.noteBefore, 'llevar banda elástica');
      },
    );

    test(
      'coach-68: createRecurringByTrainer returns 0 and writes nothing when '
      'every occurrence is in the past',
      () async {
        // Entire range is far in the past relative to wall-clock now.
        final count = await repo.createRecurringByTrainer(
          trainerId: trainerId,
          athleteId: 'ath-A',
          athleteDisplayName: 'Athlete A',
          weekdays: const {1, 2, 3, 4, 5, 6, 7}, // every weekday
          startHour: 10,
          startMinute: 0,
          durationMin: 60,
          fromDate: DateTime.utc(2000, 1, 3),
          untilDate: DateTime.utc(2000, 1, 10),
        );

        expect(count, 0);
        final all = await firestore.collection('appointments').get();
        expect(all.docs, isEmpty);
      },
    );
  });

  // ────────────────────────────────────────────────────────────────────────
  // trainerDiscoveryProvider filter gaps + PriceFilter.matches semantics
  // ────────────────────────────────────────────────────────────────────────
  group('trainerDiscoveryProvider filters', () {
    Position makePosition({double lat = -34.6, double lon = -58.4}) => Position(
          latitude: lat,
          longitude: lon,
          timestamp: DateTime(2024),
          accuracy: 10,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );

    TrainerPublicProfile trainer({
      required String uid,
      String? displayName,
      double? lat,
      double? lon,
      String? geohash,
      int? rate,
    }) =>
        TrainerPublicProfile(
          uid: uid,
          displayName: displayName ?? uid,
          displayNameLowercase: (displayName ?? uid).toLowerCase(),
          trainerLatitude: lat,
          trainerLongitude: lon,
          trainerGeohash: geohash,
          trainerMonthlyRate: rate,
        );

    test(
      'price filter keeps trainers with a null rate and excludes out-of-range',
      () async {
        final cheap = trainer(uid: 'cheap', displayName: 'Cheap', rate: 4000);
        final pricey = trainer(uid: 'pricey', displayName: 'Pricey', rate: 12000);
        final noRate = trainer(uid: 'norate', displayName: 'NoRate'); // null rate

        final container = ProviderContainer(overrides: [
          athleteLocationProvider.overrideWith(
            (_) => AthleteLocationNotifier()..setForTest(null),
          ),
          selectedSpecialtyProvider
              .overrideWith((_) => const <TrainerSpecialty>{}),
          selectedPriceFilterProvider.overrideWith((_) => PriceFilter.under5k),
          trainerPublicProfileRepositoryProvider.overrideWith(
            (_) => _FakeDiscoveryRepo(all: [cheap, pricey, noRate]),
          ),
        ]);
        addTearDown(container.dispose);

        final result = await container.read(trainerDiscoveryProvider.future);
        final ids = result.map((t) => t.uid).toSet();
        // cheap (4000 < 5000) kept; noRate kept (null always passes); pricey out.
        expect(ids, {'cheap', 'norate'});
      },
    );

    test(
      'distance filter (with location) drops trainers beyond the radius and '
      'trainers without coordinates',
      () async {
        final pos = makePosition(lat: -34.6, lon: -58.4);
        // Same coords as the athlete → ~0 km.
        final near = trainer(
          uid: 'near',
          displayName: 'Near',
          lat: -34.6,
          lon: -58.4,
          geohash: 'd2h4j',
        );
        // ~155 km away (1 degree latitude ≈ 111 km, plus longitude offset).
        final far = trainer(
          uid: 'far',
          displayName: 'Far',
          lat: -33.6,
          lon: -57.4,
          geohash: 'd2h00',
        );
        // No coordinates → distance unknown → excluded by the distance filter.
        final virtual = trainer(uid: 'virtual', displayName: 'Virtual');

        final container = ProviderContainer(overrides: [
          athleteLocationProvider.overrideWith(
            (_) => AthleteLocationNotifier()..setForTest(pos),
          ),
          selectedSpecialtyProvider
              .overrideWith((_) => const <TrainerSpecialty>{}),
          selectedDistanceFilterProvider
              .overrideWith((_) => DistanceFilter.km2),
          virtualOnlyFilterProvider.overrideWith((_) => false),
          trainerPublicProfileRepositoryProvider.overrideWith(
            (_) => _FakeDiscoveryRepo(
              all: [near, far, virtual],
              geohash: [near, far, virtual],
            ),
          ),
        ]);
        addTearDown(container.dispose);

        final result = await container.read(trainerDiscoveryProvider.future);
        expect(result.map((t) => t.uid).toSet(), {'near'});
      },
    );

    test('PriceFilter.matches: null rate always included; range boundaries', () {
      // null → always kept regardless of filter.
      for (final f in PriceFilter.values) {
        expect(f.matches(null), isTrue, reason: '$f should keep null rate');
      }
      // any → everything passes.
      expect(PriceFilter.any.matches(99999), isTrue);
      // under5k → strictly < 5000.
      expect(PriceFilter.under5k.matches(4999), isTrue);
      expect(PriceFilter.under5k.matches(5000), isFalse);
      // k5to10k → inclusive [5000, 10000].
      expect(PriceFilter.k5to10k.matches(5000), isTrue);
      expect(PriceFilter.k5to10k.matches(10000), isTrue);
      expect(PriceFilter.k5to10k.matches(4999), isFalse);
      expect(PriceFilter.k5to10k.matches(10001), isFalse);
      // over10k → strictly > 10000.
      expect(PriceFilter.over10k.matches(10001), isTrue);
      expect(PriceFilter.over10k.matches(10000), isFalse);
    });
  });
}

// ── Fake repository for trainerDiscoveryProvider tests ─────────────────────
// Mirrors the fake used in trainer_discovery_providers_test.dart: geohash
// queries return the seeded `geohash` list regardless of the cells requested.
class _FakeDiscoveryRepo implements TrainerPublicProfileRepositoryInterface {
  _FakeDiscoveryRepo({
    List<TrainerPublicProfile>? all,
    List<TrainerPublicProfile>? geohash,
    Map<String, TrainerPublicProfile>? byId,
  })  : _all = all ?? const [],
        _geohash = geohash ?? const [],
        _byId = byId ?? const {};

  final List<TrainerPublicProfile> _all;
  final List<TrainerPublicProfile> _geohash;
  final Map<String, TrainerPublicProfile> _byId;

  @override
  Future<List<TrainerPublicProfile>> listAll({TrainerSpecialty? specialty}) async {
    var r = _all;
    if (specialty != null) {
      r = r.where((t) => t.trainerSpecialty == specialty).toList();
    }
    return r;
  }

  @override
  Future<List<TrainerPublicProfile>> listByGeohashPrefix(
    String prefix5, {
    TrainerSpecialty? specialty,
  }) async {
    var r = _geohash;
    if (specialty != null) {
      r = r.where((t) => t.trainerSpecialty == specialty).toList();
    }
    return r;
  }

  @override
  Future<List<TrainerPublicProfile>> listByGeohashes(
    List<String> geohashes, {
    TrainerSpecialty? specialty,
  }) async {
    var r = _geohash;
    if (specialty != null) {
      r = r.where((t) => t.trainerSpecialty == specialty).toList();
    }
    return r;
  }

  @override
  Future<List<TrainerPublicProfile>> listVirtualOnly({
    TrainerSpecialty? specialty,
  }) async {
    var r = _all.where((t) => t.trainerOffersOnline).toList();
    if (specialty != null) {
      r = r.where((t) => t.trainerSpecialty == specialty).toList();
    }
    return r;
  }

  @override
  Future<TrainerPublicProfile?> getById(String uid) async => _byId[uid];
}
