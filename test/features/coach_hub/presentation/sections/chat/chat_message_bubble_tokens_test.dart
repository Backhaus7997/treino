// Widget tests for ChatMessageBubble tokens (Fase 8, WU-07).
//
// Cubre:
//   - La burbuja propia (isOwn: true) usa un fondo sólido distinto al de la
//     burbuja recibida (isOwn: false) — propia = palette.accent (mint
//     sólido), recibida = palette.bgCard.
//   - Verificado en dark Y light theme (contraste de texto sobre el fondo
//     mint sólido debe seguir siendo alto en ambos).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/chat/widgets/chat_message_bubble.dart';
import 'package:treino/l10n/app_l10n.dart';

Widget _wrapBubble(Widget child, {required ThemeData theme}) {
  return MediaQuery(
    data: const MediaQueryData(size: Size(1200, 800)),
    child: MaterialApp(
      theme: theme,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  group('ChatMessageBubble — tokens de color propio/recibido', () {
    for (final themeName in ['dark', 'light']) {
      testWidgets(
        'burbuja propia (isOwn=true) usa accent sólido, distinto del '
        'bgCard de la recibida (isOwn=false) — $themeName theme',
        (tester) async {
          final theme =
              themeName == 'dark' ? AppTheme.dark() : AppTheme.light();

          await tester.pumpWidget(_wrapBubble(
            ChatMessageBubble(
              key: const Key('own_bubble'),
              text: 'hola',
              isOwn: true,
              createdAt: DateTime(2026, 7, 1, 10),
            ),
            theme: theme,
          ));

          final ownCtx = tester.element(find.byKey(const Key('own_bubble')));
          final palette = AppPalette.of(ownCtx);

          final ownContainer = tester.widget<Container>(
            find.byKey(const Key('chat_bubble_container')),
          );
          final ownDecoration = ownContainer.decoration! as BoxDecoration;
          expect(ownDecoration.color, palette.accent,
              reason: 'burbuja propia debe usar accent sólido (mockup)');

          await tester.pumpWidget(_wrapBubble(
            ChatMessageBubble(
              key: const Key('received_bubble'),
              text: 'hola',
              isOwn: false,
              createdAt: DateTime(2026, 7, 1, 10),
            ),
            theme: theme,
          ));

          final receivedContainer = tester.widget<Container>(
            find.byKey(const Key('chat_bubble_container')),
          );
          final receivedDecoration =
              receivedContainer.decoration! as BoxDecoration;
          expect(receivedDecoration.color, palette.bgCard,
              reason: 'burbuja recibida debe usar bgCard');
          expect(
            receivedDecoration.color,
            isNot(equals(ownDecoration.color)),
            reason: 'propia y recibida deben distinguirse visualmente',
          );
        },
      );
    }
  });
}
