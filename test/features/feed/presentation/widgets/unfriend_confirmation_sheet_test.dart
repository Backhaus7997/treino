import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/feed/presentation/widgets/unfriend_confirmation_sheet.dart';
import 'package:treino/l10n/app_l10n.dart';

// ---------------------------------------------------------------------------
// Helper: open the sheet from inside a test
// ---------------------------------------------------------------------------

/// Envuelve un widget suelto con el theme y los delegates de l10n.
Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: child),
    );

Widget _buildOpenSheetButton({
  required String friendDisplayName,
  required VoidCallback onConfirm,
}) {
  return MaterialApp(
    theme: AppTheme.dark(),
    localizationsDelegates: AppL10n.localizationsDelegates,
    supportedLocales: AppL10n.supportedLocales,
    locale: const Locale('es', 'AR'),
    home: Scaffold(
      body: Builder(
        builder: (ctx) => Center(
          child: ElevatedButton(
            onPressed: () {
              showModalBottomSheet<void>(
                context: ctx,
                builder: (_) => UnfriendConfirmationSheet(
                  friendDisplayName: friendDisplayName,
                  onConfirm: onConfirm,
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests: SCENARIO-470, SCENARIO-471b, SCENARIO-471
// ---------------------------------------------------------------------------

void main() {
  group('UnfriendConfirmationSheet', () {
    // SCENARIO-470: el sheet interpola el nombre + CANCELAR + DEJAR DE SEGUIR
    testWidgets(
        'SCENARIO-470: el sheet interpola el nombre y muestra CANCELAR y DEJAR DE SEGUIR',
        (tester) async {
      await tester.pumpWidget(
        _buildOpenSheetButton(
          friendDisplayName: 'Vicente',
          onConfirm: () {},
        ),
      );

      // Open the sheet
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Sheet is present
      expect(find.byType(UnfriendConfirmationSheet), findsOneWidget);

      // Interpolated copy
      expect(
        find.text('¿Dejar de seguir a Vicente?'),
        findsOneWidget,
      );

      // Both action buttons
      expect(find.text('CANCELAR'), findsOneWidget);
      expect(find.text('DEJAR DE SEGUIR'), findsOneWidget);
    });

    // SCENARIO-471b: CANCELAR pops the sheet WITHOUT firing onConfirm
    testWidgets(
        'SCENARIO-471b: tapping CANCELAR closes sheet without calling onConfirm',
        (tester) async {
      var confirmCallCount = 0;

      await tester.pumpWidget(
        _buildOpenSheetButton(
          friendDisplayName: 'Vicente',
          onConfirm: () => confirmCallCount++,
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Sheet is open
      expect(find.byType(UnfriendConfirmationSheet), findsOneWidget);

      // Tap CANCELAR
      await tester.tap(find.text('CANCELAR'));
      await tester.pumpAndSettle();

      // Sheet is dismissed
      expect(find.byType(UnfriendConfirmationSheet), findsNothing);

      // onConfirm was NOT called
      expect(confirmCallCount, equals(0));
    });

    // SCENARIO-471: ELIMINAR pops the sheet and fires onConfirm
    testWidgets(
        'SCENARIO-471: tapping DEJAR DE SEGUIR closes the sheet and calls onConfirm',
        (tester) async {
      var confirmCallCount = 0;

      await tester.pumpWidget(
        _buildOpenSheetButton(
          friendDisplayName: 'Vicente',
          onConfirm: () => confirmCallCount++,
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Sheet is open
      expect(find.byType(UnfriendConfirmationSheet), findsOneWidget);

      // Tap DEJAR DE SEGUIR
      await tester.tap(find.text('DEJAR DE SEGUIR'));
      await tester.pumpAndSettle();

      // Sheet is dismissed
      expect(find.byType(UnfriendConfirmationSheet), findsNothing);

      // onConfirm was called exactly once
      expect(confirmCallCount, equals(1));
    });
  });

  // REQ-FOLLOW-007 — el sheet se reusa para cancelar una solicitud enviada, y
  // ahí el copy NO puede hablar de eliminar: todavía no hay vínculo que
  // eliminar, sólo un pedido que nadie contestó.
  group('UnfriendConfirmationSheet — modo cancelar solicitud', () {
    testWidgets('el copy habla de la solicitud, no de dejar de seguir',
        (tester) async {
      await tester.pumpWidget(_wrap(
        UnfriendConfirmationSheet(
          friendDisplayName: 'Vicente',
          mode: UnfollowSheetMode.cancelRequest,
          onConfirm: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('¿Cancelar la solicitud a Vicente?'), findsOneWidget);
      expect(find.text('CANCELAR SOLICITUD'), findsOneWidget);
      expect(find.text('DEJAR DE SEGUIR'), findsNothing);
    });

    testWidgets('el botón de descarte dice VOLVER, no CANCELAR',
        (tester) async {
      // Si dijera CANCELAR quedarían dos botones que empiezan igual —
      // "CANCELAR" y "CANCELAR SOLICITUD"— uno al lado del otro, y el que
      // descarta se leería como el que confirma.
      var confirmed = false;
      await tester.pumpWidget(_wrap(
        UnfriendConfirmationSheet(
          friendDisplayName: 'Vicente',
          mode: UnfollowSheetMode.cancelRequest,
          onConfirm: () => confirmed = true,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('VOLVER'), findsOneWidget);
      await tester.tap(find.text('VOLVER'));
      await tester.pumpAndSettle();
      expect(confirmed, isFalse);
    });
  });
}
