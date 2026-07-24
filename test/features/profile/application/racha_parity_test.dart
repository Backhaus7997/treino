import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/argentina_time.dart';
import 'package:treino/features/profile/application/profile_stats_providers.dart';
import 'package:treino/features/profile/data/user_public_profile_repository.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';

// [#552] Paridad de la racha: PERFIL (fila de stats, userSessionStatsProvider
// → computeStreak en vivo) y RANKINGS → RACHAS (leaderboard sobre el campo
// denormalizado `racha` de userPublicProfiles) deben mostrar EL MISMO número
// para el mismo usuario en el mismo instante.
//
// Antes del fix, el campo denormalizado era un snapshot del último finish()
// que nunca decaía: un atleta que dejaba de entrenar quedaba en el board con
// su última racha para siempre (RANKINGS: 1) mientras su propio perfil,
// calculado en vivo, decía 0. Mismo patrón de dos-fuentes-sin-convergencia
// que #442.
//
// Decisión semántica (#552): "racha" significa SIEMPRE la racha actual hasta
// hoy en frame ART. El board ahora decae el valor guardado en lectura usando
// el stamp `rachaUpdatedAt` que updateCounters deriva junto a cada escritura
// de `racha`.
//
// Estilo #442: integración sobre UNA FakeFirebaseFirestore compartida, con
// los repos REALES encadenados (SessionRepository.finish → updateCounters →
// leaderboard), no mocks — la paridad se verifica de punta a punta.

/// Ancla de día ART machine-independiente: 15:00Z == 12:00 ART del mismo día
/// (mismo truco que los fixtures de Insights — mediodía ART esquiva los
/// bordes de medianoche en cualquier TZ de máquina).
DateTime _artNoonDaysAgo(int daysAgo) {
  final art =
      toArgentina(DateTime.now().toUtc()).subtract(Duration(days: daysAgo));
  return DateTime.utc(art.year, art.month, art.day, 15);
}

Future<void> _seedPublicProfile(
  FakeFirebaseFirestore firestore,
  String uid, {
  int? racha,
  Timestamp? rachaUpdatedAt,
}) {
  return firestore.collection('userPublicProfiles').doc(uid).set({
    'uid': uid,
    'displayName': uid,
    'displayNameLowercase': uid,
    'gymId': 'g1',
    'rankingOptIn': true,
    if (racha != null) 'racha': racha,
    if (rachaUpdatedAt != null) 'rachaUpdatedAt': rachaUpdatedAt,
  });
}

void main() {
  late FakeFirebaseFirestore firestore;
  late UserPublicProfileRepository publicRepo;
  late SessionRepository sessionRepo;
  late ProviderContainer container;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    publicRepo = UserPublicProfileRepository(firestore: firestore);
    sessionRepo = SessionRepository(
      firestore: firestore,
      publicProfileRepository: publicRepo,
    );
    container = ProviderContainer(
      overrides: [
        currentUidProvider.overrideWithValue('u1'),
        sessionRepositoryProvider.overrideWithValue(sessionRepo),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<void> trainOn({required int daysAgo, double volumeKg = 100}) async {
    final startedAt = _artNoonDaysAgo(daysAgo);
    final session = await sessionRepo.create(
      uid: 'u1',
      routineId: 'r1',
      routineName: 'Rutina',
      startedAt: startedAt,
    );
    await sessionRepo.finish(
      uid: 'u1',
      sessionId: session.id,
      finishedAt: startedAt.add(const Duration(hours: 1)),
      totalVolumeKg: volumeKg,
      durationMin: 60,
      wasFullyCompleted: true,
    );
  }

  Future<int> profileRacha() async =>
      (await container.read(userSessionStatsProvider.future)).streak;

  Future<int?> boardRachaOf(String uid) async {
    final board = await publicRepo.leaderboard(
      gymId: 'g1',
      metricField: 'racha',
    );
    for (final p in board) {
      if (p.uid == uid) return p.racha;
    }
    return null;
  }

  test(
      '#552 parity: racha viva (entrenó hoy y ayer) — PERFIL y RANKINGS '
      'muestran el mismo valor', () async {
    await _seedPublicProfile(firestore, 'u1');
    await trainOn(daysAgo: 1);
    await trainOn(daysAgo: 0);

    final perfil = await profileRacha();
    final rankings = await boardRachaOf('u1');

    expect(perfil, 2);
    expect(rankings, perfil,
        reason: 'la misma racha debe verse igual en ambas pantallas');
  });

  test(
      '#552 parity: updateCounters deriva rachaUpdatedAt junto con racha — '
      'el caller (finish) no lo pasa', () async {
    await _seedPublicProfile(firestore, 'u1');
    await trainOn(daysAgo: 0);

    final doc =
        await firestore.collection('userPublicProfiles').doc('u1').get();
    expect(doc.data()!['racha'], 1);
    expect(doc.data()!['rachaUpdatedAt'], isA<Timestamp>(),
        reason: 'el stamp de frescura viaja SIEMPRE en el mismo write que '
            'racha, derivado por el repositorio');
  });

  test(
      '#552 regresión: racha cortada (último entreno hace 3 días) — el board '
      'decae el snapshot viejo a 0, igual que el perfil en vivo', () async {
    // Estado prod del bug: el finish() de hace 3 días dejó racha:1 con stamp
    // de ese día; desde entonces el atleta no entrenó. Se fabrica el doc tal
    // como quedó (el flow real corrido HOY se auto-sanaría escribiendo 0).
    await _seedPublicProfile(
      firestore,
      'u1',
      racha: 1,
      rachaUpdatedAt: Timestamp.fromDate(_artNoonDaysAgo(3)),
    );
    await sessionRepo.create(
      uid: 'u1',
      routineId: 'r1',
      routineName: 'Rutina',
      startedAt: _artNoonDaysAgo(3),
    );
    // La sesión existe como finished sin pasar por finish() para no
    // re-estampar el contador con el reloj de hoy.
    final snap = await firestore
        .collection('users')
        .doc('u1')
        .collection('sessions')
        .get();
    await snap.docs.single.reference.update({
      'status': 'finished',
      'finishedAt': Timestamp.fromDate(
        _artNoonDaysAgo(3).add(const Duration(hours: 1)),
      ),
      'wasFullyCompleted': true,
      'totalVolumeKg': 100.0,
    });

    final perfil = await profileRacha();
    final rankings = await boardRachaOf('u1');

    expect(perfil, 0, reason: 'racha cortada: hoy y ayer sin entrenar');
    expect(rankings, 0,
        reason: 'el board ya no puede mostrar el snapshot congelado (era el '
            'bug: PERFIL 0 vs RANKINGS 1)');
    expect(rankings, perfil);
  });

  test(
      '#552 decay reordena el board: racha fresca de 2 le gana a una racha '
      'vieja de 5', () async {
    await _seedPublicProfile(
      firestore,
      'u1',
      racha: 2,
      rachaUpdatedAt: Timestamp.fromDate(_artNoonDaysAgo(0)),
    );
    await _seedPublicProfile(
      firestore,
      'u2',
      racha: 5,
      rachaUpdatedAt: Timestamp.fromDate(_artNoonDaysAgo(10)),
    );

    final board = await publicRepo.leaderboard(
      gymId: 'g1',
      metricField: 'racha',
    );

    expect(board.map((p) => p.uid).toList(), ['u1', 'u2'],
        reason: 'el valor guardado 5 está muerto — decae a 0 y baja');
    expect(board.first.racha, 2);
    expect(board.last.racha, 0);
  });

  test(
      '#552 doc legacy sin stamp: passthrough documentado hasta correr '
      'backfill_racha_freshness.js', () async {
    // Un doc escrito antes de este fix no tiene rachaUpdatedAt: el board no
    // puede juzgar frescura y muestra el valor tal cual (comportamiento
    // pre-#552). La divergencia con el perfil para estos docs se cierra con
    // el backfill (o con el próximo finish() del atleta, que ya estampa).
    await _seedPublicProfile(firestore, 'u1', racha: 1);

    final rankings = await boardRachaOf('u1');

    expect(rankings, 1,
        reason: 'sin stamp no hay decay — passthrough hasta el backfill');
  });
}
