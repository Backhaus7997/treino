import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/data/appointment_repository.dart';
import 'package:treino/features/coach/data/availability_repository.dart';
import 'package:treino/features/coach/domain/availability_override.dart';
import 'package:treino/features/coach/domain/availability_rule.dart';
import 'package:treino/features/coach/presentation/agenda_strings.dart';
import 'package:treino/features/coach/presentation/availability_editor_screen.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

class _FakeAvailabilityRepository extends Fake
    implements AvailabilityRepository {}

class _FakeAppointmentRepository extends Fake
    implements AppointmentRepository {}

class _StubAvailabilityRepository extends Fake
    implements AvailabilityRepository {
  final List<Future<void> Function()> addRuleCalls = [];
  final List<Future<void> Function()> deleteRuleCalls = [];
  final List<Future<void> Function()> addOverrideCalls = [];
  final List<Future<void> Function()> deleteOverrideCalls = [];

  AvailabilityRule? addedRule;
  String? deletedRuleId;
  AvailabilityOverride? addedOverride;
  String? deletedOverrideId;

  @override
  Future<void> addRule(AvailabilityRule rule) async {
    addedRule = rule;
  }

  @override
  Future<void> updateRule(AvailabilityRule rule) async {}

  @override
  Future<void> deleteRule(String trainerId, String ruleId) async {
    deletedRuleId = ruleId;
  }

  @override
  Future<void> addOverride(AvailabilityOverride override) async {
    addedOverride = override;
  }

  @override
  Future<void> deleteOverride(String trainerId, String overrideId) async {
    deletedOverrideId = overrideId;
  }

  @override
  Stream<List<AvailabilityRule>> watchRules(String trainerId) =>
      const Stream.empty();

  @override
  Stream<List<AvailabilityOverride>> watchOverrides(
    String trainerId,
    DateTime fromDate,
    DateTime toDate,
  ) =>
      const Stream.empty();
}

// ── Fixtures ──────────────────────────────────────────────────────────────────

AvailabilityRule _makeRule({
  String id = 'rule-1',
  int dayOfWeek = DateTime.monday,
}) =>
    AvailabilityRule(
      id: id,
      trainerId: 'trainer-1',
      dayOfWeek: dayOfWeek,
      startHour: 9,
      startMinute: 0,
      endHour: 11,
      endMinute: 0,
      slotDurationMin: 60,
    );

AvailabilityOverride _makeBlockOverride({String id = 'override-1'}) =>
    AvailabilityOverride.block(
      id: id,
      trainerId: 'trainer-1',
      date: DateTime.utc(2026, 7, 6), // A Monday
    );

// ── Widget helper ─────────────────────────────────────────────────────────────

Widget _wrap(
  Widget child, {
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      availabilityRepositoryProvider
          .overrideWithValue(_FakeAvailabilityRepository()),
      appointmentRepositoryProvider
          .overrideWithValue(_FakeAppointmentRepository()),
      ...overrides,
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: child,
    ),
  );
}

Widget _editor({
  List<AvailabilityRule> rules = const [],
  List<AvailabilityOverride> overridesList = const [],
  AvailabilityRepository? repoOverride,
}) {
  return ProviderScope(
    overrides: [
      availabilityRepositoryProvider.overrideWithValue(
        repoOverride ?? _FakeAvailabilityRepository(),
      ),
      appointmentRepositoryProvider
          .overrideWithValue(_FakeAppointmentRepository()),
      availabilityRulesStreamProvider('trainer-1').overrideWith(
        (ref) => Stream.value(rules),
      ),
      overridesStreamProvider(OverridesKey(
        trainerId: 'trainer-1',
        fromDate: DateTime.utc(2026, 1, 1),
        toDate: DateTime.utc(2027, 12, 31),
      )).overrideWith((ref) => Stream.value(overridesList)),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: const AvailabilityEditorScreen(trainerId: 'trainer-1'),
    ),
  );
}

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  // ── SCENARIO-513: Screen renders with title and add-rule CTA ─────────────
  group('SCENARIO-513 — AvailabilityEditorScreen basic render', () {
    testWidgets(
      'SCENARIO-513: screen shows editor title and addRuleCta button',
      (tester) async {
        await tester.pumpWidget(_editor());
        await tester.pump();

        expect(find.text(AgendaStrings.editorTitle), findsOneWidget);
        expect(find.text(AgendaStrings.addRuleCta), findsOneWidget);
      },
    );
  });

  // ── SCENARIO-514: Rule list is rendered when rules exist ─────────────────
  group('SCENARIO-514 — Existing rules are listed', () {
    testWidgets(
      'SCENARIO-514: rule for Monday 09:00–11:00 is shown in the list',
      (tester) async {
        final rule = _makeRule(dayOfWeek: DateTime.monday);
        await tester.pumpWidget(_editor(rules: [rule]));
        await tester.pump();

        // Rule row must show the day label
        expect(find.text(AgendaStrings.dayOfWeekLabels[DateTime.monday]!),
            findsOneWidget);
      },
    );
  });

  // ── SCENARIO-515: Tapping add rule opens form sheet ───────────────────────
  group('SCENARIO-515 — Add rule form sheet opens', () {
    testWidgets(
      'SCENARIO-515: tapping addRuleCta opens a bottom sheet with save button',
      (tester) async {
        await tester.pumpWidget(_editor());
        await tester.pump();

        await tester.tap(find.text(AgendaStrings.addRuleCta));
        await tester.pumpAndSettle();

        // Form sheet must appear with a save/confirm action
        expect(find.text(AgendaStrings.bookingConfirmCta), findsOneWidget);
      },
    );
  });

  // ── SCENARIO-516: Delete rule shows confirmation then calls deleteRule ────
  group('SCENARIO-516 — Delete rule', () {
    testWidgets(
      'SCENARIO-516: delete icon tap shows confirm dialog, confirm removes rule',
      (tester) async {
        final stubRepo = _StubAvailabilityRepository();
        final rule = _makeRule(id: 'rule-to-delete');

        await tester.pumpWidget(_editor(
          rules: [rule],
          repoOverride: stubRepo,
        ));
        await tester.pump();

        // Find and tap the delete icon for the rule
        expect(find.byIcon(Icons.delete_outline), findsOneWidget);
        await tester.tap(find.byIcon(Icons.delete_outline));
        await tester.pumpAndSettle();

        // Confirmation dialog should show
        expect(find.text(AgendaStrings.ruleDeleteConfirm), findsOneWidget);

        // Tap the confirm button
        await tester.tap(find.text(AgendaStrings.bookingConfirmCta));
        await tester.pumpAndSettle();

        expect(stubRepo.deletedRuleId, equals('rule-to-delete'));
      },
    );
  });

  // ── SCENARIO-517: blockDayCta button is visible ───────────────────────────
  group('SCENARIO-517 — Block day CTA visible', () {
    testWidgets(
      'SCENARIO-517: blockDayCta is shown on the editor screen',
      (tester) async {
        await tester.pumpWidget(_editor());
        await tester.pump();

        expect(find.text(AgendaStrings.blockDayCta), findsOneWidget);
      },
    );
  });

  // ── SCENARIO-518: Existing overrides listed ───────────────────────────────
  group('SCENARIO-518 — Existing block overrides are listed', () {
    testWidgets(
      'SCENARIO-518: block override for a date appears in overrides section',
      (tester) async {
        final blockOverride = _makeBlockOverride();
        await tester.pumpWidget(_editor(overridesList: [blockOverride]));
        await tester.pump();

        // The override should display its date + "Bloqueado" label
        expect(find.text(AgendaStrings.slotBlockedLabel), findsOneWidget);
      },
    );
  });

  // ── SCENARIO-519: Delete override ─────────────────────────────────────────
  group('SCENARIO-519 — Delete override', () {
    testWidgets(
      'SCENARIO-519: delete icon for override calls deleteOverride on confirm',
      (tester) async {
        final stubRepo = _StubAvailabilityRepository();
        final blockOverride = _makeBlockOverride(id: 'override-to-delete');

        await tester.pumpWidget(ProviderScope(
          overrides: [
            availabilityRepositoryProvider.overrideWithValue(stubRepo),
            appointmentRepositoryProvider
                .overrideWithValue(_FakeAppointmentRepository()),
            availabilityRulesStreamProvider('trainer-1').overrideWith(
              (ref) => Stream.value([]),
            ),
            overridesStreamProvider(OverridesKey(
              trainerId: 'trainer-1',
              fromDate: DateTime.utc(2026, 1, 1),
              toDate: DateTime.utc(2027, 12, 31),
            )).overrideWith((ref) => Stream.value([blockOverride])),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const AvailabilityEditorScreen(trainerId: 'trainer-1'),
          ),
        ));
        await tester.pump();

        // Find delete icons — there might be one for each override row
        // The override should have a delete action
        final deleteIcons = find.byIcon(Icons.delete_outline);
        expect(deleteIcons, findsWidgets);

        // Tap the first delete icon (for the override)
        await tester.tap(deleteIcons.last);
        await tester.pumpAndSettle();

        // Confirm deletion
        await tester.tap(find.text(AgendaStrings.bookingConfirmCta));
        await tester.pumpAndSettle();

        expect(stubRepo.deletedOverrideId, equals('override-to-delete'));
      },
    );
  });
}
