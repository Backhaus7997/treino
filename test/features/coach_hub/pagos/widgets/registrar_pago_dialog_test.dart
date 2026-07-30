/// Tests for RegistrarPagoDialog — PR2b + athlete-picker extension.
///
/// REQ-PAGW-REGISTRAR-001: dialog collects athlete + amount + concept +
/// estado (+ due date when pending), pops a [RegistrarPagoResult] on
/// confirm; no pop on cancel; validation shows an error for missing/invalid
/// fields. The dialog itself never touches the payment repository —
/// persistence is the caller's job (pagos_web_screen.dart).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart'
    show trainerLinksStreamProvider;
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/registrar_pago_dialog.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart'
    show userPublicProfilesBatchProvider;
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/l10n/app_l10n.dart';

// ── Fakes ─────────────────────────────────────────────────────────────────────

TrainerLink _link(
  String athleteId,
  TrainerLinkStatus status, {
  String? id,
  DateTime? requestedAt,
}) =>
    TrainerLink(
      id: id ?? 'l_$athleteId',
      trainerId: 'trainer-1',
      athleteId: athleteId,
      status: status,
      requestedAt: requestedAt ?? DateTime.utc(2026, 1, 1),
    );

UserPublicProfile _prof(String uid, String name) =>
    UserPublicProfile(uid: uid, displayName: name);

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _wrapDialog({
  List<TrainerLink> links = const [],
  List<UserPublicProfile> profiles = const [],
}) =>
    ProviderScope(
      overrides: [
        trainerLinksStreamProvider.overrideWith((ref) => Stream.value(links)),
        userPublicProfilesBatchProvider.overrideWith(
          (ref, key) => {for (final p in profiles) p.uid: p},
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: const Scaffold(
          body: Center(child: RegistrarPagoDialog()),
        ),
      ),
    );

/// Opens the dialog inside a route we can pop-capture the result from, so
/// tests can assert on the [RegistrarPagoResult] returned by `Navigator.pop`.
Future<RegistrarPagoResult?> _pumpAndOpen(
  WidgetTester tester, {
  List<TrainerLink> links = const [],
  List<UserPublicProfile> profiles = const [],
}) async {
  RegistrarPagoResult? captured;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trainerLinksStreamProvider.overrideWith((ref) => Stream.value(links)),
        userPublicProfilesBatchProvider.overrideWith(
          (ref, key) => {for (final p in profiles) p.uid: p},
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await showDialog<RegistrarPagoResult>(
                    context: context,
                    builder: (_) => const RegistrarPagoDialog(),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return captured;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('RegistrarPagoDialog (REQ-PAGW-REGISTRAR-001)', () {
    final links = [_link('athlete-1', TrainerLinkStatus.active)];
    final profiles = [_prof('athlete-1', 'Ana Activa')];

    // (a) Dialog renders correctly — alumno dropdown, Monto, Concepto, Estado.
    testWidgets(
        'dialog shows alumno dropdown, Monto, Concepto, and Estado toggle',
        (tester) async {
      await tester.pumpWidget(_wrapDialog(links: links, profiles: profiles));
      await tester.pumpAndSettle();

      expect(find.text('Registrar pago'), findsOneWidget); // i18n title
      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Monto (ARS)'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Concepto'), findsOneWidget);
      expect(find.text('Cobrado'), findsOneWidget); // i18n
      expect(find.text('Pendiente'), findsOneWidget); // i18n
    });

    // (b) Cancel → dialog pops null.
    testWidgets('SCENARIO — cancel → pops null', (tester) async {
      final result =
          await _pumpAndOpen(tester, links: links, profiles: profiles);
      // Result not yet captured (dialog still open) — cancel it now.
      expect(find.text('Cancelar'), findsOneWidget); // i18n
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });

    // (c) Submit without selecting an alumno → validation error, no pop.
    testWidgets(
        'SCENARIO — submit without alumno → shows "Elegí un alumno." error, '
        'does not pop', (tester) async {
      await tester.pumpWidget(_wrapDialog(links: links, profiles: profiles));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Registrar')); // i18n
      await tester.pumpAndSettle();

      expect(find.text('Elegí un alumno.'), findsOneWidget); // i18n
      // Dialog is still open (didn't pop).
      expect(find.byType(RegistrarPagoDialog), findsOneWidget);
    });

    // (d) Alumno + monto + concepto + Estado=Cobrado (default) → pops paid.
    testWidgets(
        'SCENARIO — alumno + monto + concepto + Cobrado → pops paid with '
        'dueAt null', (tester) async {
      RegistrarPagoResult? captured;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trainerLinksStreamProvider
                .overrideWith((ref) => Stream.value(links)),
            userPublicProfilesBatchProvider.overrideWith(
              (ref, key) => {for (final p in profiles) p.uid: p},
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      captured = await showDialog<RegistrarPagoResult>(
                        context: context,
                        builder: (_) => const RegistrarPagoDialog(),
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ana Activa').last);
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Monto (ARS)'), '5000');
      await tester.enterText(
          find.widgetWithText(TextField, 'Concepto'), 'Clase suelta');
      // Estado defaults to Cobrado — no fecha field should be visible.
      expect(find.text('Fecha de vencimiento'), findsNothing); // i18n

      await tester.tap(find.text('Registrar')); // i18n
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.athleteId, 'athlete-1');
      expect(captured!.amount, 5000);
      expect(captured!.concept, 'Clase suelta');
      expect(captured!.status, PaymentStatus.paid);
      expect(captured!.dueAt, isNull);
    });

    // (e) Estado=Pendiente reveals fecha field; picking a date → pending +
    // non-null dueAt.
    testWidgets(
        'SCENARIO — Estado=Pendiente reveals fecha field; picking a date → '
        'pops pending with non-null dueAt', (tester) async {
      RegistrarPagoResult? captured;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trainerLinksStreamProvider
                .overrideWith((ref) => Stream.value(links)),
            userPublicProfilesBatchProvider.overrideWith(
              (ref, key) => {for (final p in profiles) p.uid: p},
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      captured = await showDialog<RegistrarPagoResult>(
                        context: context,
                        builder: (_) => const RegistrarPagoDialog(),
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ana Activa').last);
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Monto (ARS)'), '3000');
      await tester.enterText(
          find.widgetWithText(TextField, 'Concepto'), 'Cuota mensual');

      // Toggle Estado to Pendiente.
      await tester.tap(find.text('Pendiente')); // i18n
      await tester.pumpAndSettle();
      expect(find.text('Fecha de vencimiento'), findsOneWidget); // i18n

      // Open the date picker and confirm a date (defaults to "today" — the
      // material date picker's default OK button confirms initialDate).
      await tester.tap(find.text('Elegí una fecha')); // i18n
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Registrar')); // i18n
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.status, PaymentStatus.pending);
      expect(captured!.dueAt, isNotNull);
    });

    // (f) Empty athlete list → muted message, Registrar disabled/no-op.
    testWidgets(
        'SCENARIO — empty athlete list → shows "No tenés alumnos vinculados." '
        'and submitting does not pop', (tester) async {
      await tester.pumpWidget(_wrapDialog());
      await tester.pumpAndSettle();

      expect(
          find.text('No tenés alumnos vinculados.'), // i18n
          findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);

      await tester.tap(find.text('Registrar')); // i18n
      await tester.pumpAndSettle();

      // Still open — validation blocked submission (no alumno available).
      expect(find.byType(RegistrarPagoDialog), findsOneWidget);
      expect(find.text('Elegí un alumno.'), findsOneWidget); // i18n
    });

    // (g) pending/terminated links are excluded from the dropdown.
    testWidgets(
        'SCENARIO — pending and terminated links excluded from the dropdown',
        (tester) async {
      final mixedLinks = [
        _link('a-active', TrainerLinkStatus.active),
        _link('a-pending', TrainerLinkStatus.pending),
        _link('a-terminated', TrainerLinkStatus.terminated),
      ];
      final mixedProfiles = [
        _prof('a-active', 'Alumno Activo'),
        _prof('a-pending', 'Alumno Pendiente'),
        _prof('a-terminated', 'Alumno Terminado'),
      ];
      await tester
          .pumpWidget(_wrapDialog(links: mixedLinks, profiles: mixedProfiles));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      expect(find.text('Alumno Activo'), findsOneWidget);
      expect(find.text('Alumno Pendiente'), findsNothing);
      expect(find.text('Alumno Terminado'), findsNothing);
    });
  });

  group('RegistrarPagoDialog with fixed athleteId (third-caller fix)', () {
    // (h) athleteId provided → dropdown hidden, submit pops with that id —
    // no dropdown interaction needed, no trainerLinksStreamProvider read.
    testWidgets(
        'SCENARIO — athleteId: "a1" → no dropdown shown; valid amount+concept '
        '→ pops RegistrarPagoResult with athleteId "a1"', (tester) async {
      RegistrarPagoResult? captured;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      captured = await showDialog<RegistrarPagoResult>(
                        context: context,
                        builder: (_) =>
                            const RegistrarPagoDialog(athleteId: 'a1'),
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // No dropdown, no "Alumno" label — the caller already knows the
      // athlete, so the picker block isn't rendered at all.
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.text('Alumno'), findsNothing);

      await tester.enterText(
          find.widgetWithText(TextField, 'Monto (ARS)'), '4000');
      await tester.enterText(
          find.widgetWithText(TextField, 'Concepto'), 'Clase suelta');

      await tester.tap(find.text('Registrar')); // i18n
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.athleteId, 'a1');
      expect(captured!.amount, 4000);
      expect(captured!.concept, 'Clase suelta');
      expect(captured!.status, PaymentStatus.paid);
    });
  });

  group('RegistrarPagoDialog — Estado=Pendiente requires a due date', () {
    // (i) Pendiente with no date picked → validation error, no pop.
    testWidgets(
        'SCENARIO — Estado=Pendiente with no date → shows "Elegí una fecha '
        'de vencimiento." and does not pop', (tester) async {
      final links = [_link('athlete-1', TrainerLinkStatus.active)];
      final profiles = [_prof('athlete-1', 'Ana Activa')];
      RegistrarPagoResult? captured;
      var popped = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trainerLinksStreamProvider
                .overrideWith((ref) => Stream.value(links)),
            userPublicProfilesBatchProvider.overrideWith(
              (ref, key) => {for (final p in profiles) p.uid: p},
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      captured = await showDialog<RegistrarPagoResult>(
                        context: context,
                        builder: (_) => const RegistrarPagoDialog(),
                      );
                      popped = true;
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ana Activa').last);
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Monto (ARS)'), '3000');
      await tester.enterText(
          find.widgetWithText(TextField, 'Concepto'), 'Cuota mensual');

      await tester.tap(find.text('Pendiente')); // i18n
      await tester.pumpAndSettle();

      await tester.tap(find.text('Registrar')); // i18n
      await tester.pumpAndSettle();

      expect(
          find.text('Elegí una fecha de vencimiento.'), // i18n
          findsOneWidget);
      expect(find.byType(RegistrarPagoDialog), findsOneWidget);
      expect(popped, isFalse);
      expect(captured, isNull);
    });

    // (j) Pendiente(pick date) → Cobrado → Pendiente → dueAt cleared.
    testWidgets(
        'SCENARIO — toggling Pendiente(date picked)→Cobrado clears the due '
        'date; submitting from Cobrado pops with dueAt null', (tester) async {
      final links = [_link('athlete-1', TrainerLinkStatus.active)];
      final profiles = [_prof('athlete-1', 'Ana Activa')];
      RegistrarPagoResult? captured;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trainerLinksStreamProvider
                .overrideWith((ref) => Stream.value(links)),
            userPublicProfilesBatchProvider.overrideWith(
              (ref, key) => {for (final p in profiles) p.uid: p},
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () async {
                      captured = await showDialog<RegistrarPagoResult>(
                        context: context,
                        builder: (_) => const RegistrarPagoDialog(),
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ana Activa').last);
      await tester.pumpAndSettle();

      await tester.enterText(
          find.widgetWithText(TextField, 'Monto (ARS)'), '3000');
      await tester.enterText(
          find.widgetWithText(TextField, 'Concepto'), 'Cuota mensual');

      // Pendiente → pick a date.
      await tester.tap(find.text('Pendiente')); // i18n
      await tester.pumpAndSettle();
      await tester.tap(find.text('Elegí una fecha')); // i18n
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Elegí una fecha'), findsNothing); // date is now set

      // Toggle back to Cobrado — the date field (and its section) disappears
      // entirely, so nothing to assert visually beyond that; verify via the
      // popped result instead.
      await tester.tap(find.text('Cobrado')); // i18n
      await tester.pumpAndSettle();
      expect(find.text('Fecha de vencimiento'), findsNothing); // i18n

      await tester.tap(find.text('Registrar')); // i18n
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.status, PaymentStatus.paid);
      expect(captured!.dueAt, isNull);
    });
  });
}
