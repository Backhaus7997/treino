import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/data/appointment_repository.dart';
import 'package:treino/features/coach/domain/agenda_exceptions.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/payments/domain/payment.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late AppointmentRepository repo;

  const trainerId = 'trainer1';
  const athleteId = 'athlete1';
  const athleteDisplayName = 'Ana Pérez';
  const durationMin = 60;

  // ADR-7: minute-precision DateTime.
  final startsAt = DateTime.utc(2026, 7, 1, 10, 0, 0);
  final startsAtMs = startsAt.millisecondsSinceEpoch;
  final expectedDocId = '${trainerId}_$startsAtMs';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = AppointmentRepository(firestore: firestore);
  });

  group('book()', () {
    // ─── SCENARIO-489: book NEW slot ──────────────────────────────────────
    test(
      'SCENARIO-489: book new slot (doc absent) → returns confirmed Appointment with deterministic ID',
      () async {
        final appt = await repo.book(
          trainerId: trainerId,
          athleteId: athleteId,
          athleteDisplayName: athleteDisplayName,
          startsAt: startsAt,
          durationMin: durationMin,
        );

        expect(appt.id, equals(expectedDocId));
        expect(appt.status, equals(AppointmentStatus.confirmed));
        expect(appt.trainerId, equals(trainerId));
        expect(appt.athleteId, equals(athleteId));
        expect(appt.startsAt, equals(startsAt));

        // Verify persisted in Firestore.
        final snap =
            await firestore.collection('appointments').doc(expectedDocId).get();
        expect(snap.exists, isTrue);
        expect(snap.data()!['status'], equals('confirmed'));
        expect(snap.data()!['athleteId'], equals(athleteId));
      },
    );

    // ─── SCENARIO-490: book when slot already confirmed ───────────────────
    test(
      'SCENARIO-490: book when doc exists status=confirmed → throws SlotAlreadyTakenException',
      () async {
        // Pre-seed a confirmed appointment at the doc ID.
        final existing = Appointment.create(
          trainerId: trainerId,
          athleteId: 'otherAthlete',
          athleteDisplayName: 'Other',
          startsAt: startsAt,
          durationMin: durationMin,
        );
        await firestore
            .collection('appointments')
            .doc(expectedDocId)
            .set(existing.toJson());

        expect(
          () => repo.book(
            trainerId: trainerId,
            athleteId: athleteId,
            athleteDisplayName: athleteDisplayName,
            startsAt: startsAt,
            durationMin: durationMin,
          ),
          throwsA(isA<SlotAlreadyTakenException>()),
        );
      },
    );

    // ─── SCENARIO-491-amended: ADR-1 flip cancelled → confirmed ──────────
    test(
      'SCENARIO-491-amended: book when doc exists status=cancelled → flips to confirmed, preserves cancellationLog',
      () async {
        // Pre-seed a cancelled appointment with an existing cancellation log.
        final cancelledAppt = Appointment(
          id: expectedDocId,
          trainerId: trainerId,
          athleteId: 'oldAthlete',
          athleteDisplayName: 'Old Athlete',
          startsAt: startsAt,
          durationMin: durationMin,
          status: AppointmentStatus.cancelled,
          cancelledAt: DateTime.utc(2026, 6, 28),
          cancelledBy: 'oldAthlete',
          cancellationLog: const [
            CancellationEntry(byUid: 'oldAthlete', atMs: 1751068800000),
          ],
        );
        await firestore
            .collection('appointments')
            .doc(expectedDocId)
            .set(cancelledAppt.toJson());

        final appt = await repo.book(
          trainerId: trainerId,
          athleteId: athleteId,
          athleteDisplayName: athleteDisplayName,
          startsAt: startsAt,
          durationMin: durationMin,
        );

        expect(appt.status, equals(AppointmentStatus.confirmed));
        expect(appt.athleteId, equals(athleteId));
        expect(appt.cancelledAt, isNull);
        expect(appt.cancelledBy, isNull);

        // cancellationLog MUST be preserved (ADR-1 audit trail).
        final snap =
            await firestore.collection('appointments').doc(expectedDocId).get();
        final log = snap.data()!['cancellationLog'] as List<dynamic>;
        expect(log, hasLength(1));
        expect((log.first as Map<String, dynamic>)['byUid'], 'oldAthlete');
      },
    );

    // ─── REQ-COACH-AGENDA-009: 28-day booking horizon ────────────────────
    test(
      'REQ-COACH-AGENDA-009: book throws BookingTooFarAheadException when '
      'startsAt is more than 28 days out',
      () async {
        // 29 days from now → beyond the 28-day horizon.
        final tooFar = DateTime.now().toUtc().add(const Duration(days: 29));
        final tooFarMinute = DateTime.utc(
          tooFar.year,
          tooFar.month,
          tooFar.day,
          tooFar.hour,
          tooFar.minute,
        );

        await expectLater(
          repo.book(
            trainerId: trainerId,
            athleteId: athleteId,
            athleteDisplayName: athleteDisplayName,
            startsAt: tooFarMinute,
            durationMin: durationMin,
          ),
          throwsA(isA<BookingTooFarAheadException>()),
        );

        // Nothing was written.
        final all = await firestore.collection('appointments').get();
        expect(all.docs, isEmpty);
      },
    );

    test(
      'REQ-COACH-AGENDA-009: book succeeds when startsAt is within 28 days',
      () async {
        // 27 days from now → inside the horizon.
        final soon = DateTime.now().toUtc().add(const Duration(days: 27));
        final soonMinute = DateTime.utc(
          soon.year,
          soon.month,
          soon.day,
          soon.hour,
          soon.minute,
        );

        final appt = await repo.book(
          trainerId: trainerId,
          athleteId: athleteId,
          athleteDisplayName: athleteDisplayName,
          startsAt: soonMinute,
          durationMin: durationMin,
        );

        expect(appt.status, equals(AppointmentStatus.confirmed));
      },
    );

    // ─── SCENARIO-496: deterministic doc ID assertion ─────────────────────
    test(
      'SCENARIO-496: book asserts doc ID is exactly trainerId_startsAtMs',
      () async {
        final appt = await repo.book(
          trainerId: trainerId,
          athleteId: athleteId,
          athleteDisplayName: athleteDisplayName,
          startsAt: startsAt,
          durationMin: durationMin,
        );

        expect(
            appt.id, equals('${trainerId}_${startsAt.millisecondsSinceEpoch}'));

        // Verify the document exists at that exact ID.
        final snap =
            await firestore.collection('appointments').doc(appt.id).get();
        expect(snap.exists, isTrue);
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────────
  // cancel(), watchForAthlete(), watchForTrainer()
  // ─────────────────────────────────────────────────────────────────────────

  group('cancel()', () {
    Appointment makeConfirmedAppt({
      required DateTime startsAt,
      String id = '',
    }) {
      final appt = Appointment.create(
        trainerId: trainerId,
        athleteId: athleteId,
        athleteDisplayName: athleteDisplayName,
        startsAt: startsAt,
        durationMin: durationMin,
      );
      return id.isEmpty ? appt : appt.copyWith(id: id);
    }

    // ─── SCENARIO-492: cancellation succeeds when >24h ahead ─────────────
    test(
      'SCENARIO-492: cancel succeeds when >24h ahead → status=cancelled, cancelledAt/By set, appends to log',
      () async {
        // startsAt is in the far future — always >24h away.
        final future = DateTime.utc(2030, 1, 1, 10, 0);
        final appt = makeConfirmedAppt(startsAt: future);
        await firestore
            .collection('appointments')
            .doc(appt.id)
            .set(appt.toJson());

        await repo.cancel(
          appointment: appt,
          actorUid: athleteId,
          reason: 'changed plans',
        );

        final snap =
            await firestore.collection('appointments').doc(appt.id).get();
        expect(snap.data()!['status'], equals('cancelled'));
        expect(snap.data()!['cancelledBy'], equals(athleteId));
        // cancellationLog should have one entry.
        final log = snap.data()!['cancellationLog'] as List<dynamic>;
        expect(log, hasLength(1));
        expect((log.first as Map<String, dynamic>)['byUid'], equals(athleteId));
        expect(
          (log.first as Map<String, dynamic>)['reason'],
          equals('changed plans'),
        );
      },
    );

    // ─── SCENARIO-493: CancellationTooLateException when <24h ahead ──────
    test(
      'SCENARIO-493: cancel throws CancellationTooLateException when <24h ahead',
      () async {
        // startsAt is 1 hour from now.
        final soon = DateTime.now().toUtc().add(const Duration(hours: 1));
        final soonMinutePrecision = DateTime.utc(
          soon.year,
          soon.month,
          soon.day,
          soon.hour,
          soon.minute,
        );
        final appt = makeConfirmedAppt(startsAt: soonMinutePrecision);
        await firestore
            .collection('appointments')
            .doc(appt.id)
            .set(appt.toJson());

        expect(
          () => repo.cancel(appointment: appt, actorUid: athleteId),
          throwsA(isA<CancellationTooLateException>()),
        );
      },
    );
  });

  group('createRecurringByTrainer() + cancelFutureSeries()', () {
    // Far-future window so every occurrence is >24h away (cancellable). Using
    // all weekdays + a 4-day range makes the count deterministic regardless of
    // which weekday the range starts on: 4 occurrences (Jan 7, 8, 9, 10).
    final from = DateTime.utc(2030, 1, 7);
    final until = DateTime.utc(2030, 1, 10);
    const everyDay = {1, 2, 3, 4, 5, 6, 7};

    Future<int> seedSeries() => repo.createRecurringByTrainer(
          trainerId: trainerId,
          athleteId: athleteId,
          athleteDisplayName: athleteDisplayName,
          weekdays: everyDay,
          startHour: 10,
          startMinute: 0,
          durationMin: durationMin,
          fromDate: from,
          untilDate: until,
        );

    test(
        'createRecurringByTrainer stamps ONE shared non-null recurringId on '
        'every occurrence', () async {
      final count = await seedSeries();
      expect(count, 4);

      final snap = await firestore.collection('appointments').get();
      expect(snap.docs, hasLength(4));
      final ids =
          snap.docs.map((d) => d.data()['recurringId'] as String?).toSet();
      expect(ids, hasLength(1)); // all occurrences share the same series id
      expect(ids.first, isNotNull);
    });

    test(
        'cancelFutureSeries cancels every future occurrence of the series and '
        'returns the count', () async {
      await seedSeries();
      final created = await firestore.collection('appointments').get();
      final recurringId = created.docs.first.data()['recurringId'] as String;

      final cancelled = await repo.cancelFutureSeries(
        recurringId: recurringId,
        trainerId: trainerId,
        actorUid: trainerId,
      );
      expect(cancelled, 4);

      final after = await firestore.collection('appointments').get();
      expect(
        after.docs.every((d) => d.data()['status'] == 'cancelled'),
        isTrue,
      );
    });

    test('cancelFutureSeries leaves a single (non-recurring) appointment alone',
        () async {
      await seedSeries();
      final created = await firestore.collection('appointments').get();
      final recurringId = created.docs.first.data()['recurringId'] as String;

      // A standalone confirmed appointment, far future, no recurringId.
      final single = Appointment.create(
        trainerId: trainerId,
        athleteId: athleteId,
        athleteDisplayName: athleteDisplayName,
        startsAt: DateTime.utc(2030, 1, 15, 9, 0),
        durationMin: durationMin,
      );
      await firestore
          .collection('appointments')
          .doc(single.id)
          .set(single.toJson());

      await repo.cancelFutureSeries(
        recurringId: recurringId,
        trainerId: trainerId,
        actorUid: trainerId,
      );

      final singleSnap =
          await firestore.collection('appointments').doc(single.id).get();
      expect(singleSnap.data()!['status'], 'confirmed');
    });
  });

  group('watchForAthlete()', () {
    // ─── SCENARIO-494: streams confirmed appointments for athleteId ───────
    test(
      'SCENARIO-494: watchForAthlete streams confirmed appointments for athleteId',
      () async {
        final appt1 = Appointment.create(
          trainerId: trainerId,
          athleteId: athleteId,
          athleteDisplayName: athleteDisplayName,
          startsAt: DateTime.utc(2026, 7, 1, 10, 0),
          durationMin: durationMin,
        );
        final appt2 = Appointment.create(
          trainerId: trainerId,
          athleteId: athleteId,
          athleteDisplayName: athleteDisplayName,
          startsAt: DateTime.utc(2026, 7, 2, 10, 0),
          durationMin: durationMin,
        );
        // Different athlete — should NOT appear.
        final apptOther = Appointment.create(
          trainerId: trainerId,
          athleteId: 'otherAthlete',
          athleteDisplayName: 'Other',
          startsAt: DateTime.utc(2026, 7, 3, 10, 0),
          durationMin: durationMin,
        );

        await firestore
            .collection('appointments')
            .doc(appt1.id)
            .set(appt1.toJson());
        await firestore
            .collection('appointments')
            .doc(appt2.id)
            .set(appt2.toJson());
        await firestore
            .collection('appointments')
            .doc(apptOther.id)
            .set(apptOther.toJson());

        final results = await repo.watchForAthlete(athleteId).first;
        expect(results, hasLength(2));
        expect(results.map((a) => a.athleteId).toSet(), equals({athleteId}));
        expect(results.every((a) => a.status == AppointmentStatus.confirmed),
            isTrue);
      },
    );
  });

  group('watchForTrainer()', () {
    // ─── SCENARIO-495: streams confirmed appointments for trainerId in date range ─
    test(
      'SCENARIO-495: watchForTrainer streams confirmed appointments for trainerId in date range',
      () async {
        final apptInRange = Appointment.create(
          trainerId: trainerId,
          athleteId: athleteId,
          athleteDisplayName: athleteDisplayName,
          startsAt: DateTime.utc(2026, 7, 5, 10, 0),
          durationMin: durationMin,
        );
        // Outside range — should NOT appear.
        final apptOutside = Appointment.create(
          trainerId: trainerId,
          athleteId: athleteId,
          athleteDisplayName: athleteDisplayName,
          startsAt: DateTime.utc(2026, 8, 1, 10, 0),
          durationMin: durationMin,
        );

        await firestore
            .collection('appointments')
            .doc(apptInRange.id)
            .set(apptInRange.toJson());
        await firestore
            .collection('appointments')
            .doc(apptOutside.id)
            .set(apptOutside.toJson());

        final results = await repo
            .watchForTrainer(
              trainerId,
              fromDate: DateTime.utc(2026, 7, 1),
              toDate: DateTime.utc(2026, 7, 31),
            )
            .first;

        expect(results, hasLength(1));
        expect(results.single.id, equals(apptInRange.id));
        expect(results.single.trainerId, equals(trainerId));
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Slice 2a — Agenda→cobro bridge: billAppointment() + markBilled()
  // MONEY-CRITICAL: these pin the atomic create-Payment+link-appointment
  // transaction and its race/guard behavior.
  // ─────────────────────────────────────────────────────────────────────────

  group('billAppointment()', () {
    Appointment confirmedAppt(String id) => Appointment(
          id: id,
          trainerId: trainerId,
          athleteId: athleteId,
          athleteDisplayName: athleteDisplayName,
          startsAt: startsAt,
          durationMin: durationMin,
          status: AppointmentStatus.confirmed,
        );

    Payment pendingPayment({DateTime? dueAt}) => Payment(
          id: '',
          trainerId: trainerId,
          athleteId: athleteId,
          amountArs: 5000,
          concept: 'Sesión 01/07/2026',
          status: PaymentStatus.pending,
          createdAt: DateTime.utc(2026, 7, 1),
          dueAt: dueAt,
        );

    test(
      '(a) creates a Payment doc (athleteId from the appointment, status '
      'pending, correct amount) AND atomically sets appointment.paymentId',
      () async {
        final appt = confirmedAppt('appt-bill-1');
        await firestore
            .collection('appointments')
            .doc(appt.id)
            .set(appt.toJson());

        final paymentId = await repo.billAppointment(
          appointment: appt,
          payment: pendingPayment(),
        );

        expect(paymentId, isNotEmpty);

        final paymentSnap =
            await firestore.collection('payments').doc(paymentId).get();
        expect(paymentSnap.exists, isTrue);
        expect(paymentSnap.data()!['id'], equals(paymentId));
        expect(paymentSnap.data()!['trainerId'], equals(trainerId));
        expect(paymentSnap.data()!['athleteId'], equals(athleteId));
        expect(paymentSnap.data()!['amountArs'], equals(5000));
        expect(paymentSnap.data()!['status'], equals('pending'));

        final apptSnap =
            await firestore.collection('appointments').doc(appt.id).get();
        expect(apptSnap.data()!['paymentId'], equals(paymentId));
      },
    );

    test(
      '(d) propagates an optional dueAt onto the created Payment',
      () async {
        final appt = confirmedAppt('appt-bill-2');
        await firestore
            .collection('appointments')
            .doc(appt.id)
            .set(appt.toJson());
        final dueAt = DateTime.utc(2026, 7, 15, 23, 59, 59);

        final paymentId = await repo.billAppointment(
          appointment: appt,
          payment: pendingPayment(dueAt: dueAt),
        );

        final paymentSnap =
            await firestore.collection('payments').doc(paymentId).get();
        expect(paymentSnap.data()!['dueAt'], isNotNull);
      },
    );

    test(
      '(d) dueAt stays null on the created Payment when not provided',
      () async {
        final appt = confirmedAppt('appt-bill-3');
        await firestore
            .collection('appointments')
            .doc(appt.id)
            .set(appt.toJson());

        final paymentId = await repo.billAppointment(
          appointment: appt,
          payment: pendingPayment(),
        );

        final paymentSnap =
            await firestore.collection('payments').doc(paymentId).get();
        expect(paymentSnap.data()!['dueAt'], isNull);
      },
    );

    test(
      '(b) throws AppointmentAlreadyBilledException when paymentId is '
      'already set — guards re-cobro: no second Payment doc is created and '
      'the existing paymentId is left untouched',
      () async {
        final appt = confirmedAppt('appt-bill-4');
        await firestore.collection('appointments').doc(appt.id).set({
          ...appt.toJson(),
          'paymentId': 'existing-payment-id',
        });

        await expectLater(
          repo.billAppointment(
            appointment: appt,
            payment: pendingPayment(),
          ),
          throwsA(isA<AppointmentAlreadyBilledException>()),
        );

        final payments = await firestore.collection('payments').get();
        expect(payments.docs, isEmpty);

        final apptSnap =
            await firestore.collection('appointments').doc(appt.id).get();
        expect(apptSnap.data()!['paymentId'], equals('existing-payment-id'));
      },
    );

    test(
      'throws AppointmentNotConfirmedException when the live status is not '
      'confirmed (e.g. cancelled concurrently after the dialog opened) — no '
      'Payment doc is created',
      () async {
        final appt = confirmedAppt('appt-bill-5');
        await firestore.collection('appointments').doc(appt.id).set({
          ...appt.toJson(),
          'status': 'cancelled',
        });

        await expectLater(
          repo.billAppointment(
            appointment: appt,
            payment: pendingPayment(),
          ),
          throwsA(isA<AppointmentNotConfirmedException>()),
        );

        final payments = await firestore.collection('payments').get();
        expect(payments.docs, isEmpty);
      },
    );

    test(
      'throws AppointmentNotFoundException when the appointment doc does '
      'not exist — no Payment doc is created',
      () async {
        final appt = confirmedAppt('appt-bill-does-not-exist');
        // Deliberately NOT seeded in Firestore.

        await expectLater(
          repo.billAppointment(
            appointment: appt,
            payment: pendingPayment(),
          ),
          throwsA(isA<AppointmentNotFoundException>()),
        );

        final payments = await firestore.collection('payments').get();
        expect(payments.docs, isEmpty);
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Slice 2b — cobro por lote desde la agenda: billAppointments()
  // MONEY-CRITICAL: pins the atomic create-ONE-Payment+link-N-appointments
  // transaction — all-or-nothing across the whole lote.
  // ─────────────────────────────────────────────────────────────────────────

  group('billAppointments()', () {
    const otherAthleteId = 'athlete2';
    const otherTrainerId = 'trainer2';

    Appointment confirmedApptAt(
      String id,
      DateTime at, {
      String athlete = athleteId,
      String trainer = trainerId,
    }) =>
        Appointment(
          id: id,
          trainerId: trainer,
          athleteId: athlete,
          athleteDisplayName: athleteDisplayName,
          startsAt: at,
          durationMin: durationMin,
          status: AppointmentStatus.confirmed,
        );

    Payment lotePayment({int amountArs = 15000, String? concept}) => Payment(
          id: '',
          trainerId: trainerId,
          athleteId: athleteId,
          amountArs: amountArs,
          concept: concept ?? '3 sesiones',
          status: PaymentStatus.pending,
          createdAt: DateTime.utc(2026, 7, 1),
        );

    /// Seeds 3 confirmed same-athlete appointments and returns them.
    Future<List<Appointment>> seedThree() async {
      final appts = [
        confirmedApptAt('lote-1', DateTime.utc(2026, 7, 1, 9, 0)),
        confirmedApptAt('lote-2', DateTime.utc(2026, 7, 1, 10, 0)),
        confirmedApptAt('lote-3', DateTime.utc(2026, 7, 1, 11, 0)),
      ];
      for (final a in appts) {
        await firestore.collection('appointments').doc(a.id).set(a.toJson());
      }
      return appts;
    }

    test(
      'N turnos same-athlete → crea 1 Payment (monto, concepto, athleteId '
      'correctos) y marca los N turnos con ese paymentId',
      () async {
        final appts = await seedThree();

        final paymentId = await repo.billAppointments(
          appointments: appts,
          payment: lotePayment(amountArs: 15000, concept: '3 sesiones'),
        );

        // Exactamente 1 Payment creado.
        final payments = await firestore.collection('payments').get();
        expect(payments.docs, hasLength(1));
        final paymentData = payments.docs.single.data();
        expect(paymentData['id'], equals(paymentId));
        expect(paymentData['athleteId'], equals(athleteId));
        expect(paymentData['trainerId'], equals(trainerId));
        expect(paymentData['amountArs'], equals(15000));
        expect(paymentData['concept'], equals('3 sesiones'));
        expect(paymentData['status'], equals('pending'));

        // Los 3 turnos quedan marcados con el MISMO paymentId.
        for (final a in appts) {
          final snap =
              await firestore.collection('appointments').doc(a.id).get();
          expect(snap.data()!['paymentId'], equals(paymentId));
        }
      },
    );

    test(
      'lote que incluye un turno ya cobrado → aborta TODO el lote: no crea '
      'el Payment ni marca ninguno de los otros turnos',
      () async {
        final appts = await seedThree();
        // El 2do turno ya tiene un paymentId de un cobro previo.
        await firestore.collection('appointments').doc('lote-2').update({
          'paymentId': 'payment-previo',
        });

        await expectLater(
          repo.billAppointments(appointments: appts, payment: lotePayment()),
          throwsA(isA<AppointmentAlreadyBilledException>()),
        );

        // Nada se escribió: ni el Payment...
        final payments = await firestore.collection('payments').get();
        expect(payments.docs, isEmpty);

        // ...ni el paymentId de los turnos que SÍ eran válidos (lote-1, lote-3).
        final snap1 =
            await firestore.collection('appointments').doc('lote-1').get();
        expect(snap1.data()!['paymentId'], isNull);
        final snap3 =
            await firestore.collection('appointments').doc('lote-3').get();
        expect(snap3.data()!['paymentId'], isNull);

        // El ya-cobrado conserva su paymentId original (no se pisó).
        final snap2 =
            await firestore.collection('appointments').doc('lote-2').get();
        expect(snap2.data()!['paymentId'], equals('payment-previo'));
      },
    );

    test(
      'lote que incluye un turno no confirmado (cancelado concurrentemente) '
      '→ aborta TODO el lote, no escribe nada',
      () async {
        final appts = await seedThree();
        await firestore.collection('appointments').doc('lote-3').update({
          'status': 'cancelled',
        });

        await expectLater(
          repo.billAppointments(appointments: appts, payment: lotePayment()),
          throwsA(isA<AppointmentNotConfirmedException>()),
        );

        final payments = await firestore.collection('payments').get();
        expect(payments.docs, isEmpty);
        final snap1 =
            await firestore.collection('appointments').doc('lote-1').get();
        expect(snap1.data()!['paymentId'], isNull);
      },
    );

    test(
      'lote que incluye un turno inexistente → aborta TODO el lote, no '
      'escribe nada',
      () async {
        final appts = await seedThree();
        final withMissing = [
          ...appts,
          confirmedApptAt('lote-does-not-exist', DateTime.utc(2026, 7, 1, 12)),
        ];

        await expectLater(
          repo.billAppointments(
              appointments: withMissing, payment: lotePayment()),
          throwsA(isA<AppointmentNotFoundException>()),
        );

        final payments = await firestore.collection('payments').get();
        expect(payments.docs, isEmpty);
      },
    );

    // NOTE on the next 2 tests: billAppointments has TWO independent guards
    // against a mixed-athlete/mixed-trainer lote —
    //   (1) a debug-only `assert()` on the Appointment OBJECTS the caller
    //       passes in (fails fast in dev/tests, compiled OUT of release
    //       builds), and
    //   (2) the in-transaction re-validation against the LIVE Firestore doc
    //       (runs in every build mode — the actual production safety net).
    // To pin (2) specifically (not just re-trigger (1)), the Appointment
    // OBJECT passed to billAppointments must itself claim the SAME
    // athleteId/trainerId as the payment (so the assert passes), while the
    // Firestore doc seeded at that id disagrees — simulating a caller/UI bug
    // that would slip straight through in a release build if (2) didn't
    // exist.
    test(
      'lote con un doc LIVE de OTRO alumno, mientras el objeto que pasa el '
      'caller "miente" y declara el mismo athleteId que el payment (bypassea '
      'el assert de debug) → la revalidación server-side dentro de la '
      'transacción lo detecta igual: aborta TODO el lote, no escribe nada',
      () async {
        final appts = await seedThree();

        // Doc LIVE en Firestore: pertenece a otro athleteId.
        final liveForeign = confirmedApptAt(
          'lote-foreign',
          DateTime.utc(2026, 7, 1, 13, 0),
          athlete: otherAthleteId,
        );
        await firestore
            .collection('appointments')
            .doc(liveForeign.id)
            .set(liveForeign.toJson());

        // Objeto que pasa el caller para ESE MISMO id: declara el athleteId
        // del payment (pasa el assert), pero la doc real dice otra cosa.
        final claimedSameAthlete =
            confirmedApptAt(liveForeign.id, DateTime.utc(2026, 7, 1, 13, 0));

        await expectLater(
          repo.billAppointments(
            appointments: [...appts, claimedSameAthlete],
            payment: lotePayment(), // payment.athleteId == athleteId
          ),
          throwsA(isA<AppointmentAthleteMismatchException>()),
        );

        final payments = await firestore.collection('payments').get();
        expect(payments.docs, isEmpty);
        for (final a in appts) {
          final snap =
              await firestore.collection('appointments').doc(a.id).get();
          expect(snap.data()!['paymentId'], isNull);
        }
      },
    );

    test(
      'lote con un doc LIVE de OTRO trainer, objeto pasado por el caller '
      '"miente" y declara el mismo trainerId que el payment (bypassea el '
      'assert de debug) → la revalidación server-side lo detecta igual: '
      'aborta TODO el lote, no escribe nada',
      () async {
        final appts = await seedThree();

        final liveForeign = confirmedApptAt(
          'lote-foreign-trainer',
          DateTime.utc(2026, 7, 1, 13, 0),
          trainer: otherTrainerId,
        );
        await firestore
            .collection('appointments')
            .doc(liveForeign.id)
            .set(liveForeign.toJson());

        final claimedSameTrainer =
            confirmedApptAt(liveForeign.id, DateTime.utc(2026, 7, 1, 13, 0));

        await expectLater(
          repo.billAppointments(
            appointments: [...appts, claimedSameTrainer],
            payment: lotePayment(), // payment.trainerId == trainerId
          ),
          throwsA(isA<AppointmentAthleteMismatchException>()),
        );

        final payments = await firestore.collection('payments').get();
        expect(payments.docs, isEmpty);
      },
    );

    test('N=1 (lote de un solo turno) funciona igual que el caso general',
        () async {
      final appt =
          confirmedApptAt('lote-single', DateTime.utc(2026, 7, 1, 9, 0));
      await firestore
          .collection('appointments')
          .doc(appt.id)
          .set(appt.toJson());

      final paymentId = await repo.billAppointments(
        appointments: [appt],
        payment: lotePayment(amountArs: 5000, concept: '1 sesión'),
      );

      final snap =
          await firestore.collection('appointments').doc(appt.id).get();
      expect(snap.data()!['paymentId'], equals(paymentId));
    });
  });

  group('markBilled()', () {
    test('(a) sets paymentId on the appointment doc', () async {
      final appt = Appointment.create(
        trainerId: trainerId,
        athleteId: athleteId,
        athleteDisplayName: athleteDisplayName,
        startsAt: startsAt,
        durationMin: durationMin,
      );
      await firestore
          .collection('appointments')
          .doc(appt.id)
          .set(appt.toJson());

      await repo.markBilled(appointmentId: appt.id, paymentId: 'payment-xyz');

      final snap =
          await firestore.collection('appointments').doc(appt.id).get();
      expect(snap.data()!['paymentId'], equals('payment-xyz'));
    });
  });
}
