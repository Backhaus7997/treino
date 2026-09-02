import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/argentina_time.dart';
import 'package:treino/features/profile/application/profile_stats_providers.dart';
import 'package:treino/features/profile/data/user_public_profile_repository.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';

// [#552, migrado a semanas] Paridad de la racha: PERFIL (fila de stats,
// userSessionStatsProvider → computeWeeklyStreak en vivo) y RANKINGS → RACHAS
// (leaderboard sobre el campo denormalizado `rachaSemanas` de
// userPublicProfiles) deben mostrar EL MISMO número para el mismo usuario en
// el mismo instante.
//
// Antes del fix, el campo denormalizado era un snapshot del último finish()
// que nunca decaía: un atleta que dejaba de entrenar quedaba en el board con
// su última racha para siempre (RANKINGS: 1) mientras su propio perfil,
// calculado en vivo, decía 0. Mismo patrón de dos-fuentes-sin-convergencia
// que #442.
//
// Decisión semántica (#552): "racha" significa SIEMPRE la racha actual hasta
// hoy en frame ART. El board decae el valor guardado en lectura usando el
// stamp `rachaSemanasUpdatedAt` que updateCounters deriva junto a cada
// escritura de `rachaSemanas`. Desde la migración la unidad es la SEMANA y la
// ventana de gracia del decay es {semana en curso, semana anterior}.
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

/// Mediodía ART del LUNES de hace [weeksAgo] semanas.
///
/// La racha se cuenta por semanas, así que los fixtures se anclan al borde de
/// semana y no a "hace N días": con días, el mismo fixture da un número
/// distinto según el día en que corra la suite (si hoy es lunes, "ayer" ya es
/// la semana pasada).
DateTime _artNoonWeeksAgo(int weeksAgo) {
  final monday = mondayOfWeekArt(toArgentina(DateTime.now().toUtc()));
  return DateTime.utc(
    monday.year,
    monday.month,
    monday.day - (7 * weeksAgo),
    15,
  );
}

Future<void> _seedPublicProfile(
  FakeFirebaseFirestore firestore,
  String uid, {
  int? rachaSemanas,
  Timestamp? rachaSemanasUpdatedAt,
}) {
  return firestore.collection('userPublicProfiles').doc(uid).set({
    'uid': uid,
    'displayName': uid,
    'displayNameLowercase': uid,
    'gymId': 'g1',
    'rankingOptIn': true,
    if (rachaSemanas != null) 'rachaSemanas': rachaSemanas,
    if (rachaSemanasUpdatedAt != null)
      'rachaSemanasUpdatedAt': rachaSemanasUpdatedAt,
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

  Future<void> trainOn({required int weeksAgo, double volumeKg = 100}) async {
    final startedAt = _artNoonWeeksAgo(weeksAgo);
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
      metricField: 'rachaSemanas',
    );
    for (final p in board) {
      if (p.uid == uid) return p.rachaSemanas;
    }
    return null;
  }

  test(
      '#552 parity: racha viva (cumplió esta semana y la pasada) — PERFIL y '
      'RANKINGS muestran el mismo valor', () async {
    await _seedPublicProfile(firestore, 'u1');
    await trainOn(weeksAgo: 1);
    await trainOn(weeksAgo: 0);

    final perfil = await profileRacha();
    final rankings = await boardRachaOf('u1');

    expect(perfil, 2);
    expect(rankings, perfil,
        reason: 'la misma racha debe verse igual en ambas pantallas');
  });

  test(
      '#552 parity: updateCounters deriva rachaSemanasUpdatedAt junto con '
      'rachaSemanas — el caller (finish) no lo pasa', () async {
    await _seedPublicProfile(firestore, 'u1');
    await trainOn(weeksAgo: 0);

    final doc =
        await firestore.collection('userPublicProfiles').doc('u1').get();
    expect(doc.data()!['rachaSemanas'], 1);
    expect(doc.data()!['rachaSemanasUpdatedAt'], isA<Timestamp>(),
        reason: 'el stamp de frescura viaja SIEMPRE en el mismo write que '
            'rachaSemanas, derivado por el repositorio');
  });

  test(
      '#552 regresión: racha cortada (último entreno hace 3 semanas) — el '
      'board decae el snapshot viejo a 0, igual que el perfil en vivo',
      () async {
    // Estado prod del bug: el finish() de hace 3 semanas dejó rachaSemanas:1
    // con stamp de ese día; desde entonces el atleta no entrenó. Se fabrica el
    // doc tal como quedó (el flow real corrido HOY se auto-sanaría con 0).
    await _seedPublicProfile(
      firestore,
      'u1',
      rachaSemanas: 1,
      rachaSemanasUpdatedAt: Timestamp.fromDate(_artNoonWeeksAgo(3)),
    );
    await sessionRepo.create(
      uid: 'u1',
      routineId: 'r1',
      routineName: 'Rutina',
      startedAt: _artNoonWeeksAgo(3),
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
        _artNoonWeeksAgo(3).add(const Duration(hours: 1)),
      ),
      'wasFullyCompleted': true,
      'totalVolumeKg': 100.0,
    });

    final perfil = await profileRacha();
    final rankings = await boardRachaOf('u1');

    expect(perfil, 0,
        reason: 'racha cortada: la semana en curso y la anterior sin cumplir');
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
      rachaSemanas: 2,
      rachaSemanasUpdatedAt: Timestamp.fromDate(_artNoonWeeksAgo(0)),
    );
    await _seedPublicProfile(
      firestore,
      'u2',
      rachaSemanas: 5,
      rachaSemanasUpdatedAt: Timestamp.fromDate(_artNoonWeeksAgo(10)),
    );

    final board = await publicRepo.leaderboard(
      gymId: 'g1',
      metricField: 'rachaSemanas',
    );

    expect(board.map((p) => p.uid).toList(), ['u1', 'u2'],
        reason: 'el valor guardado 5 está muerto — decae a 0 y baja');
    expect(board.first.rachaSemanas, 2);
    expect(board.last.rachaSemanas, 0);
  });

  test('doc de la era en DÍAS: el board muestra 0, NO el valor viejo',
      () async {
    // Este test invirtió su expectativa con la migración a semanas, y es el
    // punto entero del campo nuevo.
    //
    // Antes: un doc sin stamp hacía passthrough del valor crudo. Con la
    // migración, un doc que sólo tiene el `racha` legacy guarda DÍAS: dejarlo
    // pasar mostraría "23 semanas" donde corresponde "3" — un número inflado
    // en un board PÚBLICO, que es exactamente la advertencia falsa del §11.1
    // de AGENTS.md. Sin `rachaSemanas` ni su stamp, el valor honesto es 0, y
    // se corrige solo en el próximo finish() del atleta.
    await firestore.collection('userPublicProfiles').doc('u1').set({
      'uid': 'u1',
      'displayName': 'u1',
      'displayNameLowercase': 'u1',
      'gymId': 'g1',
      'rankingOptIn': true,
      'racha': 23, // legacy, en días
      'rachaUpdatedAt': Timestamp.fromDate(_artNoonDaysAgo(0)),
    });

    final rankings = await boardRachaOf('u1');

    expect(rankings, 0,
        reason: 'el 23 son DÍAS; mostrarlo como semanas sería mentir');
  });
}
