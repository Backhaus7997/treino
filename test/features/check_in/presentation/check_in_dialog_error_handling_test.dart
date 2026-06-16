import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/check_in/application/check_in_providers.dart';
import 'package:treino/features/check_in/domain/check_in.dart';
import 'package:treino/features/check_in/presentation/check_in_dialog.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Notifier whose [confirm] mimics the real one: it swallows the write failure
/// into error state via AsyncValue.guard instead of throwing.
class _FailingCheckInNotifier extends AsyncNotifier<CheckIn?>
    implements CheckInNotifier {
  @override
  Future<CheckIn?> build() async => null;

  @override
  Future<void> confirm({String? gymId, String? gymName}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard<CheckIn?>(
      () async => throw Exception('firestore write denied'),
    );
  }
}

/// Notifier whose [confirm] succeeds, leaving the state without error.
class _SuccessCheckInNotifier extends AsyncNotifier<CheckIn?>
    implements CheckInNotifier {
  @override
  Future<CheckIn?> build() async => null;

  @override
  Future<void> confirm({String? gymId, String? gymName}) async {
    state = const AsyncValue.data(null);
  }
}

Widget _harness({required List<Override> overrides}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) =>
                  const CheckInDialog(gymId: 'gym1', gymName: 'Smart Fit'),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('CheckInDialog error handling', () {
    testWidgets(
        'keeps dialog open and shows error SnackBar when confirm() fails',
        (tester) async {
      await tester.pumpWidget(_harness(overrides: [
        checkInNotifierProvider.overrideWith(_FailingCheckInNotifier.new),
      ]));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('SÍ, ENTRÉ'), findsOneWidget);

      await tester.tap(find.text('SÍ, ENTRÉ'));
      await tester.pumpAndSettle();

      // Error surfaced and the dialog did NOT close on a failed write.
      expect(
        find.text('No pudimos registrar tu check-in. Probá de nuevo.'),
        findsOneWidget,
      );
      expect(find.text('SÍ, ENTRÉ'), findsOneWidget);
    });

    testWidgets('closes dialog without error on successful confirm()',
        (tester) async {
      await tester.pumpWidget(_harness(overrides: [
        checkInNotifierProvider.overrideWith(_SuccessCheckInNotifier.new),
      ]));

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('SÍ, ENTRÉ'), findsOneWidget);

      await tester.tap(find.text('SÍ, ENTRÉ'));
      await tester.pumpAndSettle();

      // Dialog dismissed; no error SnackBar.
      expect(find.text('SÍ, ENTRÉ'), findsNothing);
      expect(
        find.text('No pudimos registrar tu check-in. Probá de nuevo.'),
        findsNothing,
      );
    });
  });
}
