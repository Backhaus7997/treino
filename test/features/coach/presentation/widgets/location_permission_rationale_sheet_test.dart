import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/presentation/widgets/location_permission_rationale_sheet.dart';
import 'package:treino/l10n/app_l10n.dart';

Widget _wrapWithScaffold({required Future<bool> Function()? onShow}) {
  return MaterialApp(
    theme: AppTheme.dark(),
    localizationsDelegates: AppL10n.localizationsDelegates,
    supportedLocales: AppL10n.supportedLocales,
    locale: const Locale('es', 'AR'),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: onShow != null
                ? () => onShow()
                : () => showLocationPermissionRationaleSheet(context),
            child: const Text('OPEN'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('LocationPermissionRationaleSheet — T32/T33', () {
    testWidgets('shows title "Permitir ubicación"', (tester) async {
      await tester.pumpWidget(_wrapWithScaffold(onShow: null));

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();

      expect(find.text('Permitir ubicación'), findsOneWidget);
    });

    testWidgets('shows body text about location use', (tester) async {
      await tester.pumpWidget(_wrapWithScaffold(onShow: null));

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('entrenadores cerca tuyo'),
        findsOneWidget,
      );
    });

    testWidgets('shows "ACEPTAR" button', (tester) async {
      await tester.pumpWidget(_wrapWithScaffold(onShow: null));

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();

      expect(find.text('ACEPTAR'), findsOneWidget);
    });

    testWidgets('shows "Ahora no" button', (tester) async {
      await tester.pumpWidget(_wrapWithScaffold(onShow: null));

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();

      expect(find.text('Ahora no'), findsOneWidget);
    });

    testWidgets('tapping "ACEPTAR" returns true', (tester) async {
      bool? result;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showLocationPermissionRationaleSheet(context);
              },
              child: const Text('OPEN'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('ACEPTAR'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('tapping "Ahora no" returns false', (tester) async {
      bool? result;

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                result = await showLocationPermissionRationaleSheet(context);
              },
              child: const Text('OPEN'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ahora no'));
      await tester.pumpAndSettle();

      expect(result, isFalse);
    });
  });
}
