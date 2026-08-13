import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/follow_up_entry_providers.dart';
import 'package:treino/features/coach/domain/follow_up_entry.dart';
import 'package:treino/features/coach/presentation/athlete_detail_screen.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

// The follow-up log could be WRITTEN from mobile (the dashboard's "Dejar
// feedback" sheet) but only READ in the Coach Hub (web): the trainer left a
// note on their phone and it vanished from their view. The SEGUIMIENTO section
// in the mobile athlete detail closes that asymmetry. Read-only — creating
// stays in the dashboard sheet, editing/deleting stays in the web hub.

const _kTrainer = 'trainer-1';
const _kAthlete = 'athlete-1';

UserPublicProfile _profile() =>
    const UserPublicProfile(uid: _kAthlete, displayName: 'Martín García');

FollowUpEntry _entry({
  required String id,
  required String text,
  required FollowUpTag tag,
  required DateTime at,
}) =>
    FollowUpEntry(
      id: id,
      trainerId: _kTrainer,
      athleteId: _kAthlete,
      text: text,
      tag: tag,
      recordedAt: at,
    );

Future<void> _pumpScreen(
  WidgetTester tester, {
  required List<Override> extraOverrides,
}) async {
  final router = GoRouter(
    initialLocation: '/coach/athlete/$_kAthlete',
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            Scaffold(body: child, bottomNavigationBar: const SizedBox()),
        routes: [
          GoRoute(
            path: '/coach/athlete/:athleteId',
            builder: (context, state) => AthleteDetailScreen(
              athleteId: state.pathParameters['athleteId']!,
            ),
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue(_kTrainer),
        userPublicProfileProvider(_kAthlete)
            .overrideWith((ref) => Stream.value(_profile())),
        assignedRoutinesProvider(_kAthlete)
            .overrideWith((ref) async => const []),
        ...extraOverrides,
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// The section sits near the bottom of a long ListView, so every assertion
/// has to scroll it into view first.
Future<void> _scrollToSeguimiento(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('SEGUIMIENTO'),
    300,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 60,
  );
  await tester.pump();
}

Override _entriesOverride(Stream<List<FollowUpEntry>> stream) =>
    followUpEntriesProvider((trainerId: _kTrainer, athleteId: _kAthlete))
        .overrideWith((ref) => stream);

void main() {
  group('AthleteDetailScreen — SEGUIMIENTO', () {
    testWidgets('renders the entries newest-first with their tag and date',
        (tester) async {
      await _pumpScreen(tester, extraOverrides: [
        _entriesOverride(Stream.value([
          _entry(
            id: 'e1',
            text: 'Buen trabajo hoy, subiste el peso en banca',
            tag: FollowUpTag.entrenamiento,
            at: DateTime(2026, 7, 28),
          ),
          _entry(
            id: 'e2',
            text: 'Reportó molestia lumbar leve',
            tag: FollowUpTag.molestia,
            at: DateTime(2026, 7, 21),
          ),
        ])),
      ]);
      await _scrollToSeguimiento(tester);

      expect(find.text('Buen trabajo hoy, subiste el peso en banca'),
          findsOneWidget);
      expect(find.text('Reportó molestia lumbar leve'), findsOneWidget);
      // Tag chips use the SAME labels as the web hub, so an entry does not
      // change identity depending on where it is read.
      expect(find.text('ENTRENAMIENTO'), findsOneWidget);
      expect(find.text('MOLESTIA'), findsOneWidget);
      expect(find.text('28/07'), findsOneWidget);
      expect(find.text('21/07'), findsOneWidget);
    });

    testWidgets('no entries → empty state, no rows', (tester) async {
      await _pumpScreen(tester, extraOverrides: [
        _entriesOverride(Stream.value(const <FollowUpEntry>[])),
      ]);
      await _scrollToSeguimiento(tester);

      expect(
        find.text('Todavía no dejaste seguimiento de este alumno.'),
        findsOneWidget,
      );
      expect(find.text('ENTRENAMIENTO'), findsNothing);
    });

    testWidgets('a failing query degrades to an inline error, not a crash',
        (tester) async {
      await _pumpScreen(tester, extraOverrides: [
        _entriesOverride(
          Stream<List<FollowUpEntry>>.error(Exception('permission-denied')),
        ),
      ]);
      await _scrollToSeguimiento(tester);

      expect(find.text('No pudimos cargar el seguimiento.'), findsOneWidget);
      // #503 contract: one section failing must NOT take the screen down —
      // the athlete header is still there.
      expect(find.text('Martín García'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('caps the mobile view at 10 entries — the full log is on web',
        (tester) async {
      await _pumpScreen(tester, extraOverrides: [
        _entriesOverride(Stream.value([
          for (var i = 0; i < 14; i++)
            _entry(
              id: 'e$i',
              text: 'Entrada $i',
              tag: FollowUpTag.general,
              at: DateTime(2026, 7, 28).subtract(Duration(days: i)),
            ),
        ])),
      ]);
      await _scrollToSeguimiento(tester);

      expect(find.text('Entrada 0'), findsOneWidget);
      expect(find.text('Entrada 9'), findsOneWidget);
      expect(find.text('Entrada 10'), findsNothing);
      expect(find.text('Entrada 13'), findsNothing);
    });
  });
}
