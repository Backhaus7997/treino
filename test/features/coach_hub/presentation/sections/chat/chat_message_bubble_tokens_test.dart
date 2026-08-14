// Widget tests for ChatMessageBubble tokens (Fase 8, WU-07).
//
// Cubre:
//   - La burbuja propia (isOwn: true) usa un fondo sólido distinto al de la
//     burbuja recibida (isOwn: false) — propia = palette.accent (mint
//     sólido), recibida = palette.bgCard.
//   - Verificado en dark Y light theme (contraste de texto sobre el fondo
//     mint sólido debe seguir siendo alto en ambos).
//
// Remediación ronda 1 (CRITICAL-2 del verify report):
//   - Los 4 corner radii de la burbuja deben pertenecer a la escala cerrada
//     del design system (12/16/20/9999). `AppSpacing.hairline` (4.0) es un
//     token de SPACING, no de radio, y NO puede reusarse como radio de
//     esquina — regla dura "radii 12/16/20/full".

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/features/coach_hub/presentation/sections/chat/widgets/chat_message_bubble.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Escala cerrada de radios del design system TREINO (regla dura, ver
/// CLAUDE.md/AppRadius). Cualquier corner radius de un componente de
/// producción debe pertenecer a este set.
final _allowedRadii = {
  AppRadius.sm,
  AppRadius.md,
  AppRadius.lg,
  AppRadius.full
};

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

  group('ChatMessageBubble — radios de esquina (remediación CRITICAL-2)', () {
    for (final isOwn in [true, false]) {
      testWidgets(
        'los 4 corner radii pertenecen a la escala cerrada AppRadius '
        '(isOwn: $isOwn)',
        (tester) async {
          await tester.pumpWidget(_wrapBubble(
            ChatMessageBubble(
              key: const Key('bubble_under_test'),
              text: 'hola',
              isOwn: isOwn,
              createdAt: DateTime(2026, 7, 1, 10),
            ),
            theme: AppTheme.dark(),
          ));

          final container = tester.widget<Container>(
            find.byKey(const Key('chat_bubble_container')),
          );
          final decoration = container.decoration! as BoxDecoration;
          final radius = decoration.borderRadius! as BorderRadius;

          for (final corner in [
            radius.topLeft,
            radius.topRight,
            radius.bottomLeft,
            radius.bottomRight,
          ]) {
            expect(
              _allowedRadii,
              contains(corner.x),
              reason: 'corner radius $corner (x=${corner.x}) debe pertenecer a '
                  'la escala 12/16/20/9999 — AppSpacing.hairline (4.0) no es '
                  'un radio válido.',
            );
          }
        },
      );
    }
  });
}
