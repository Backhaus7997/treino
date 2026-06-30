import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/coach_hub/presentation/sections/agenda/agenda_web_screen.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

// ─── Constants ───────────────────────────────────────────────────────────────

const _kTrainerId = 'trainer-uid-1';
const _kAthleteId = 'athlete-uid-abc';

// ─── Factories ───────────────────────────────────────────────────────────────

/// Tomorrow UTC — used so confirmed appointments appear as dots (not past).
DateTime _tomorrow() {
  final now = DateTime.now().toUtc();
  return DateTime.utc(now.year, now.month, now.day + 1, 9, 0);
}

Appointment _appt({
  String id = 'appt-1',
  String athleteId = _kAthleteId,
  AppointmentStatus status = AppointmentStatus.confirmed,
  DateTime? startsAt,
  int durationMin = 60,
}) =>
    Appointment(
      id: id,
      trainerId: _kTrainerId,
      athleteId: athleteId,
      athleteDisplayName: 'Atleta Prueba',
      startsAt: startsAt ?? _tomorrow(),
      durationMin: durationMin,
      status: status,
    );

UserPublicProfile _pub(String uid, String name) => UserPublicProfile(
      uid: uid,
      displayName: name,
      displayNameLowercase: name.toLowerCase(),
    );

// ─── Test wrap helper ─────────────────────────────────────────────────────────

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

// ─── Shared override builders ─────────────────────────────────────────────────

List<Override> _overrides({
  List<Appointment> appointments = const [],
  Map<String, UserPublicProfile> profiles = const {},
}) {
  return [
    currentUidProvider.overrideWithValue(_kTrainerId),
    // Override the appointments stream for any TrainerAppointmentsKey
    trainerAppointmentsStreamProvider.overrideWith(
      (ref, key) => Stream.value(appointments),
    ),
    // Override public profile for each athlete in profiles map
    for (final entry in profiles.entries)
      userPublicProfileProvider(entry.key).overrideWith(
        (ref) => Stream.value(entry.value),
      ),
  ];
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    // Register fallback values for Riverpod family providers used in tests
  });

  // ── SCENARIO-101-A: Calendar loads with appointments ──────────────────────

  group('SCENARIO-101-A — Calendar renders in month view with appointment dots',
      () {
    testWidgets('TableCalendar is present and in month view by default',
        (tester) async {
      final appt = _appt();
      final profiles = {_kAthleteId: _pub(_kAthleteId, 'Atleta Prueba')};

      await tester.pumpWidget(
        _wrap(
          const AgendaWebScreen(),
          overrides: _overrides(appointments: [appt], profiles: profiles),
        ),
      );
      await tester.pumpAndSettle();

      // TableCalendar widget must exist
      expect(find.byType(TableCalendar<dynamic>), findsOneWidget);

      // The format button shows "Semana" when in month view (toggle to week).
      // table_calendar shows the NEXT format label in the button.
      expect(find.text('Semana'), findsOneWidget); // i18n
    });
  });

  // ── SCENARIO-101-B: Month toggle ──────────────────────────────────────────

  group('SCENARIO-101-B — Month toggle switches calendar view', () {
    testWidgets('tapping Semana toggles to week view', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AgendaWebScreen(),
          overrides: _overrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Before tap: shows "Semana" button (month view default, next = week)
      expect(find.text('Semana'), findsOneWidget); // i18n

      await tester.tap(find.text('Semana'));
      await tester.pumpAndSettle();

      // After tap: shows "Mes" button (week view, next = month)
      expect(find.text('Mes'), findsOneWidget); // i18n
    });
  });

  // ── SCENARIO-101-C: Trainer with no appointments ──────────────────────────

  group('SCENARIO-101-C — No appointments → empty state in day list', () {
    testWidgets('shows empty day list copy when trainer has zero appointments',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AgendaWebScreen(),
          overrides: _overrides(appointments: []),
        ),
      );
      await tester.pumpAndSettle();

      // Should show the empty state message for selected day
      expect(
        find.text('No hay sesiones este día.'), // i18n
        findsOneWidget,
      );
    });
  });

  // ── SCENARIO-102-A: Day list cards ───────────────────────────────────────

  group('SCENARIO-102-A — Day with appointments shows cards', () {
    testWidgets('appointment card shows time + athlete name + duration',
        (tester) async {
      // Use today so the selected day (default = today) matches
      final now = DateTime.now().toUtc();
      final today = DateTime.utc(now.year, now.month, now.day, 10, 30);
      final appt = _appt(startsAt: today, durationMin: 45);
      final profiles = {_kAthleteId: _pub(_kAthleteId, 'Juan García')};

      await tester.pumpWidget(
        _wrap(
          const AgendaWebScreen(),
          overrides: _overrides(appointments: [appt], profiles: profiles),
        ),
      );
      await tester.pumpAndSettle();

      // Time in HH:mm format
      expect(find.text('10:30'), findsOneWidget);
      // Athlete name
      expect(find.text('Juan García'), findsOneWidget);
      // Duration label
      expect(find.text('45 min'), findsOneWidget); // i18n
    });
  });

  // ── SCENARIO-102-A: isRawUid fallback ────────────────────────────────────

  group('SCENARIO-102-A — UID fallback name', () {
    testWidgets('raw uid athlete shows Alumno fallback', (tester) async {
      final now = DateTime.now().toUtc();
      final today = DateTime.utc(now.year, now.month, now.day, 9, 0);
      // athleteDisplayName looks like a raw UID
      final appt = Appointment(
        id: 'appt-uid-test',
        trainerId: _kTrainerId,
        athleteId: 'aB1cD2eF3gH4iJ5kL6mN',
        athleteDisplayName: 'aB1cD2eF3gH4iJ5kL6mN',
        startsAt: today,
        durationMin: 60,
        status: AppointmentStatus.confirmed,
      );

      await tester.pumpWidget(
        _wrap(
          const AgendaWebScreen(),
          overrides: [
            currentUidProvider.overrideWithValue(_kTrainerId),
            trainerAppointmentsStreamProvider.overrideWith(
              (ref, key) => Stream.value([appt]),
            ),
            // profile returns null (no display name resolved)
            userPublicProfileProvider('aB1cD2eF3gH4iJ5kL6mN').overrideWith(
              (ref) => Stream.value(null),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Alumno'), findsOneWidget);
    });
  });

  // ── SCENARIO-102-B: Empty state for selected day ──────────────────────────

  group('SCENARIO-102-B — Day with no appointments shows empty state', () {
    testWidgets('empty state text visible when no appointments on selected day',
        (tester) async {
      // Appointment is tomorrow; selected day is today → empty
      final appt = _appt(startsAt: _tomorrow());
      final profiles = {_kAthleteId: _pub(_kAthleteId, 'Atleta')};

      await tester.pumpWidget(
        _wrap(
          const AgendaWebScreen(),
          overrides: _overrides(appointments: [appt], profiles: profiles),
        ),
      );
      await tester.pumpAndSettle();

      // Today is selected by default; tomorrow's appointment should NOT show
      // and the empty state should be present
      expect(find.text('No hay sesiones este día.'), findsOneWidget); // i18n
    });
  });

  // ── SCENARIO-103-A: Detail dialog opens on card tap ───────────────────────

  group('SCENARIO-103-A — Tap card opens AlertDialog detail', () {
    testWidgets('tapping appointment card opens AlertDialog', (tester) async {
      final now = DateTime.now().toUtc();
      final today = DateTime.utc(now.year, now.month, now.day, 15, 0);
      final appt = _appt(startsAt: today, durationMin: 60);
      final profiles = {_kAthleteId: _pub(_kAthleteId, 'María López')};

      await tester.pumpWidget(
        _wrap(
          const AgendaWebScreen(),
          overrides: _overrides(appointments: [appt], profiles: profiles),
        ),
      );
      await tester.pumpAndSettle();

      // Tap the appointment card
      await tester.tap(find.text('María López').first);
      await tester.pumpAndSettle();

      // AlertDialog should appear
      expect(find.byType(AlertDialog), findsOneWidget);

      // Detail shows time range label  e.g. "15:00 – 16:00 · 60 min"
      expect(find.textContaining('15:00'), findsWidgets);
      expect(find.textContaining('16:00'), findsWidgets);

      // GUARDAR NOTAS button present in dialog
      expect(find.text('GUARDAR NOTAS'), findsOneWidget); // i18n
    });
  });

  // ── SCENARIO-103-B: Dismiss dialog ───────────────────────────────────────

  group('SCENARIO-103-B — Dismiss dialog closes it', () {
    testWidgets('tapping Cerrar closes the AlertDialog', (tester) async {
      final now = DateTime.now().toUtc();
      final today = DateTime.utc(now.year, now.month, now.day, 11, 0);
      final appt = _appt(startsAt: today);
      final profiles = {_kAthleteId: _pub(_kAthleteId, 'Carlos Ruiz')};

      await tester.pumpWidget(
        _wrap(
          const AgendaWebScreen(),
          overrides: _overrides(appointments: [appt], profiles: profiles),
        ),
      );
      await tester.pumpAndSettle();

      // Open the dialog
      await tester.tap(find.text('Carlos Ruiz').first);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      // Tap the close/dismiss action
      await tester.tap(find.text('Cerrar')); // i18n
      await tester.pumpAndSettle();

      // Dialog should be gone
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
