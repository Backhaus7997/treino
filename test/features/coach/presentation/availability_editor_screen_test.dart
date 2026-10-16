import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/data/appointment_repository.dart';
import 'package:treino/features/coach/data/availability_repository.dart';
import 'package:treino/features/coach/domain/availability_override.dart';
import 'package:treino/features/coach/domain/availability_rule.dart';
import 'package:treino/features/coach/presentation/availability_editor_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

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
  AvailabilityRule? updatedRule;
  String? deletedRuleId;
  AvailabilityOverride? addedOverride;
  String? deletedOverrideId;

  @override
  Future<void> addRule(AvailabilityRule rule) async {
    addedRule = rule;
  }

  @override
  Future<void> updateRule(AvailabilityRule rule) async {
    updatedRule = rule;
  }

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
  int startHour = 9,
  int endHour = 11,
}) =>
    AvailabilityRule(
      id: id,
      trainerId: 'trainer-1',
      dayOfWeek: dayOfWeek,
      startHour: startHour,
      startMinute: 0,
      endHour: endHour,
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

// ignore: unused_element
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
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
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

        // El título va en mayúsculas, como el resto de las pantallas (#1495).
        expect(find.text('MIS HORARIOS'), findsOneWidget);
        expect(find.text('AGREGAR HORARIO'), findsOneWidget);
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
        expect(find.text('Lunes'), findsOneWidget);
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

        await tester.tap(find.text('AGREGAR HORARIO'));
        await tester.pumpAndSettle();

        // Form sheet must appear with a save/confirm action (en mayúsculas,
        // como el resto de los botones primarios: #1495)
        expect(find.text('CONFIRMAR'), findsOneWidget);
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
        expect(find.byIcon(TreinoIcon.trash), findsOneWidget);
        await tester.tap(find.byIcon(TreinoIcon.trash));
        await tester.pumpAndSettle();

        // Confirmation dialog should show
        expect(
            find.text(
                '¿Borrar este horario? Las reservas existentes se mantienen.'),
            findsOneWidget);

        // Tap the confirm button
        await tester.tap(find.text('Confirmar'));
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

        expect(find.text('BLOQUEAR UN DÍA'), findsOneWidget);
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
        expect(find.text('Bloqueado'), findsOneWidget);
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
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            locale: const Locale('es', 'AR'),
            home: const AvailabilityEditorScreen(trainerId: 'trainer-1'),
          ),
        ));
        await tester.pump();

        // Find delete icons — there might be one for each override row
        // The override should have a delete action
        final deleteIcons = find.byIcon(TreinoIcon.trash);
        expect(deleteIcons, findsWidgets);

        // Tap the first delete icon (for the override)
        await tester.tap(deleteIcons.last);
        await tester.pumpAndSettle();

        // Confirm deletion
        await tester.tap(find.text('Confirmar'));
        await tester.pumpAndSettle();

        expect(stubRepo.deletedOverrideId, equals('override-to-delete'));
      },
    );
  });

  // ── #1495: franjas superpuestas ───────────────────────────────────────────
  group('#1495 — franjas superpuestas', () {
    testWidgets(
      'el default de "Agregar horario" no choca con lo ya cargado: '
      'con lunes 09–13 propone lunes 13–15',
      (tester) async {
        final stubRepo = _StubAvailabilityRepository();
        await tester.pumpWidget(_editor(
          rules: [_makeRule(startHour: 9, endHour: 13)],
          repoOverride: stubRepo,
        ));
        await tester.pump();

        await tester.tap(find.text('AGREGAR HORARIO'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('CONFIRMAR'));
        await tester.pumpAndSettle();

        final added = stubRepo.addedRule;
        expect(added, isNotNull, reason: 'el default debería poder guardarse');
        expect(added!.dayOfWeek, DateTime.monday);
        expect(added.startHour, 13);
        expect(added.endHour, 15);
      },
    );

    testWidgets(
      'editar una regla sin tocar nada no choca consigo misma',
      (tester) async {
        final stubRepo = _StubAvailabilityRepository();
        await tester.pumpWidget(_editor(
          rules: [_makeRule(id: 'solo')],
          repoOverride: stubRepo,
        ));
        await tester.pump();

        await tester.tap(find.byIcon(TreinoIcon.edit));
        await tester.pumpAndSettle();
        await tester.tap(find.text('CONFIRMAR'));
        await tester.pumpAndSettle();

        expect(stubRepo.updatedRule?.id, 'solo');
      },
    );

    testWidgets(
      'mover una regla encima de otra se rechaza ADENTRO del sheet, '
      'con el horario que pisa, y no guarda',
      (tester) async {
        final stubRepo = _StubAvailabilityRepository();
        await tester.pumpWidget(_editor(
          rules: [
            _makeRule(id: 'lunes', dayOfWeek: DateTime.monday),
            _makeRule(id: 'martes', dayOfWeek: DateTime.tuesday),
          ],
          repoOverride: stubRepo,
        ));
        await tester.pump();

        // Editar la del martes (la segunda) y pasarla al lunes 09–11.
        await tester.tap(find.byIcon(TreinoIcon.edit).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Lun'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('CONFIRMAR'));
        await tester.pumpAndSettle();

        const mensaje = 'Ese horario se superpone con otro que ya cargaste: '
            'Lunes, 09:00 – 11:00.';
        expect(find.text(mensaje), findsOneWidget);
        expect(find.byType(SnackBar), findsNothing);
        expect(stubRepo.updatedRule, isNull);
        expect(stubRepo.addedRule, isNull);

        // En cuanto cambia algo, el aviso se va.
        await tester.tap(find.text('Mar'));
        await tester.pumpAndSettle();
        expect(find.text(mensaje), findsNothing);
      },
    );

    testWidgets(
      'franjas pegadas (11:00 fin / 11:00 inicio) no se consideran superpuestas',
      (tester) async {
        final stubRepo = _StubAvailabilityRepository();
        // Lunes 07–09 cargado: el default (09–11) arranca justo donde termina.
        await tester.pumpWidget(_editor(
          rules: [_makeRule(startHour: 7, endHour: 9)],
          repoOverride: stubRepo,
        ));
        await tester.pump();

        await tester.tap(find.text('AGREGAR HORARIO'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('CONFIRMAR'));
        await tester.pumpAndSettle();

        expect(stubRepo.addedRule?.startHour, 9);
        expect(stubRepo.addedRule?.dayOfWeek, DateTime.monday);
      },
    );
  });

  // ── #1495: la pantalla habla el idioma del resto de la app ────────────────
  group('#1495 — restyle', () {
    testWidgets('chevron en vez de la flecha, y tachos rojos (no magenta)',
        (tester) async {
      await tester.pumpWidget(_editor(
        rules: [_makeRule()],
        overridesList: [_makeBlockOverride()],
      ));
      await tester.pump();

      expect(find.byIcon(TreinoIcon.chevronLeft), findsOneWidget);
      expect(find.byIcon(Icons.arrow_back), findsNothing);

      final palette = AppPalette.of(tester.element(find.byType(Scaffold)));
      final tachos = tester.widgetList<Icon>(find.byIcon(TreinoIcon.trash));
      expect(tachos, hasLength(2));
      for (final tacho in tachos) {
        expect(tacho.color, palette.danger);
        expect(tacho.color, isNot(palette.highlight));
      }
    });

    testWidgets(
        'el texto de los chips seleccionados se lee sobre el mint '
        '(color de botón, no el fondo de la pantalla)', (tester) async {
      await tester.pumpWidget(_editor());
      await tester.pump();

      await tester.tap(find.text('AGREGAR HORARIO'));
      await tester.pumpAndSettle();

      final context = tester.element(find.text('Lun'));
      final esperado = TreinoButtonTokens.foreground(context);

      // «Lun» (día) y «60 min» (duración) arrancan seleccionados.
      for (final etiqueta in ['Lun', '60 min']) {
        final texto = tester.widget<Text>(find.text(etiqueta));
        expect(texto.style?.color, esperado, reason: etiqueta);
      }
      // Uno NO seleccionado conserva el color de texto normal.
      final noSel = tester.widget<Text>(find.text('Mar'));
      expect(noSel.style?.color, AppPalette.of(context).textPrimary);
    });
  });
}
