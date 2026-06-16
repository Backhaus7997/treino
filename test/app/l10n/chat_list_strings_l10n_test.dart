// Chat list screen i18n key existence + verbatim tests.
//
// Covers chat/presentation/chat_list_screen.dart, which previously used
// hardcoded Spanish literals instead of AppL10n. These tests FAIL until the
// chat ARB keys are added and codegen is re-run.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/l10n/app_l10n.dart';

Future<AppL10n> _pumpAndGetL10n(WidgetTester tester) async {
  late AppL10n captured;
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Builder(
        builder: (context) {
          captured = AppL10n.of(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return captured;
}

void main() {
  group('AppL10n — chat list screen keys (es_AR)', () {
    testWidgets('chatListTitle verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.chatListTitle, 'MENSAJES');
    });

    testWidgets('chatListDeletedUser verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.chatListDeletedUser, 'Usuario eliminado');
    });

    testWidgets('chatListStartConversation verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.chatListStartConversation, 'Iniciá la conversación');
    });

    testWidgets('chatListEmptyTitle verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.chatListEmptyTitle, 'Sin mensajes todavía');
    });

    testWidgets('chatListEmptyBody verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(
        l10n.chatListEmptyBody,
        'Cuando tengas un vínculo activo con un PF, '
        'vas a poder chatear desde acá.',
      );
    });

    testWidgets('chatListError verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.chatListError, 'No pudimos cargar tus mensajes.');
    });

    testWidgets('chatListRetryLabel verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.chatListRetryLabel, 'Reintentar');
    });

    testWidgets('chatRelativeJustNow verbatim', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.chatRelativeJustNow, 'recién');
    });

    testWidgets('chatRelativeMinutes interpolates', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.chatRelativeMinutes(5), 'hace 5m');
    });

    testWidgets('chatRelativeHours interpolates', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.chatRelativeHours(3), 'hace 3h');
    });

    testWidgets('chatRelativeDays interpolates', (tester) async {
      final l10n = await _pumpAndGetL10n(tester);
      expect(l10n.chatRelativeDays(2), 'hace 2d');
    });
  });
}
