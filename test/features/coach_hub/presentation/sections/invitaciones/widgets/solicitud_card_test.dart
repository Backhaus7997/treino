// WU-03 (Fase 4) — SolicitudCard presentational.
//
// TDD: tarjeta de una solicitud SIN acceso a repo — expone callbacks
// onAccept/onDecline, el caller (InvitacionesScreen, WU-04) es responsable
// de invocar trainerLinkRepositoryProvider. Sigue el patrón de
// _PendingRequestTile (dashboard_pending.dart) pero desacoplado del stream.
//
// SCENARIO-SC-01: pending && !busy → Aceptar/Rechazar visibles, callbacks.
// SCENARIO-SC-02: busy=true → spinner, sin botones (ni siquiera pending).
// SCENARIO-SC-03: status != pending → pill read-only, sin botones.
// SCENARIO-SC-04: avatar + nombre + Semantics(a11yAvatarLabel).
// SCENARIO-SC-05: dark+light smoke, sin crash.
// SCENARIO-SC-06: botones focusables + activables por teclado (Enter/Space).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/invitaciones/widgets/solicitud_card.dart';
import 'package:treino/l10n/app_l10n.dart';

Widget _wrap(Widget widget, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: Center(child: widget)),
    );

void main() {
  group('SolicitudCard —', () {
    testWidgets(
        'una solicitud de las 22:30 ART muestra la fecha ARGENTINA (#671)',
        (tester) async {
      // 2020-06-17 01:30 UTC == 2020-06-16 22:30 ART. Entre las 21:00 y la
      // medianoche argentina el día UTC ya rotó, y leer los campos crudos del
      // instante mostraba la fecha del día siguiente.
      //
      // La fecha es vieja a propósito: el formato relativo sólo cae al dd/mm
      // después de 7 días, que es la rama donde vivía el bug. Y al ser un
      // instante FIJO el test no depende del reloj ni del huso de la máquina —
      // falla con el código viejo en cualquier CI, incluido TZ=UTC.
      await tester.pumpWidget(_wrap(
        SolicitudCard(
          id: 'r9',
          displayName: 'Ana García',
          requestedAt: DateTime.utc(2020, 6, 17, 1, 30),
          status: TrainerLinkStatus.pending,
          onAccept: () {},
          onDecline: () {},
        ),
      ));
      await tester.pump();

      expect(find.text('16/06'), findsOneWidget);
      expect(find.text('17/06'), findsNothing);
    });

    testWidgets(
        'pending && !busy → Aceptar/Rechazar visibles, keys y callbacks '
        '[SCENARIO-SC-01]', (tester) async {
      var accepted = 0;
      var declined = 0;

      await tester.pumpWidget(_wrap(
        SolicitudCard(
          id: 'r1',
          displayName: 'Ana García',
          requestedAt: DateTime.now().subtract(const Duration(hours: 2)),
          status: TrainerLinkStatus.pending,
          onAccept: () => accepted++,
          onDecline: () => declined++,
        ),
      ));
      await tester.pump();

      expect(find.byKey(const Key('solicitud_card_r1')), findsOneWidget);
      expect(find.text('Ana García'), findsOneWidget);
      expect(find.byKey(const Key('accept_r1')), findsOneWidget);
      expect(find.byKey(const Key('decline_r1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('accept_r1')));
      await tester.pump();
      expect(accepted, 1);
      expect(declined, 0);

      await tester.tap(find.byKey(const Key('decline_r1')));
      await tester.pump();
      expect(declined, 1);
    });

    testWidgets(
        'requestedAt reciente → texto relativo visible [SCENARIO-SC-01b]',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SolicitudCard(
          id: 'r1',
          displayName: 'Ana García',
          requestedAt: DateTime.now().subtract(const Duration(seconds: 10)),
          status: TrainerLinkStatus.pending,
        ),
      ));
      await tester.pump();

      expect(find.text('recién'), findsOneWidget);
    });

    testWidgets('busy=true → spinner visible, sin botones [SCENARIO-SC-02]',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SolicitudCard(
          id: 'r1',
          displayName: 'Ana García',
          requestedAt: DateTime.now(),
          status: TrainerLinkStatus.pending,
          busy: true,
          onAccept: () {},
          onDecline: () {},
        ),
      ));
      // No pumpAndSettle: el spinner anima indefinidamente.
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('accept_r1')), findsNothing);
      expect(find.byKey(const Key('decline_r1')), findsNothing);
    });

    testWidgets(
        'status active → pill read-only "ACEPTADA", sin botones '
        '[SCENARIO-SC-03]', (tester) async {
      await tester.pumpWidget(_wrap(
        SolicitudCard(
          id: 'r2',
          displayName: 'Beto López',
          requestedAt: DateTime.now(),
          status: TrainerLinkStatus.active,
          onAccept: () {},
          onDecline: () {},
        ),
      ));
      await tester.pump();

      expect(find.text('ACEPTADA'), findsOneWidget);
      expect(find.byKey(const Key('accept_r2')), findsNothing);
      expect(find.byKey(const Key('decline_r2')), findsNothing);
    });

    testWidgets('status paused → pill read-only "PAUSADA" [SCENARIO-SC-03b]',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SolicitudCard(
          id: 'r3',
          displayName: 'Caro Díaz',
          requestedAt: DateTime.now(),
          status: TrainerLinkStatus.paused,
        ),
      ));
      await tester.pump();

      expect(find.text('PAUSADA'), findsOneWidget);
    });

    testWidgets(
        'status terminated → pill read-only "RECHAZADA" [SCENARIO-SC-03c]',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SolicitudCard(
          id: 'r4',
          displayName: 'Dani Ruiz',
          requestedAt: DateTime.now(),
          status: TrainerLinkStatus.terminated,
        ),
      ));
      await tester.pump();

      expect(find.text('RECHAZADA'), findsOneWidget);
    });

    testWidgets(
        'avatar → Semantics(image) con a11yAvatarLabel(nombre) '
        '[SCENARIO-SC-04]', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_wrap(
        SolicitudCard(
          id: 'r1',
          displayName: 'Ana García',
          requestedAt: DateTime.now(),
          status: TrainerLinkStatus.pending,
        ),
      ));
      await tester.pump();

      final l10n = AppL10n.of(
        tester.element(find.byKey(const Key('solicitud_card_r1'))),
      );
      // El label del avatar se funde con el fallback de inicial ("A") en el
      // mismo SemanticsNode (mismo comportamiento que `_PendingRequestTile`
      // en dashboard_pending.dart) — se valida con RegExp (substring) en vez
      // de igualdad exacta.
      expect(
        find.bySemanticsLabel(RegExp(RegExp.escape(
          l10n.a11yAvatarLabel('Ana García'),
        ))),
        findsOneWidget,
      );

      handle.dispose();
    });

    testWidgets('smoke dark+light sin crash [SCENARIO-SC-05]', (tester) async {
      for (final theme in [AppTheme.dark(), AppTheme.light()]) {
        await tester.pumpWidget(_wrap(
          SolicitudCard(
            id: 'r1',
            displayName: 'Ana García',
            requestedAt: DateTime.now().subtract(const Duration(days: 1)),
            status: TrainerLinkStatus.pending,
            onAccept: () {},
            onDecline: () {},
          ),
          theme: theme,
        ));
        await tester.pump();
        expect(find.byKey(const Key('solicitud_card_r1')), findsOneWidget);
      }
    });

    testWidgets(
        'botón Aceptar → focusable, Enter activa, Semantics(button) '
        '[SCENARIO-SC-06]', (tester) async {
      final handle = tester.ensureSemantics();
      var accepted = 0;
      await tester.pumpWidget(_wrap(
        SolicitudCard(
          id: 'r1',
          displayName: 'Ana García',
          requestedAt: DateTime.now(),
          status: TrainerLinkStatus.pending,
          onAccept: () => accepted++,
        ),
      ));
      await tester.pump();

      final semantics = tester.getSemantics(
        find.byKey(const Key('accept_r1')),
      );
      expect(semantics.flagsCollection.isButton, isTrue);

      final focusNode = Focus.of(
        tester.element(find.byKey(const Key('accept_r1'))),
      );
      focusNode.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(accepted, 1);

      handle.dispose();
    });
  });
}
