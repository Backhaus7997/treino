import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/numeric_keyboard_done_bar.dart';
import 'package:treino/l10n/app_l10n.dart';

const _doneButton = Key('numeric_keyboard_done_button');
const _numberField = Key('number_field');
const _decimalField = Key('decimal_field');
const _textField = Key('text_field');

Widget _app() {
  return MaterialApp(
    theme: AppTheme.light(),
    locale: const Locale('es', 'AR'),
    localizationsDelegates: AppL10n.localizationsDelegates,
    supportedLocales: AppL10n.supportedLocales,
    builder: (context, child) => NumericKeyboardDoneBar(child: child!),
    home: const Scaffold(
      body: Column(
        children: [
          TextField(
            key: _numberField,
            keyboardType: TextInputType.number,
          ),
          TextField(
            key: _decimalField,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
          ),
          TextField(key: _textField),
        ],
      ),
    ),
  );
}

/// El teclado "sube": en el test se simula con `viewInsets` (1 px lógico = 1
/// físico, para que los 300 de acá sean 300 lógicos).
void _showKeyboard(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.viewInsets = const FakeViewPadding(bottom: 300);
}

void main() {
  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);
  final android = TargetPlatformVariant.only(TargetPlatform.android);

  group('NumericKeyboardDoneBar (#1500)', () {
    testWidgets(
      'aparece con el foco en un campo numérico y el teclado arriba',
      (tester) async {
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_app());

        await tester.tap(find.byKey(_numberField));
        _showKeyboard(tester);
        await tester.pumpAndSettle();

        expect(find.byKey(_doneButton), findsOneWidget);
        expect(find.text('Listo'), findsOneWidget);
      },
      variant: ios,
    );

    testWidgets(
      'también con el teclado numérico con decimales',
      (tester) async {
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_app());

        await tester.tap(find.byKey(_decimalField));
        _showKeyboard(tester);
        await tester.pumpAndSettle();

        expect(find.byKey(_doneButton), findsOneWidget);
      },
      variant: ios,
    );

    testWidgets(
      'no aparece en un campo de texto',
      (tester) async {
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_app());

        await tester.tap(find.byKey(_textField));
        _showKeyboard(tester);
        await tester.pumpAndSettle();

        expect(find.byKey(_doneButton), findsNothing);
      },
      variant: ios,
    );

    testWidgets(
      'no aparece si el teclado no está arriba',
      (tester) async {
        await tester.pumpWidget(_app());

        await tester.tap(find.byKey(_numberField));
        await tester.pumpAndSettle();

        expect(find.byKey(_doneButton), findsNothing);
      },
      variant: ios,
    );

    testWidgets(
      'no aparece fuera de iOS',
      (tester) async {
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_app());

        await tester.tap(find.byKey(_numberField));
        _showKeyboard(tester);
        await tester.pumpAndSettle();

        expect(find.byKey(_doneButton), findsNothing);
      },
      variant: android,
    );

    testWidgets(
      '"Listo" le saca el foco al campo y la barra desaparece',
      (tester) async {
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_app());

        await tester.tap(find.byKey(_numberField));
        _showKeyboard(tester);
        await tester.pumpAndSettle();
        final editable = find.descendant(
          of: find.byKey(_numberField),
          matching: find.byType(EditableText),
        );
        expect(
          tester.widget<EditableText>(editable).focusNode.hasFocus,
          isTrue,
        );

        await tester.tap(find.byKey(_doneButton));
        await tester.pumpAndSettle();

        expect(find.byKey(_doneButton), findsNothing);
        expect(
          tester.widget<EditableText>(editable).focusNode.hasFocus,
          isFalse,
        );
      },
      variant: ios,
    );

    testWidgets(
      'suma la altura de la barra a los viewInsets del contenido',
      (tester) async {
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_app());

        await tester.tap(find.byKey(_numberField));
        _showKeyboard(tester);
        await tester.pumpAndSettle();

        // Con esto el Scaffold encoge por el teclado Y por la barra, y la
        // barra no tapa el final del formulario.
        final media = MediaQuery.of(tester.element(find.byType(Scaffold)));
        expect(media.viewInsets.bottom, 300 + NumericKeyboardDoneBar.height);
      },
      variant: ios,
    );
  });
}
