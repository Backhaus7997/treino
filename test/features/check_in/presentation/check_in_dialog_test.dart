import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/check_in/application/check_in_providers.dart';
import 'package:treino/features/check_in/domain/check_in.dart';
import 'package:treino/features/check_in/presentation/check_in_dialog.dart';
import 'package:treino/l10n/app_l10n.dart';

class MockCheckInNotifier extends AsyncNotifier<CheckIn?>
    implements CheckInNotifier {
  @override
  Future<CheckIn?> build() async => null;

  @override
  Future<void> confirm({String? gymId, String? gymName}) async {}
}

Widget _wrap({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('CheckInDialog', () {
    testWidgets(
        'SCENARIO-333: renders gym name in subtext when gymId is non-null',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const CheckInDialog(
            gymId: 'smart-fit-palermo', gymName: 'Smart Fit'),
      ));
      await tester.pump();

      expect(find.text('¿ESTÁS EN EL GYM HOY?'), findsOneWidget);
      expect(find.textContaining('Smart Fit'), findsOneWidget);
    });

    testWidgets('SCENARIO-334: renders neutral subtext when gymId is null',
        (tester) async {
      await tester.pumpWidget(_wrap(
        child: const CheckInDialog(gymId: null, gymName: null),
      ));
      await tester.pump();

      expect(find.text('¿ESTÁS EN EL GYM HOY?'), findsOneWidget);
      expect(find.text('Confirma tu entrenamiento de hoy'), findsOneWidget);
    });

    testWidgets('SCENARIO-338 partial: NO button dismisses dialog',
        (tester) async {
      bool dialogOpen = true;
      await tester.pumpWidget(_wrap(
        child: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              await showDialog<void>(
                context: context,
                builder: (_) => const CheckInDialog(gymId: null, gymName: null),
              );
              dialogOpen = false;
            },
            child: const Text('Open'),
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('NO'), findsOneWidget);
      await tester.tap(find.text('NO'));
      await tester.pumpAndSettle();

      expect(dialogOpen, isFalse);
    });

    testWidgets('SCENARIO-337 partial: SÍ, ENTRÉ button is visible',
        (tester) async {
      await tester.pumpWidget(_wrap(
        overrides: [
          checkInNotifierProvider.overrideWith(() => MockCheckInNotifier()),
        ],
        child: const CheckInDialog(gymId: 'gym1', gymName: 'Smart Fit'),
      ));
      await tester.pump();

      expect(find.text('SÍ, ENTRÉ'), findsOneWidget);
    });
  });
}
