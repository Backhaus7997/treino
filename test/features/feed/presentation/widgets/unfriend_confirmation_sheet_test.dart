import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/feed/presentation/widgets/unfriend_confirmation_sheet.dart';

// ---------------------------------------------------------------------------
// Helper: open the sheet from inside a test
// ---------------------------------------------------------------------------

Widget _buildOpenSheetButton({
  required String friendDisplayName,
  required VoidCallback onConfirm,
}) {
  return MaterialApp(
    theme: AppTheme.dark(),
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
    // SCENARIO-470: sheet renders interpolated friend name + CANCELAR + ELIMINAR
    testWidgets(
        'SCENARIO-470: sheet renders interpolated friend name, CANCELAR, and ELIMINAR buttons',
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
        find.text('¿Eliminar amistad con Vicente?'),
        findsOneWidget,
      );

      // Both action buttons
      expect(find.text('CANCELAR'), findsOneWidget);
      expect(find.text('ELIMINAR'), findsOneWidget);
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
        'SCENARIO-471: tapping ELIMINAR closes the sheet and calls onConfirm',
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

      // Tap ELIMINAR
      await tester.tap(find.text('ELIMINAR'));
      await tester.pumpAndSettle();

      // Sheet is dismissed
      expect(find.byType(UnfriendConfirmationSheet), findsNothing);

      // onConfirm was called exactly once
      expect(confirmCallCount, equals(1));
    });
  });
}
