import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/chat/domain/media_type.dart';
import 'package:treino/features/chat/domain/message.dart';
import 'package:treino/features/chat/presentation/chat_image_bubble.dart';
import 'package:treino/features/chat/presentation/photo_viewer_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      locale: const Locale('es', 'AR'),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: Scaffold(body: child),
    );

Message _imageMsg({String text = ''}) => Message(
      id: 'msg1',
      senderId: 'aaa',
      text: text,
      mediaUrl: 'https://firebasestorage.googleapis.com/img.jpg',
      mediaType: MediaType.image,
      createdAt: DateTime.utc(2026, 5, 21),
    );

void main() {
  group('ChatImageBubble', () {
    testWidgets('renders CachedNetworkImage thumbnail', (tester) async {
      await tester.pumpWidget(_wrap(ChatImageBubble(message: _imageMsg())));
      await tester.pump();

      expect(find.byType(CachedNetworkImage), findsOneWidget);
    });

    testWidgets('tap navigates to PhotoViewerScreen', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('es', 'AR'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(body: ChatImageBubble(message: _imageMsg())),
      ));
      await tester.pump();

      await tester.tap(find.byType(GestureDetector).first);
      // Use pump() with a duration instead of pumpAndSettle() to avoid timeout
      // caused by CachedNetworkImage's ongoing image load animation.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(PhotoViewerScreen), findsOneWidget);
    });

    testWidgets('caption is displayed below image when text non-empty',
        (tester) async {
      await tester.pumpWidget(
          _wrap(ChatImageBubble(message: _imageMsg(text: 'Great form!'))));
      await tester.pump();

      expect(find.text('Great form!'), findsOneWidget);
    });

    testWidgets('no caption widget when text is empty', (tester) async {
      await tester.pumpWidget(_wrap(ChatImageBubble(message: _imageMsg())));
      await tester.pump();

      // No text should appear for empty caption.
      expect(find.text(''), findsNothing);
    });
  });
}
