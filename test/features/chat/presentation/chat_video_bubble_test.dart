import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/firebase_storage_video_player.dart';
import 'package:treino/features/chat/domain/media_type.dart';
import 'package:treino/features/chat/domain/message.dart';
import 'package:treino/features/chat/presentation/chat_video_bubble.dart';
import 'package:treino/l10n/app_l10n.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      locale: const Locale('es', 'AR'),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      home: Scaffold(body: child),
    );

Message _videoMsg({String text = ''}) => Message(
      id: 'vid1',
      senderId: 'aaa',
      text: text,
      mediaUrl: 'https://firebasestorage.googleapis.com/vid.mp4',
      mediaType: MediaType.video,
      createdAt: DateTime.utc(2026, 5, 21),
    );

void main() {
  group('ChatVideoBubble', () {
    testWidgets('renders FirebaseStorageVideoPlayer in tree', (tester) async {
      await tester.pumpWidget(_wrap(ChatVideoBubble(message: _videoMsg())));
      await tester.pump();

      expect(find.byType(FirebaseStorageVideoPlayer), findsOneWidget);
    });

    testWidgets('caption is displayed below video when text non-empty',
        (tester) async {
      await tester.pumpWidget(
          _wrap(ChatVideoBubble(message: _videoMsg(text: 'Watch this rep'))));
      await tester.pump();

      expect(find.text('Watch this rep'), findsOneWidget);
    });

    testWidgets('no caption when text is empty', (tester) async {
      await tester.pumpWidget(_wrap(ChatVideoBubble(message: _videoMsg())));
      await tester.pump();

      expect(find.text(''), findsNothing);
    });
  });
}
