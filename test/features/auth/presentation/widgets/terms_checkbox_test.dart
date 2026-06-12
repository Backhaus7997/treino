import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/presentation/widgets/terms_checkbox.dart';

void main() {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final launched = <String>[];

  setUp(() {
    launched.clear();
    // Mock the url_launcher platform channel: canLaunch → true, and record the
    // URL passed to launch/launchUrl so we can assert which page was opened.
    TestWidgetsFlutterBinding.ensureInitialized()
        .defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'canLaunch':
          return true;
        case 'launch':
        case 'launchUrl':
          launched.add((call.arguments as Map)['url'] as String);
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(20), child: child),
        ),
      );

  String plainText(WidgetTester tester) => tester
      .widgetList<RichText>(find.byType(RichText))
      .map((rt) => rt.text.toPlainText())
      .join(' ');

  group('TermsCheckbox', () {
    testWidgets('renders checkbox and the full terms sentence', (tester) async {
      await tester.pumpWidget(wrap(
        TermsCheckbox(value: false, onChanged: (_) {}),
      ));
      await tester.pump();

      expect(find.byType(Checkbox), findsOneWidget);
      final text = plainText(tester);
      expect(text, contains('Acepto los'));
      expect(text, contains('Términos'));
      expect(text, contains('Política de Privacidad'));
    });

    testWidgets('toggling the checkbox fires onChanged', (tester) async {
      bool? changed;
      await tester.pumpWidget(wrap(
        TermsCheckbox(value: false, onChanged: (v) => changed = v),
      ));
      await tester.pump();

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(changed, isTrue);
    });

    testWidgets('tapping Términos opens the terms URL, no SnackBar',
        (tester) async {
      await tester.pumpWidget(wrap(
        TermsCheckbox(value: false, onChanged: (_) {}),
      ));
      await tester.pump();

      await tester.tapOnText(find.textRange.ofSubstring('Términos'));
      await tester.pumpAndSettle();

      expect(launched, isNotEmpty);
      expect(launched.first, contains('notion'));
      // The old dead-end SnackBar must be gone — users can now actually read it.
      expect(find.text('Próximamente'), findsNothing);
    });

    testWidgets('tapping Política de Privacidad opens the privacy URL',
        (tester) async {
      await tester.pumpWidget(wrap(
        TermsCheckbox(value: false, onChanged: (_) {}),
      ));
      await tester.pump();

      await tester
          .tapOnText(find.textRange.ofSubstring('Política de Privacidad'));
      await tester.pumpAndSettle();

      expect(launched, isNotEmpty);
      expect(launched.first, contains('notion'));
    });
  });
}
