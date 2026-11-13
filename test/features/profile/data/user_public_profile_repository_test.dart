// Los dobles de Firestore de #1698 implementan `CollectionReference` y
// `DocumentReference` (selladas) para simular el permission-denied de las
// reglas, que fake_cloud_firestore no evalúa.
// ignore_for_file: subtype_of_sealed_class

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/profile/data/user_public_profile_repository.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late UserPublicProfileRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = UserPublicProfileRepository(firestore: firestore);
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-254: get returns null for missing doc
  // ──────────────────────────────────────────────────────────────────────────
  test('SCENARIO-254: get returns null for missing doc', () async {
    final result = await repo.get('u99');
    expect(result, isNull);
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-255: set + get round-trip
  // ──────────────────────────────────────────────────────────────────────────
  test('SCENARIO-255: set then get returns the same profile', () async {
    const profile = UserPublicProfile(
      uid: 'u1',
      displayName: 'Ana',
      displayNameLowercase: 'ana',
      avatarUrl: null,
      gymId: 'g1',
    );

    await repo.set(profile);
    final result = await repo.get('u1');

    expect(result, isNotNull);
    expect(result!.uid, equals('u1'));
    expect(result.displayName, equals('Ana'));
    expect(result.displayNameLowercase, equals('ana'));
    expect(result.gymId, equals('g1'));
    expect(result.avatarUrl, isNull);
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-256: searchByDisplayName prefix match
  // ──────────────────────────────────────────────────────────────────────────
  test('SCENARIO-256: searchByDisplayName returns prefix matches', () async {
    await firestore.collection('userPublicProfiles').doc('a').set({
      'uid': 'a',
      'displayName': 'Martín',
      'displayNameLowercase': 'martín',
      'avatarUrl': null,
      'gymId': null,
    });
    await firestore.collection('userPublicProfiles').doc('b').set({
      'uid': 'b',
      'displayName': 'Marta',
      'displayNameLowercase': 'marta',
      'avatarUrl': null,
      'gymId': null,
    });
    await firestore.collection('userPublicProfiles').doc('c').set({
      'uid': 'c',
      'displayName': 'Carlos',
      'displayNameLowercase': 'carlos',
      'avatarUrl': null,
      'gymId': null,
    });

    final results = await repo.searchByDisplayName('mar');

    expect(results.length, equals(2));
    final uids = results.map((p) => p.uid).toSet();
    expect(uids, containsAll(['a', 'b']));
    expect(uids, isNot(contains('c')));
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-257: searchByDisplayName respects 20-result limit
  // ──────────────────────────────────────────────────────────────────────────
  test('SCENARIO-257: searchByDisplayName returns at most 20 results',
      () async {
    // Seed 25 docs whose displayNameLowercase starts with 'test'
    for (var i = 0; i < 25; i++) {
      await firestore.collection('userPublicProfiles').doc('test$i').set({
        'uid': 'test$i',
        'displayName': 'Test$i',
        'displayNameLowercase': 'test$i',
        'avatarUrl': null,
        'gymId': null,
      });
    }

    final results = await repo.searchByDisplayName('test');
    expect(results.length, equals(20));
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-320e: updateCounters() merges only the provided counter fields
  // without clobbering displayName / avatarUrl / gymId written by the
  // identity write-path. Verifies ADR-WRS-12 partial-merge contract.
  // ──────────────────────────────────────────────────────────────────────────
  test(
      'SCENARIO-320e: updateCounters merges without clobbering existing identity fields',
      () async {
    // Seed the identity doc first (as UserRepository would do it)
    await firestore.collection('userPublicProfiles').doc('u10').set({
      'uid': 'u10',
      'displayName': 'Ana Kraft',
      'displayNameLowercase': 'ana kraft',
      'avatarUrl': 'https://cdn.example.com/ana.jpg',
      'gymId': 'gym-elite',
    });

    // Partial counter write (as SessionRepository.finish() uses it)
    await repo.updateCounters('u10', {'workoutsCount': 5, 'racha': 3});

    final result = await repo.get('u10');
    expect(result, isNotNull);

    // Identity fields must NOT be clobbered
    expect(result!.displayName, equals('Ana Kraft'));
    expect(result.displayNameLowercase, equals('ana kraft'));
    expect(result.avatarUrl, equals('https://cdn.example.com/ana.jpg'));
    expect(result.gymId, equals('gym-elite'));

    // Counter fields are written
    expect(result.workoutsCount, equals(5));
    expect(result.racha, equals(3));
    // Unset counters remain null (not overwritten with null)
    expect(result.followersCount, isNull);
    expect(result.followingCount, isNull);
  });

  // ──────────────────────────────────────────────────────────────────────────
  // T06 RED: watch (SCENARIO-479..480)
  // ──────────────────────────────────────────────────────────────────────────

  // SCENARIO-479: watch emits null when the profile doc does not exist
  test('SCENARIO-479: watch emits null when no profile doc exists for uid',
      () async {
    final stream = repo.watch('u99');
    await expectLater(stream, emits(isNull));
  });

  // SCENARIO-480: watch re-emits updated profile on Firestore doc update
  test(
      'SCENARIO-480: watch re-emits updated UserPublicProfile after Firestore doc update',
      () async {
    // Seed initial profile with followersCount: 0
    await firestore.collection('userPublicProfiles').doc('u1').set({
      'uid': 'u1',
      'displayName': 'Ana',
      'displayNameLowercase': 'ana',
      'avatarUrl': null,
      'gymId': null,
      'followersCount': 0,
    });

    final stream = repo.watch('u1');
    final emissions = <UserPublicProfile?>[];
    final sub = stream.listen(emissions.add);

    // Wait for initial emission
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(emissions.length, equals(1));
    expect(emissions.first, isNotNull);
    expect(emissions.first!.followersCount, equals(0));

    // Update the doc
    await firestore
        .collection('userPublicProfiles')
        .doc('u1')
        .update({'followersCount': 5});

    // Wait for re-emission
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(emissions.length, greaterThanOrEqualTo(2));
    expect(emissions.last!.followersCount, equals(5));

    await sub.cancel();
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-258: searchByDisplayName returns empty list for blank query
  // ──────────────────────────────────────────────────────────────────────────
  test(
      'SCENARIO-258: searchByDisplayName returns [] for blank/whitespace query',
      () async {
    // Seed a doc to ensure the repo doesn't hit Firestore
    await firestore.collection('userPublicProfiles').doc('u1').set({
      'uid': 'u1',
      'displayName': 'Ana',
      'displayNameLowercase': 'ana',
      'avatarUrl': null,
      'gymId': null,
    });

    final resultsBlank = await repo.searchByDisplayName('');
    expect(resultsBlank, isEmpty);

    final resultsWhitespace = await repo.searchByDisplayName('   ');
    expect(resultsWhitespace, isEmpty);
  });

  // ──────────────────────────────────────────────────────────────────────────
  // #1478: por cualquier palabra del nombre, sin tildes (`searchPrefixes`, que
  // escribe la Cloud Function), y la consulta vieja en paralelo hasta el
  // backfill.
  // ──────────────────────────────────────────────────────────────────────────
  group('#1478 searchByDisplayName por searchPrefixes', () {
    // Lo que la CF guardaría para cada nombre (ver
    // test/fixtures/search/user_search_terms.json).
    const martinLopez = [
      'ma', 'mar', 'mart', 'marti', 'martin', //
      'lo', 'lop', 'lope', 'lopez',
    ];
    const martinGomez = [
      'ma', 'mar', 'mart', 'marti', 'martin', //
      'go', 'gom', 'gome', 'gomez',
    ];

    Future<void> seed(
      String uid,
      String name, {
      List<String>? prefixes,
    }) =>
        firestore.collection('userPublicProfiles').doc(uid).set({
          'uid': uid,
          'displayName': name,
          'displayNameLowercase': name.toLowerCase(),
          if (prefixes != null) 'searchPrefixes': prefixes,
        });

    Future<List<String>> uidsFor(String query) async =>
        (await repo.searchByDisplayName(query)).map((p) => p.uid).toList();

    test('"martin" encuentra a "Martín López" (la vieja no: tiene tilde)',
        () async {
      await seed('ml', 'Martín López', prefixes: martinLopez);
      expect(await uidsFor('martin'), ['ml']);
    });

    test('"lopez" y "LÓPEZ" encuentran por el apellido', () async {
      await seed('ml', 'Martín López', prefixes: martinLopez);
      expect(await uidsFor('lopez'), ['ml']);
      expect(await uidsFor('LÓPEZ'), ['ml']);
      expect(await uidsFor('  lóp '), ['ml']);
    });

    test('varias palabras: todas tienen que estar, en cualquier orden',
        () async {
      await seed('ml', 'Martín López', prefixes: martinLopez);
      await seed('mg', 'Martín Gómez', prefixes: martinGomez);
      expect(await uidsFor('martin lo'), ['ml']);
      expect(await uidsFor('lopez martin'), ['ml']);
      expect((await uidsFor('martin')).toSet(), {'ml', 'mg'});
      expect(await uidsFor('martin pe'), isEmpty);
    });

    test('un perfil que todavía no tiene el campo sale por la consulta vieja',
        () async {
      await seed('viejo', 'martin_88');
      expect(await uidsFor('martin'), ['viejo']);
    });

    test(
        'si lo encuentran las dos consultas, sale una sola vez y primero '
        'en el orden de la vieja', () async {
      await seed('ml', 'Martín López', prefixes: martinLopez);
      await seed('viejo', 'martin_88');
      await seed('mt', 'martina', prefixes: const [
        'ma', 'mar', 'mart', 'marti', 'martin', 'martina', //
      ]);
      expect(await uidsFor('martin'), ['viejo', 'mt', 'ml']);
    });

    test('cada consulta trae hasta 20: juntas no se recortan a 20', () async {
      for (var i = 0; i < 25; i++) {
        await seed('handle$i', 'martin_$i');
      }
      for (var i = 0; i < 25; i++) {
        await seed('real$i', 'Martín López', prefixes: martinLopez);
      }
      final uids = await uidsFor('martin');
      expect(uids, hasLength(40));
      // Lo que vino a arreglar el #1478 no queda afuera por los handles.
      expect(uids.where((u) => u.startsWith('real')), hasLength(20));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // getByIds batch lookup — backs the RESEÑAS section's single-read author
  // resolution (replaces the per-tile N+1 listen pattern).
  // ──────────────────────────────────────────────────────────────────────────
  test('getByIds returns a uid->profile map and omits missing/duplicate ids',
      () async {
    await firestore.collection('userPublicProfiles').doc('u1').set({
      'uid': 'u1',
      'displayName': 'Ana',
      'displayNameLowercase': 'ana',
      'avatarUrl': null,
      'gymId': null,
    });
    await firestore.collection('userPublicProfiles').doc('u2').set({
      'uid': 'u2',
      'displayName': 'Beto',
      'displayNameLowercase': 'beto',
      'avatarUrl': 'https://cdn.example.com/beto.jpg',
      'gymId': null,
    });

    // u3 has no doc (deleted account); u1 is requested twice (deduped).
    final result = await repo.getByIds(['u1', 'u2', 'u3', 'u1']);

    expect(result.keys.toSet(), equals({'u1', 'u2'}));
    expect(result['u1']!.displayName, equals('Ana'));
    expect(result['u2']!.avatarUrl, equals('https://cdn.example.com/beto.jpg'));
    expect(result.containsKey('u3'), isFalse);
  });

  test('getByIds short-circuits on empty input', () async {
    final result = await repo.getByIds(const []);
    expect(result, isEmpty);
  });

  // ──────────────────────────────────────────────────────────────────────────
  // SCENARIO-RANK-4: setRankingOptIn + clearRankingMetrics
  // (opt-in toggle lifecycle, spec `gym-rankings` — Opt-In Toggle Lifecycle)
  // ──────────────────────────────────────────────────────────────────────────

  test(
      'SCENARIO-RANK-4a: setRankingOptIn(uid, true) merges rankingOptIn '
      'without clobbering other fields', () async {
    await firestore.collection('userPublicProfiles').doc('u1').set({
      'uid': 'u1',
      'displayName': 'Ana',
      'displayNameLowercase': 'ana',
      'avatarUrl': null,
      'gymId': 'g1',
      'workoutsCount': 5,
      'racha': 3,
    });

    await repo.setRankingOptIn('u1', true);

    final result = await repo.get('u1');
    expect(result, isNotNull);
    expect(result!.rankingOptIn, isTrue);
    expect(result.displayName, equals('Ana'));
    expect(result.gymId, equals('g1'));
    expect(result.workoutsCount, equals(5));
    expect(result.racha, equals(3));
  });

  test(
      'SCENARIO-RANK-4b: setRankingOptIn(uid, false) merges rankingOptIn=false',
      () async {
    await repo.set(
      const UserPublicProfile(uid: 'u1', rankingOptIn: true),
    );

    await repo.setRankingOptIn('u1', false);

    final result = await repo.get('u1');
    expect(result!.rankingOptIn, isFalse);
  });

  test(
      'SCENARIO-RANK-4c: clearRankingMetrics resets lifetimeVolumeKg/best*Kg '
      'to 0/absent and rankingOptIn to false without clobbering identity '
      'fields', () async {
    await repo.set(
      const UserPublicProfile(
        uid: 'u1',
        displayName: 'Ana',
        gymId: 'g1',
        rankingOptIn: true,
        lifetimeVolumeKg: 3400,
        bestSquatKg: 110,
        bestBenchKg: 80,
        bestDeadliftKg: 150,
      ),
    );

    await repo.clearRankingMetrics('u1');

    final result = await repo.get('u1');
    expect(result, isNotNull);
    expect(result!.rankingOptIn, isFalse);
    expect(result.lifetimeVolumeKg, equals(0));
    expect(result.bestSquatKg, isNull);
    expect(result.bestBenchKg, isNull);
    expect(result.bestDeadliftKg, isNull);
    // Identity fields untouched
    expect(result.displayName, equals('Ana'));
    expect(result.gymId, equals('g1'));
  });

  // ──────────────────────────────────────────────────────────────────────────
  // QA-GYM-506: leaderboard drops athletes with NO value on the metric.
  //
  // `orderBy` only skips documents where the field is ABSENT — an explicit
  // `null` (what clearRankingMetrics and the opt-in backfill write for a lift
  // the athlete never performed) still matches and sorts to the tail of the
  // board, where the client rendered it as a fabricated "0 kg".
  // ──────────────────────────────────────────────────────────────────────────
  group('QA-GYM-506: leaderboard null-metric exclusion', () {
    Future<void> seed(
      String uid, {
      required String displayName,
      num? bestSquatKg,
      int? racha,
    }) =>
        firestore.collection('userPublicProfiles').doc(uid).set({
          'uid': uid,
          'displayName': displayName,
          'gymId': 'g1',
          'rankingOptIn': true,
          'lifetimeVolumeKg': 0,
          'racha': racha,
          'bestSquatKg': bestSquatKg,
          'bestBenchKg': null,
          'bestDeadliftKg': null,
        });

    test(
        'an opted-in athlete with bestSquatKg == null is excluded instead of '
        'ranking as 0 kg', () async {
      await seed('u1', displayName: 'Ana', bestSquatKg: 120);
      await seed('u2', displayName: 'Lu', bestSquatKg: 100);
      await seed('u3', displayName: 'Coti'); // nunca registró sentadilla
      await seed('u4', displayName: 'Nico');
      await seed('u5', displayName: 'Sofi');

      final result =
          await repo.leaderboard(gymId: 'g1', metricField: 'bestSquatKg');

      expect(result.map((p) => p.uid), equals(['u1', 'u2']));
    });

    test(
        'a gym where nobody registered the lift yields an EMPTY leaderboard, '
        'not a podium of zeros', () async {
      await seed('u1', displayName: 'Ana');
      await seed('u2', displayName: 'Lu');

      final result =
          await repo.leaderboard(gymId: 'g1', metricField: 'bestSquatKg');

      expect(result, isEmpty);
    });

    test('the same exclusion applies to bench and deadlift', () async {
      await seed('u1', displayName: 'Ana');

      expect(
        await repo.leaderboard(gymId: 'g1', metricField: 'bestBenchKg'),
        isEmpty,
      );
      expect(
        await repo.leaderboard(gymId: 'g1', metricField: 'bestDeadliftKg'),
        isEmpty,
      );
    });

    test(
        'racha keeps its 0 floor — no streak IS a 0-day streak, unlike a lift '
        'never performed', () async {
      await seed('u1', displayName: 'Ana', racha: 5);
      await seed('u2', displayName: 'Lu');

      final result = await repo.leaderboard(gymId: 'g1', metricField: 'racha');

      expect(result.map((p) => p.uid), containsAll(['u1', 'u2']));
    });
  });

  // ─── hiddenFromDiscovery: cuentas internas fuera de los listados ──────────
  group('hiddenFromDiscovery', () {
    // Matchea las DOS consultas de la búsqueda: prefijo de
    // `displayNameLowercase` y `searchPrefixes`.
    Future<void> seedPersona(String uid, String name, [Object? hidden]) =>
        firestore.collection('userPublicProfiles').doc(uid).set({
          'uid': uid,
          'displayName': name,
          'displayNameLowercase': name.toLowerCase(),
          'searchPrefixes': ['tr', 'tre', 'trei', 'trein', 'treino'],
          'gymId': 'g1',
          'rankingOptIn': true,
          'lifetimeVolumeKg': 1000,
          'rachaSemanas': 3,
          if (hidden != null) 'hiddenFromDiscovery': hidden,
        });

    test('la búsqueda no devuelve la cuenta oculta y sí la visible', () async {
      await seedPersona('soporte', 'treinoSupport', true);
      await seedPersona('visible', 'treinoFan');

      final uids =
          (await repo.searchByDisplayName('treino')).map((p) => p.uid).toList();

      expect(uids, ['visible']);
    });

    test('ausente, false o un valor roto cuentan como visible', () async {
      await seedPersona('ausente', 'treinoA');
      await seedPersona('falso', 'treinoB', false);
      await seedPersona('roto', 'treinoC', 'si');

      final uids =
          (await repo.searchByDisplayName('treino')).map((p) => p.uid).toSet();

      expect(uids, {'ausente', 'falso', 'roto'});
    });

    test('los rankings no muestran la cuenta oculta (volumen y racha)',
        () async {
      await seedPersona('soporte', 'treinoSupport', true);
      await seedPersona('visible', 'treinoFan');

      final volumen =
          await repo.leaderboard(gymId: 'g1', metricField: 'lifetimeVolumeKg');
      final racha =
          await repo.leaderboard(gymId: 'g1', metricField: 'rachaSemanas');

      expect(volumen.map((p) => p.uid), ['visible']);
      expect(racha.map((p) => p.uid), ['visible']);
    });

    test('abrir el perfil por uid sigue andando', () async {
      await seedPersona('soporte', 'treinoSupport', true);

      final perfil = await repo.get('soporte');

      expect(perfil?.hiddenFromDiscovery, isTrue);
    });

    test('el cliente nunca escribe el campo (no viaja en toJson)', () {
      const perfil = UserPublicProfile(uid: 'u', hiddenFromDiscovery: true);

      expect(perfil.toJson().containsKey('hiddenFromDiscovery'), isFalse);
    });
  });

  // [#1698] `firestore.rules` acota la `rachaSemanas` que el dueño puede
  // escribir (lo guardado + una semana por semana ART desde el sello). El
  // cliente recorta su valor al mismo techo para que, cuando el cálculo en vivo
  // lo supera (objetivo semanal que baja, sesiones del reloj sin `finish`), la
  // racha converja en vez de rebotar y decaer a 0 en el board.
  group('#1698: updateCounters recorta la racha al techo de las reglas', () {
    // Viernes 2026-07-24 12:00 ART. Su lunes es el 2026-07-20.
    final ahora = DateTime.utc(2026, 7, 24, 15);
    DateTime artNoon(int y, int m, int d) => DateTime.utc(y, m, d, 15);

    late UserPublicProfileRepository repoConReloj;

    setUp(() {
      repoConReloj =
          UserPublicProfileRepository(firestore: firestore, now: () => ahora);
    });

    Future<void> sembrar({int? racha, DateTime? sello}) {
      return firestore.collection('userPublicProfiles').doc('u1').set({
        'uid': 'u1',
        'displayName': 'Ana',
        if (racha != null) 'rachaSemanas': racha,
        if (sello != null) 'rachaSemanasUpdatedAt': Timestamp.fromDate(sello),
      });
    }

    Future<Map<String, Object?>> leer() async =>
        (await firestore.collection('userPublicProfiles').doc('u1').get())
            .data()!;

    test('racha que continúa (+1 sobre la semana pasada): se escribe tal cual',
        () async {
      await sembrar(racha: 3, sello: artNoon(2026, 7, 15));

      await repoConReloj
          .updateCounters('u1', {'workoutsCount': 20, 'rachaSemanas': 4});

      final doc = await leer();
      expect(doc['rachaSemanas'], 4);
      expect(doc['workoutsCount'], 20);
      expect(doc['rachaSemanasUpdatedAt'], isA<Timestamp>());
    });

    test(
        'un valor por encima del techo se recorta, y el resto de los '
        'contadores igual se escriben', () async {
      await sembrar(racha: 3, sello: artNoon(2026, 7, 15));

      await repoConReloj
          .updateCounters('u1', {'workoutsCount': 20, 'rachaSemanas': 9});

      final doc = await leer();
      expect(doc['rachaSemanas'], 4,
          reason: 'lo guardado (3) + 1 semana desde el sello');
      expect(doc['workoutsCount'], 20);
    });

    test('otra sesión la misma semana: el techo es lo guardado', () async {
      await sembrar(racha: 3, sello: artNoon(2026, 7, 22));

      await repoConReloj.updateCounters('u1', {'rachaSemanas': 5});

      expect((await leer())['rachaSemanas'], 3);
    });

    test('escrituras perdidas: suma una semana por semana transcurrida',
        () async {
      await sembrar(racha: 5, sello: artNoon(2026, 7, 1));

      await repoConReloj.updateCounters('u1', {'rachaSemanas': 8});

      expect((await leer())['rachaSemanas'], 8);
    });

    test('racha cortada: bajar no se recorta', () async {
      await sembrar(racha: 7, sello: artNoon(2026, 6, 20));

      await repoConReloj.updateCounters('u1', {'rachaSemanas': 1});

      expect((await leer())['rachaSemanas'], 1);
    });

    test(
        'doc sin racha ni sello (sembrado en 0, o recién creado): primera '
        'racha de 1', () async {
      await sembrar();

      await repoConReloj.updateCounters('u1', {'rachaSemanas': 6});

      expect((await leer())['rachaSemanas'], 1);
    });

    test('sin `rachaSemanas` en el payload no hay lectura ni sello', () async {
      await sembrar(racha: 3, sello: artNoon(2026, 7, 15));

      await repoConReloj.updateCounters('u1', {'workoutsCount': 21});

      final doc = await leer();
      expect(doc['workoutsCount'], 21);
      expect(doc['rachaSemanas'], 3);
      expect(
        (doc['rachaSemanasUpdatedAt'] as Timestamp).toDate().toUtc(),
        artNoon(2026, 7, 15),
        reason: 'el sello no se toca si la racha no se escribe',
      );
    });
  });

  group('#1698: si las reglas rechazan la racha, workoutsCount sigue', () {
    late _MockFirestore mockFirestore;
    late _MockCollection mockCol;
    late _MockDoc mockDoc;
    late List<Map<String, Object?>> writes;

    setUpAll(() => registerFallbackValue(SetOptions(merge: true)));

    setUp(() {
      mockFirestore = _MockFirestore();
      mockCol = _MockCollection();
      mockDoc = _MockDoc();
      writes = [];
      when(() => mockFirestore.collection('userPublicProfiles'))
          .thenReturn(mockCol);
      when(() => mockCol.doc('u1')).thenReturn(mockDoc);
      // Sin lectura posible (sin red ni caché) no hay techo que aplicar: el
      // cliente manda lo que calculó y deciden las reglas.
      when(() => mockDoc.get()).thenThrow(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      );
      when(() => mockDoc.set(any(), any())).thenAnswer((inv) async {
        final data = inv.positionalArguments.first as Map<String, Object?>;
        // Lo que hacen las reglas con una racha por encima del techo.
        if (data.containsKey('rachaSemanas')) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          );
        }
        writes.add(data);
      });
    });

    test('permission-denied en la racha: se reescribe SIN ella', () async {
      final repo = UserPublicProfileRepository(firestore: mockFirestore);

      await repo.updateCounters('u1', {'workoutsCount': 20, 'rachaSemanas': 9});

      expect(writes, [
        {'workoutsCount': 20},
      ]);
    });

    test('permission-denied y nada más que la racha: no hay segundo write',
        () async {
      final repo = UserPublicProfileRepository(firestore: mockFirestore);

      await repo.updateCounters('u1', {'rachaSemanas': 9});

      expect(writes, isEmpty);
    });

    test('un error que NO es permission-denied sigue propagándose', () async {
      when(() => mockDoc.set(any(), any())).thenThrow(
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      );
      final repo = UserPublicProfileRepository(firestore: mockFirestore);

      expect(
        () => repo.updateCounters('u1', {'rachaSemanas': 2}),
        throwsA(isA<FirebaseException>()),
      );
    });
  });
}

class _MockFirestore extends Mock implements FirebaseFirestore {}

class _MockCollection extends Mock
    implements CollectionReference<Map<String, Object?>> {}

class _MockDoc extends Mock
    implements DocumentReference<Map<String, Object?>> {}
