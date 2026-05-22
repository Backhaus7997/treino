import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/data/trainer_link_repository.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late TrainerLinkRepository repo;

  const trainerId = 'trainer-1';
  const athleteId = 'athlete-1';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = TrainerLinkRepository(firestore: firestore);
  });

  // ─── request ──────────────────────────────────────────────────────────────

  group('request', () {
    test('crea doc con status=pending y requestedAt', () async {
      final link = await repo.request(
        trainerId: trainerId,
        athleteId: athleteId,
      );
      expect(link.status, TrainerLinkStatus.pending);
      expect(link.trainerId, trainerId);
      expect(link.athleteId, athleteId);
      expect(link.id, isNotEmpty);

      final snap =
          await firestore.collection('trainer_links').doc(link.id).get();
      expect(snap.exists, isTrue);
      expect(snap.data()!['status'], 'pending');
    });

    test('id es auto-generado por Firestore', () async {
      final l1 = await repo.request(
        trainerId: trainerId,
        athleteId: athleteId,
      );
      final l2 = await repo.request(
        trainerId: trainerId,
        athleteId: athleteId,
      );
      expect(l1.id, isNot(equals(l2.id)));
    });

    test('rechaza trainerId == athleteId', () async {
      expect(
        () => repo.request(trainerId: 'same', athleteId: 'same'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ─── accept ───────────────────────────────────────────────────────────────

  group('accept', () {
    test('transiciona pending → active y setea acceptedAt', () async {
      final link = await repo.request(
        trainerId: trainerId,
        athleteId: athleteId,
      );
      await repo.accept(link.id);

      final snap =
          await firestore.collection('trainer_links').doc(link.id).get();
      expect(snap.data()!['status'], 'active');
      expect(snap.data()!['acceptedAt'], isA<Timestamp>());
    });

    test('rechaza accept sobre status terminated', () async {
      final link = await repo.request(
        trainerId: trainerId,
        athleteId: athleteId,
      );
      await repo.decline(link.id);
      expect(
        () => repo.accept(link.id),
        throwsA(isA<StateError>()),
      );
    });

    test('rechaza accept sobre doc inexistente', () async {
      expect(
        () => repo.accept('nonexistent'),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ─── decline ──────────────────────────────────────────────────────────────

  group('decline', () {
    test('transiciona pending → terminated con reason=declined', () async {
      final link = await repo.request(
        trainerId: trainerId,
        athleteId: athleteId,
      );
      await repo.decline(link.id);

      final snap =
          await firestore.collection('trainer_links').doc(link.id).get();
      expect(snap.data()!['status'], 'terminated');
      expect(snap.data()!['terminationReason'], 'declined');
      expect(snap.data()!['terminatedAt'], isA<Timestamp>());
    });

    test('rechaza decline sobre status active', () async {
      final link = await repo.request(
        trainerId: trainerId,
        athleteId: athleteId,
      );
      await repo.accept(link.id);
      expect(
        () => repo.decline(link.id),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ─── terminate ────────────────────────────────────────────────────────────

  group('terminate', () {
    test('transiciona active → terminated', () async {
      final link = await repo.request(
        trainerId: trainerId,
        athleteId: athleteId,
      );
      await repo.accept(link.id);
      await repo.terminate(link.id, reason: 'changed-mind');

      final snap =
          await firestore.collection('trainer_links').doc(link.id).get();
      expect(snap.data()!['status'], 'terminated');
      expect(snap.data()!['terminationReason'], 'changed-mind');
    });

    test('reason es opcional', () async {
      final link = await repo.request(
        trainerId: trainerId,
        athleteId: athleteId,
      );
      await repo.accept(link.id);
      await repo.terminate(link.id);

      final snap =
          await firestore.collection('trainer_links').doc(link.id).get();
      expect(snap.data()!['status'], 'terminated');
      expect(snap.data()!['terminationReason'], isNull);
    });

    test('rechaza terminate sobre pending', () async {
      final link = await repo.request(
        trainerId: trainerId,
        athleteId: athleteId,
      );
      expect(
        () => repo.terminate(link.id),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ─── listForTrainer ───────────────────────────────────────────────────────

  group('listForTrainer', () {
    test('devuelve vínculos del PF ordenados DESC por requestedAt', () async {
      // Crear 2 vínculos en orden — el segundo debe quedar primero.
      await repo.request(trainerId: trainerId, athleteId: 'a1');
      await Future.delayed(const Duration(milliseconds: 10));
      final l2 = await repo.request(trainerId: trainerId, athleteId: 'a2');

      final list = await repo.listForTrainer(trainerId);
      expect(list, hasLength(2));
      expect(list.first.id, l2.id); // más reciente primero
    });

    test('filtra por status cuando se pasa el parámetro', () async {
      final l1 = await repo.request(trainerId: trainerId, athleteId: 'a1');
      await repo.request(trainerId: trainerId, athleteId: 'a2');
      await repo.accept(l1.id);

      final active = await repo.listForTrainer(
        trainerId,
        statuses: {TrainerLinkStatus.active},
      );
      expect(active, hasLength(1));
      expect(active.first.id, l1.id);

      final pending = await repo.listForTrainer(
        trainerId,
        statuses: {TrainerLinkStatus.pending},
      );
      expect(pending, hasLength(1));
    });

    test('devuelve lista vacía cuando no hay vínculos', () async {
      final list = await repo.listForTrainer('uid-without-links');
      expect(list, isEmpty);
    });
  });

  // ─── listForAthlete ───────────────────────────────────────────────────────

  group('listForAthlete', () {
    test('devuelve solo los vínculos donde el user es atleta', () async {
      await repo.request(trainerId: 'pf-1', athleteId: athleteId);
      await repo.request(trainerId: 'pf-2', athleteId: athleteId);
      await repo.request(trainerId: 'pf-1', athleteId: 'otro-atleta');

      final list = await repo.listForAthlete(athleteId);
      expect(list, hasLength(2));
      expect(list.every((l) => l.athleteId == athleteId), isTrue);
    });
  });

  // ─── setSharedWithTrainer ─────────────────────────────────────────────────

  group('setSharedWithTrainer', () {
    test(
      'SCENARIO-466: actualiza solo sharedWithTrainer y preserva otros campos',
      () async {
        // GIVEN un trainer_links doc con sharedWithTrainer: false, status: active
        final link = await repo.request(
          trainerId: trainerId,
          athleteId: athleteId,
        );
        await repo.accept(link.id);

        final before =
            await firestore.collection('trainer_links').doc(link.id).get();
        final beforeData = before.data()!;

        // WHEN llamamos setSharedWithTrainer(linkId, true)
        await repo.setSharedWithTrainer(link.id, true);

        // THEN el doc tiene sharedWithTrainer == true
        final after =
            await firestore.collection('trainer_links').doc(link.id).get();
        final afterData = after.data()!;
        expect(afterData['sharedWithTrainer'], true);

        // AND status, trainerId, athleteId, requestedAt no cambiaron
        expect(afterData['status'], beforeData['status']);
        expect(afterData['trainerId'], beforeData['trainerId']);
        expect(afterData['athleteId'], beforeData['athleteId']);
        expect(afterData['requestedAt'], beforeData['requestedAt']);

        // AND updatedAt NO existe (REQ-COACH-LINK-004 — sin updatedAt).
        expect(afterData.containsKey('updatedAt'), isFalse);

        // AND solo agregamos sharedWithTrainer relativo al doc previo —
        // ningún otro campo nuevo aparece.
        final addedKeys =
            afterData.keys.toSet().difference(beforeData.keys.toSet());
        expect(addedKeys, isEmpty,
            reason: 'setSharedWithTrainer no debe agregar campos nuevos '
                'más allá de sharedWithTrainer (que ya tendría que existir '
                'al crear el doc por el @Default(false))');
      },
    );

    test(
      'SCENARIO-467: lanza excepción cuando el documento no existe',
      () async {
        // GIVEN no existe doc en trainer_links/non-existent-id
        // WHEN llamamos setSharedWithTrainer('non-existent-id', true)
        // THEN se lanza una excepción y no hay no-op silencioso
        await expectLater(
          () => repo.setSharedWithTrainer('non-existent-id', true),
          throwsA(isA<Exception>()),
        );
      },
    );

    test(
      'SCENARIO-468: idempotente cuando el valor no cambia',
      () async {
        // GIVEN un doc con sharedWithTrainer: false (default)
        final link = await repo.request(
          trainerId: trainerId,
          athleteId: athleteId,
        );

        // WHEN llamamos setSharedWithTrainer(linkId, false)
        await repo.setSharedWithTrainer(link.id, false);

        // THEN no se lanza excepción AND el doc sigue con sharedWithTrainer == false
        final snap =
            await firestore.collection('trainer_links').doc(link.id).get();
        expect(snap.data()!['sharedWithTrainer'], false);
      },
    );
  });

  // ─── watchForTrainer ──────────────────────────────────────────────────────

  group('watchForTrainer', () {
    test('emite lista actualizada cuando cambia status del vínculo', () async {
      final link = await repo.request(
        trainerId: trainerId,
        athleteId: athleteId,
      );
      final stream = repo.watchForTrainer(trainerId);

      final emissions = <List<String>>[];
      final sub = stream.listen((links) {
        emissions.add(links.map((l) => l.status.toJson()).toList());
      });

      // Wait for initial emission.
      await Future.delayed(const Duration(milliseconds: 10));
      expect(emissions.first, ['pending']);

      await repo.accept(link.id);
      await Future.delayed(const Duration(milliseconds: 10));
      expect(emissions.last, ['active']);

      await sub.cancel();
    });
  });
}
