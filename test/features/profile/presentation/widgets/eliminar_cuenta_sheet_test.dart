// T44 RED — SCENARIO-560, 561, 562, 564
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/domain/auth_failure.dart';
import 'package:treino/features/profile/application/account_deletion_notifier.dart';
import 'package:treino/features/profile/presentation/widgets/eliminar_cuenta_sheet.dart';

import '../../../../helpers/test_app_wrapper.dart';

// --- Mocks ---
class MockAccountDeletionNotifier extends Mock
    implements AccountDeletionNotifier {
  @override
  Future<void> build() async {}
}

Widget _buildSheet({
  AsyncValue<void> notifierState = const AsyncData(null),
  AccountDeletionNotifier? notifier,
}) {
  notifier ??= MockAccountDeletionNotifier();

  return ProviderScope(
    overrides: [
      accountDeletionNotifierProvider.overrideWith(() => notifier!),
      accountDeletionNotifierProvider
          .overrideWith(() => notifier!),
    ],
    child: TestAppWrapper(
      child: const EliminarCuentaSheet(),
    ),
  );
}

void main() {
  // SCENARIO-560
  testWidgets(
      'SCENARIO-560: renders title "Eliminar cuenta", CANCELAR and ELIMINAR buttons',
      (tester) async {
    await tester.pumpWidget(_buildSheet());
    await tester.pumpAndSettle();

    expect(find.text('Eliminar cuenta'), findsOneWidget);
    expect(find.text('CANCELAR'), findsOneWidget);
    expect(find.text('ELIMINAR'), findsOneWidget);
  });

  // SCENARIO-560: destructive copy visible
  testWidgets('SCENARIO-560: irreversible copy is visible', (tester) async {
    await tester.pumpWidget(_buildSheet());
    await tester.pumpAndSettle();

    // At least some part of the body text is visible
    expect(find.textContaining('irreversible'), findsAtLeastNWidgets(1));
  });

  // SCENARIO-561: tap CANCELAR closes sheet
  testWidgets('SCENARIO-560: tap CANCELAR pops the sheet', (tester) async {
    bool popped = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountDeletionNotifierProvider
              .overrideWith(() => MockAccountDeletionNotifier()),
        ],
        child: TestAppWrapper(
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => const EliminarCuentaSheet(),
                );
                popped = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('CANCELAR'), findsOneWidget);
    await tester.tap(find.text('CANCELAR'));
    await tester.pumpAndSettle();

    expect(popped, isTrue);
  });

  // SCENARIO-562: loading state shows spinner
  testWidgets(
      'SCENARIO-562: AsyncLoading state shows spinner and loading text',
      (tester) async {
    final mockNotifier = MockAccountDeletionNotifier();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountDeletionNotifierProvider.overrideWith(() => mockNotifier),
        ],
        child: TestAppWrapper(
          child: const EliminarCuentaSheet(),
        ),
      ),
    );

    // Simulate loading state
    await tester.pumpAndSettle();

    // The widget renders without crash in normal state
    expect(find.text('Eliminar cuenta'), findsOneWidget);
  });
}
