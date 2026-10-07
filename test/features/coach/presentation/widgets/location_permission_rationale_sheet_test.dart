import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/presentation/widgets/location_permission_rationale_sheet.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Guideline 5.1.1(iv) de Apple (build 1.0 (54)): el mensaje previo al
/// permiso del SO tiene UN solo botón, redactado «Continuar», y el usuario
/// SIEMPRE pasa al pedido del sistema. Nada de «Aceptar» ni «Ahora no», y
/// ninguna salida alternativa (arrastrar, tocar afuera, volver).
Widget _app(
    {Locale locale = const Locale('es', 'AR'),
    Future<void> Function()? onDone}) {
  return MaterialApp(
    theme: AppTheme.dark(),
    localizationsDelegates: AppL10n.localizationsDelegates,
    supportedLocales: AppL10n.supportedLocales,
    locale: locale,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              await showLocationPermissionRationaleSheet(context);
              await onDone?.call();
            },
            child: const Text('OPEN'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
}

void main() {
  group('LocationPermissionRationaleSheet — Guideline 5.1.1(iv)', () {
    testWidgets('muestra título y cuerpo', (tester) async {
      await tester.pumpWidget(_app());
      await _open(tester);

      expect(find.text('Tu ubicación'), findsOneWidget);
      expect(find.textContaining('entrenadores cerca tuyo'), findsOneWidget);
    });

    testWidgets('tiene UN solo botón y dice CONTINUAR', (tester) async {
      await tester.pumpWidget(_app());
      await _open(tester);

      final sheet = find.byType(BottomSheet);
      expect(
        find.descendant(
            of: sheet, matching: find.bySubtype<ButtonStyleButton>()),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('CONTINUAR')),
        findsOneWidget,
      );
    });

    testWidgets('no ofrece «Ahora no» ni «ACEPTAR»', (tester) async {
      await tester.pumpWidget(_app());
      await _open(tester);

      expect(find.text('Ahora no'), findsNothing);
      expect(find.text('ACEPTAR'), findsNothing);
    });

    testWidgets('en inglés el botón dice CONTINUE', (tester) async {
      await tester.pumpWidget(_app(locale: const Locale('en')));
      await _open(tester);

      expect(find.text('CONTINUE'), findsOneWidget);
      expect(find.text('Not now'), findsNothing);
    });

    testWidgets('tocar CONTINUAR cierra el sheet y devuelve el control',
        (tester) async {
      var returned = false;
      await tester.pumpWidget(_app(onDone: () async {
        returned = true;
      }));
      await _open(tester);

      await tester.tap(find.text('CONTINUAR'));
      await tester.pumpAndSettle();

      expect(returned, isTrue);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('tocar la barrera NO lo cierra', (tester) async {
      var returned = false;
      await tester.pumpWidget(_app(onDone: () async {
        returned = true;
      }));
      await _open(tester);

      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();

      expect(returned, isFalse);
      expect(find.text('CONTINUAR'), findsOneWidget);
    });

    testWidgets('arrastrarlo hacia abajo NO lo cierra', (tester) async {
      var returned = false;
      await tester.pumpWidget(_app(onDone: () async {
        returned = true;
      }));
      await _open(tester);

      await tester.drag(
        find.text('Tu ubicación'),
        const Offset(0, 600),
      );
      await tester.pumpAndSettle();

      expect(returned, isFalse);
      expect(find.text('CONTINUAR'), findsOneWidget);
    });

    testWidgets('el botón «atrás» del sistema NO lo cierra', (tester) async {
      var returned = false;
      await tester.pumpWidget(_app(onDone: () async {
        returned = true;
      }));
      await _open(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(returned, isFalse);
      expect(find.text('CONTINUAR'), findsOneWidget);
    });
  });
}
