// PR3b — Excepciones de disponibilidad — test suite.
// SCENARIOS 302-A/B/C.
// Strings en español hardcodeado + // i18n.
// NO se usa AppL10n en este archivo.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/data/availability_repository.dart';
import 'package:treino/features/coach/domain/availability_override.dart';
import 'package:treino/features/coach/domain/availability_rule.dart';
import 'package:treino/features/coach_hub/presentation/sections/agenda/agenda_web_screen.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

// ─── Constants ───────────────────────────────────────────────────────────────

const _kTrainerId = 'trainer-uid-pr3b';
const _kBlockOverrideId = 'override-block-001';
const _kExtraOverrideId = 'override-extra-001';

// ─── Stub repository ─────────────────────────────────────────────────────────

/// Stub de [AvailabilityRepository] que captura addOverride / deleteOverride.
class _StubAvailabilityRepository extends Fake
    implements AvailabilityRepository {
  AvailabilityOverride? capturedAddOverride;
  String? capturedDeleteTrainerId;
  String? capturedDeleteOverrideId;
  bool shouldThrow = false;

  @override
  Future<void> addOverride(AvailabilityOverride override) async {
    if (shouldThrow) throw Exception('error');
    capturedAddOverride = override;
  }

  @override
  Future<void> deleteOverride(String trainerId, String overrideId) async {
    if (shouldThrow) throw Exception('error');
    capturedDeleteTrainerId = trainerId;
    capturedDeleteOverrideId = overrideId;
  }

  // Rules stubs (needed so the rules section renders without error)
  @override
  Future<void> addRule(AvailabilityRule rule) async {}

  @override
  Future<void> updateRule(AvailabilityRule rule) async {}

  @override
  Future<void> deleteRule(String trainerId, String ruleId) async {}
}

// ─── Factories ───────────────────────────────────────────────────────────────

AvailabilityOverride _blockOverride({
  String id = _kBlockOverrideId,
}) =>
    AvailabilityOverride.block(
      id: id,
      trainerId: _kTrainerId,
      date: DateTime.utc(2026, 8, 15),
    );

AvailabilityOverride _extraOverride({
  String id = _kExtraOverrideId,
}) =>
    AvailabilityOverride.extra(
      id: id,
      trainerId: _kTrainerId,
      date: DateTime.utc(2026, 8, 20),
      startHour: 7,
      startMinute: 0,
      endHour: 9,
      endMinute: 0,
      slotDurationMin: 60,
    );

// ─── Test wrap helper ─────────────────────────────────────────────────────────

Widget _wrap(Widget child, {required List<Override> overrides}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

// ─── Shared overrides builder ─────────────────────────────────────────────────

List<Override> _overrides({
  List<AvailabilityOverride> overrides = const [],
  _StubAvailabilityRepository? repo,
  bool overridesLoading = false,
}) {
  final stub = repo ?? _StubAvailabilityRepository();
  return [
    currentUidProvider.overrideWithValue(_kTrainerId),
    availabilityRepositoryProvider.overrideWithValue(stub),
    availabilityRulesStreamProvider.overrideWith(
      (ref, trainerId) => Stream.value(const []),
    ),
    overridesStreamProvider.overrideWith(
      (ref, key) =>
          overridesLoading ? const Stream.empty() : Stream.value(overrides),
    ),
    trainerAppointmentsStreamProvider.overrideWith(
      (ref, key) => Stream.value(const []),
    ),
  ];
}

// ─── Helper: open panel via "MIS HORARIOS" button ────────────────────────────

Future<void> _openPanel(
  WidgetTester tester, {
  List<AvailabilityOverride> overrides = const [],
  _StubAvailabilityRepository? repo,
  bool overridesLoading = false,
}) async {
  await tester.pumpWidget(
    _wrap(
      const AgendaWebScreen(),
      overrides: _overrides(
        overrides: overrides,
        repo: repo,
        overridesLoading: overridesLoading,
      ),
    ),
  );
  await tester.pumpAndSettle();

  final btn = find.text('MIS HORARIOS'); // i18n
  expect(btn, findsOneWidget,
      reason: 'AgendaWebScreen debe mostrar botón MIS HORARIOS');
  await tester.tap(btn);
  await tester.pumpAndSettle();
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // SCENARIO-302-A / 302-B / 302-C

  // ── Estado vacío de excepciones ───────────────────────────────────────────

  group('SCENARIO-302 — sección EXCEPCIONES visible con estado vacío', () {
    testWidgets('muestra encabezado EXCEPCIONES y estado vacío',
        (tester) async {
      await _openPanel(tester, overrides: const []);

      // Header must be present
      expect(find.text('EXCEPCIONES'), findsOneWidget); // i18n

      // Empty state hint
      expect(
        find.textContaining('Sin excepciones'), // i18n
        findsOneWidget,
      );
    });

    testWidgets('loading no colapsa en estado vacío', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const AgendaWebScreen(),
          overrides: _overrides(overridesLoading: true),
        ),
      );
      await tester.pump();

      final btn = find.text('MIS HORARIOS'); // i18n
      if (btn.evaluate().isNotEmpty) {
        await tester.tap(btn);
        await tester.pump();
        // Should show spinner, not the empty state hint
        expect(find.byType(CircularProgressIndicator), findsWidgets);
        expect(find.textContaining('Sin excepciones'), findsNothing);
      }
    });
  });

  // ── Tiles: block y extra ──────────────────────────────────────────────────

  group('SCENARIO-302 — tiles de override: block y extra', () {
    testWidgets('block override muestra fecha y etiqueta Día bloqueado',
        (tester) async {
      await _openPanel(tester, overrides: [_blockOverride()]);

      // Date formatted dd/MM/yyyy
      expect(find.textContaining('15/08/2026'), findsWidgets);
      // Type label
      expect(find.textContaining('Día bloqueado'), findsOneWidget); // i18n
    });

    testWidgets('extra override muestra fecha y ventana horaria',
        (tester) async {
      await _openPanel(tester, overrides: [_extraOverride()]);

      // Date
      expect(find.textContaining('20/08/2026'), findsWidgets);
      // Time range label — Extra HH:MM - HH:MM
      expect(find.textContaining('07:00'), findsWidgets);
      expect(find.textContaining('09:00'), findsWidgets);
    });

    testWidgets('block y extra aparecen juntos en la lista', (tester) async {
      await _openPanel(tester, overrides: [_blockOverride(), _extraOverride()]);

      expect(find.textContaining('Día bloqueado'), findsOneWidget); // i18n
      expect(find.textContaining('07:00'), findsWidgets);
    });
  });

  // SCENARIO-302-A: Add block override ─────────────────────────────────────

  group('SCENARIO-302-A — agregar override block llama addOverride(block)', () {
    testWidgets(
        'tap Bloquear día → diálogo → confirmar → addOverride(block) llamado',
        (tester) async {
      final stub = _StubAvailabilityRepository();
      await _openPanel(tester, overrides: const [], repo: stub);

      // Tap "BLOQUEAR DÍA" button
      final blockBtn = find.text('BLOQUEAR DÍA'); // i18n
      expect(blockBtn, findsOneWidget);
      await tester.tap(blockBtn);
      await tester.pumpAndSettle();

      // Alert dialog for block form must open
      expect(find.byType(AlertDialog), findsWidgets);

      // Confirm
      final confirmBtn = find.text('CONFIRMAR'); // i18n
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // addOverride called with a block override for this trainer
      expect(stub.capturedAddOverride, isNotNull);
      expect(stub.capturedAddOverride, isA<AvailabilityOverrideBlock>());
      final block = stub.capturedAddOverride as AvailabilityOverrideBlock;
      expect(block.trainerId, equals(_kTrainerId));
    });
  });

  // SCENARIO-302-B: Add extra override ─────────────────────────────────────

  group('SCENARIO-302-B — agregar override extra llama addOverride(extra)', () {
    testWidgets(
        'tap Ventana extra → diálogo → confirmar → addOverride(extra) llamado',
        (tester) async {
      final stub = _StubAvailabilityRepository();
      await _openPanel(tester, overrides: const [], repo: stub);

      // Tap "VENTANA EXTRA" button
      final extraBtn = find.text('VENTANA EXTRA'); // i18n
      expect(extraBtn, findsOneWidget);
      await tester.tap(extraBtn);
      await tester.pumpAndSettle();

      // Alert dialog for extra form must open
      expect(find.byType(AlertDialog), findsWidgets);

      // Confirm with defaults
      final confirmBtn = find.text('CONFIRMAR'); // i18n
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // addOverride called with an extra override for this trainer
      expect(stub.capturedAddOverride, isNotNull);
      expect(stub.capturedAddOverride, isA<AvailabilityOverrideExtra>());
      final extra = stub.capturedAddOverride as AvailabilityOverrideExtra;
      expect(extra.trainerId, equals(_kTrainerId));
    });
  });

  // SCENARIO-302-C: Delete override ─────────────────────────────────────────

  group('SCENARIO-302-C — eliminar override llama deleteOverride(trainerId,id)',
      () {
    testWidgets('tap eliminar block → confirmar → deleteOverride llamado',
        (tester) async {
      final stub = _StubAvailabilityRepository();
      await _openPanel(tester, overrides: [_blockOverride()], repo: stub);

      // Find delete icon button in overrides section
      final deleteIcons = find.byIcon(Icons.delete_outline);
      expect(deleteIcons, findsWidgets);
      await tester.tap(deleteIcons.last);
      await tester.pumpAndSettle();

      // Confirm dialog
      expect(find.textContaining('¿Eliminar'), findsOneWidget); // i18n

      final confirmBtn = find.text('CONFIRMAR'); // i18n
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // deleteOverride must be called with correct args
      expect(stub.capturedDeleteTrainerId, equals(_kTrainerId));
      expect(stub.capturedDeleteOverrideId, equals(_kBlockOverrideId));
    });
  });
}
