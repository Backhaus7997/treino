// WU-04 (Fase 2) — Columna izquierda: Pendientes de HOY (solicitudes).
//
// RED → GREEN: cubre el contrato de extracción a
// dashboard/widgets/dashboard_pending.dart. ADR-D2-01: NO se agrega el feed
// rico del mockup (mensajes/fotos/dolor) — data inventada. Se rediseña SOLO
// la data REAL: solicitudes pendientes vía trainerLinksStreamProvider.
//
// SCENARIO-PEND-01: loading → columna de TreinoListRow skeleton (shimmer).
// SCENARIO-PEND-02: data vacía → TreinoEmptyState.
// SCENARIO-PEND-03: data con N pendientes → N tiles con keys preservadas +
//   count en el TreinoSectionHeader.
// SCENARIO-PEND-04: error → _SectionError con retry.
// SCENARIO-PEND-05: accept/decline siguen llamando al repo real (regresión).
import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/trainer_link_repository.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/widgets/dashboard_pending.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

import '../../../../../../helpers/fake_analytics_service.dart';

// ─── Factories ────────────────────────────────────────────────────────────────

TrainerLink _link({
  required String id,
  String athleteId = 'a1',
}) =>
    TrainerLink(
      id: id,
      trainerId: 'trainer-1',
      athleteId: athleteId,
      status: TrainerLinkStatus.pending,
      requestedAt: DateTime.utc(2026, 1, 10),
    );

UserPublicProfile _pub(String uid, String name) => UserPublicProfile(
      uid: uid,
      displayName: name,
      displayNameLowercase: name.toLowerCase(),
    );

// ─── Test helpers ─────────────────────────────────────────────────────────────

Future<void> _pump(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(body: DashboardPendingSection()),
      ),
    ),
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('SCENARIO-PEND-01 — loading usa el skeleton del kit', () {
    testWidgets('trainerLinksStreamProvider loading → TreinoListRow skeleton',
        (tester) async {
      final controller = StreamController<List<TrainerLink>>();
      addTearDown(controller.close);

      await _pump(
        tester,
        overrides: [
          trainerLinksStreamProvider.overrideWith((ref) => controller.stream),
        ],
      );
      await tester.pump();

      expect(find.byKey(const Key('list_row_skeleton')), findsWidgets);
    });
  });

  group('SCENARIO-PEND-02 — data vacía usa TreinoEmptyState', () {
    testWidgets('sin pending → empty state (nunca hidden)', (tester) async {
      await _pump(
        tester,
        overrides: [
          trainerLinksStreamProvider.overrideWith(
            (ref) => Stream.value(const <TrainerLink>[]),
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('empty_state_content')), findsOneWidget);
    });
  });

  group('SCENARIO-PEND-03 — N pendientes preservan keys + count', () {
    testWidgets(
        '2 pending → 2 tiles con keys accept_/decline_/pending_request_',
        (tester) async {
      final links = [
        _link(id: 'r1', athleteId: 'a1'),
        _link(id: 'r2', athleteId: 'a2'),
      ];
      await _pump(
        tester,
        overrides: [
          trainerLinksStreamProvider.overrideWith(
            (ref) => Stream.value(links),
          ),
          userPublicProfileProvider('a1').overrideWith(
            (ref) => Stream.value(_pub('a1', 'Ana')),
          ),
          userPublicProfileProvider('a2').overrideWith(
            (ref) => Stream.value(_pub('a2', 'Beto')),
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pending_request_r1')), findsOneWidget);
      expect(find.byKey(const Key('pending_request_r2')), findsOneWidget);
      expect(find.byKey(const Key('accept_r1')), findsOneWidget);
      expect(find.byKey(const Key('decline_r1')), findsOneWidget);
      expect(find.byKey(const Key('accept_r2')), findsOneWidget);
      expect(find.byKey(const Key('decline_r2')), findsOneWidget);
      // Header count = pending.length.
      expect(find.text('2'), findsOneWidget);
    });
  });

  group('SCENARIO-PEND-04 — error muestra retry', () {
    testWidgets('stream error → mensaje + botón reintentar', (tester) async {
      await _pump(
        tester,
        overrides: [
          trainerLinksStreamProvider.overrideWith(
            (ref) => Stream<List<TrainerLink>>.error(Exception('boom')),
          ),
        ],
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextButton), findsOneWidget);
    });
  });

  group('SCENARIO-PEND-05 — accept/decline llaman al repo real', () {
    late FakeFirebaseFirestore firestore;
    late TrainerLinkRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = TrainerLinkRepository(firestore: firestore);
    });

    Future<List<Override>> repoOverrides(String athleteId) async => [
          firestoreProvider.overrideWithValue(firestore),
          currentUidProvider.overrideWithValue('trainer-1'),
          analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
          userPublicProfileProvider(athleteId).overrideWith(
            (ref) => Stream.value(_pub(athleteId, 'Ana')),
          ),
        ];

    testWidgets('tap accept_ transiciona pending → active en Firestore',
        (tester) async {
      final link = await repo.request(
        trainerId: 'trainer-1',
        athleteId: 'a1',
      );

      await _pump(
        tester,
        overrides: await repoOverrides('a1'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('accept_${link.id}')));
      await tester.pumpAndSettle();

      final snap =
          await firestore.collection('trainer_links').doc(link.id).get();
      expect(snap.data()!['status'], 'active');
    });

    testWidgets('tap decline_ transiciona pending → terminated en Firestore',
        (tester) async {
      final link = await repo.request(
        trainerId: 'trainer-1',
        athleteId: 'a1',
      );

      await _pump(
        tester,
        overrides: await repoOverrides('a1'),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('decline_${link.id}')));
      await tester.pumpAndSettle();

      final snap =
          await firestore.collection('trainer_links').doc(link.id).get();
      expect(snap.data()!['status'], 'terminated');
    });
  });
}
