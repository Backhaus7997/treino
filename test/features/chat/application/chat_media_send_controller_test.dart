/// Issue #435 (QA-CHAT-005) — el envío de un adjunto debe sobrevivir al
/// dispose de la pantalla que lo disparó, y ninguna falla puede ser muda.
///
/// El bug original: `_onAttach` corría upload+send en el State del chat con
/// un `if (!mounted) return` entre ambas fases — al popear mid-upload el
/// archivo quedaba subido pero el mensaje nunca se creaba, sin aviso.
library;

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/root_scaffold_messenger.dart';
import 'package:treino/features/chat/application/chat_media_send_controller.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/chat/data/chat_media_upload_service.dart';
import 'package:treino/features/chat/data/chat_repository.dart';
import 'package:treino/features/chat/domain/media_type.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Upload service controlable: el test decide CUÁNDO termina el upload
/// (via [uploadCompleter]) y puede inyectar fallas ([uploadError]).
class _FakeChatMediaUploadService extends ChatMediaUploadService {
  _FakeChatMediaUploadService({this.uploadError});

  /// When non-null, [upload] throws it instead of returning a URL.
  final Object? uploadError;

  /// Completes the in-flight [upload] whenever the test says so — lets a
  /// test unsubscribe the "screen" while the upload is still in flight.
  final uploadCompleter = Completer<String>();

  void Function(double fraction)? capturedOnProgress;
  int uploadCalls = 0;
  final deletedUrls = <String>[];

  @override
  Future<String> upload(
    String localPath, {
    required String chatId,
    required MediaType mediaType,
    void Function(double fraction)? onProgress,
  }) async {
    uploadCalls++;
    capturedOnProgress = onProgress;
    final e = uploadError;
    if (e != null) throw e;
    return uploadCompleter.future;
  }

  @override
  Future<bool> deleteByDownloadUrl(String url) async {
    deletedUrls.add(url);
    return true;
  }
}

class _MockChatRepository extends Mock implements ChatRepository {}

void main() {
  late FakeFirebaseFirestore firestore;

  setUpAll(() {
    registerFallbackValue(MediaType.image);
  });

  setUp(() {
    firestore = FakeFirebaseFirestore();
  });

  ProviderContainer makeContainer({
    required ChatMediaUploadService upload,
    ChatRepository? repo,
  }) {
    final container = ProviderContainer(overrides: [
      chatMediaUploadServiceProvider.overrideWithValue(upload),
      chatRepositoryProvider
          .overrideWithValue(repo ?? ChatRepository(firestore: firestore)),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  /// sendMessage batchea un update sobre el chat doc — debe existir.
  Future<void> seedChat(String chatId) =>
      firestore.collection('chats').doc(chatId).set({
        'chatId': chatId,
        'members': ['u1', 'u2'],
        'createdAt': Timestamp.now(),
      });

  group('ChatMediaSendController — issue #435', () {
    test(
        'el envío completa aunque la pantalla se desuscriba mid-upload: '
        'el mensaje se crea igual', () async {
      final upload = _FakeChatMediaUploadService();
      final container = makeContainer(upload: upload);
      await seedChat('u1_u2');
      final provider = chatMediaSendControllerProvider('u1_u2');

      // "Pantalla montada": hay un listener del provider, como el ref.watch
      // del composer.
      final screen = container.listen(provider, (_, __) {});

      final send = container.read(provider.notifier).sendMedia(
            localPath: '/tmp/video.mp4',
            senderId: 'u1',
            mediaType: MediaType.video,
          );
      await Future<void>.delayed(Duration.zero);
      expect(container.read(provider).uploading, isTrue);

      // El usuario toca back mientras el video de 50MB sigue subiendo — el
      // listener muere (equivalente al dispose del State del chat).
      screen.close();

      // El upload recién termina DESPUÉS de que la pantalla murió.
      upload.uploadCompleter
          .complete('https://fake.url/chatMedia/u1_u2/video.mp4');
      await send;

      // Antes del fix: `if (!mounted) return` cortaba acá y el mensaje nunca
      // existía. Ahora el destinatario lo recibe igual.
      final msgs = await firestore
          .collection('chats')
          .doc('u1_u2')
          .collection('messages')
          .get();
      expect(msgs.docs, hasLength(1),
          reason: 'El adjunto no puede perderse al salir del chat');
      expect(msgs.docs.single.data()['mediaUrl'],
          'https://fake.url/chatMedia/u1_u2/video.mp4');
      expect(msgs.docs.single.data()['mediaType'], 'video');
      expect(msgs.docs.single.data()['senderId'], 'u1');
      expect(upload.deletedUrls, isEmpty,
          reason: 'Éxito → nada que limpiar en Storage');
    });

    test('expone uploading/progress durante el envío y vuelve a idle',
        () async {
      final upload = _FakeChatMediaUploadService();
      final container = makeContainer(upload: upload);
      await seedChat('u1_u2');
      final provider = chatMediaSendControllerProvider('u1_u2');
      final screen = container.listen(provider, (_, __) {});
      addTearDown(screen.close);

      final send = container.read(provider.notifier).sendMedia(
            localPath: '/tmp/pic.jpg',
            senderId: 'u1',
            mediaType: MediaType.image,
          );
      await Future<void>.delayed(Duration.zero);
      expect(container.read(provider).uploading, isTrue);

      upload.capturedOnProgress!(0.42);
      expect(container.read(provider).progress, closeTo(0.42, 1e-9));

      upload.uploadCompleter.complete('https://fake.url/pic.jpg');
      await send;

      expect(container.read(provider).uploading, isFalse);
      expect(container.read(provider).progress, 0);
    });

    test(
        'si sendMessage falla tras un upload exitoso: borra el objeto '
        'huérfano de Storage y no relanza', () async {
      final upload = _FakeChatMediaUploadService();
      final repo = _MockChatRepository();
      when(() => repo.sendMessage(
            chatId: any(named: 'chatId'),
            senderId: any(named: 'senderId'),
            text: any(named: 'text'),
            mediaUrl: any(named: 'mediaUrl'),
            mediaType: any(named: 'mediaType'),
          )).thenThrow(FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      ));
      final container = makeContainer(upload: upload, repo: repo);
      final provider = chatMediaSendControllerProvider('u1_u2');
      final screen = container.listen(provider, (_, __) {});
      addTearDown(screen.close);

      final send = container.read(provider.notifier).sendMedia(
            localPath: '/tmp/pic.jpg',
            senderId: 'u1',
            mediaType: MediaType.image,
          );
      upload.uploadCompleter.complete('https://fake.url/orphan.jpg');
      await send; // no debe relanzar — el controller es dueño del error

      expect(upload.deletedUrls, ['https://fake.url/orphan.jpg'],
          reason: 'Sin mensaje creado, el archivo subido es un huérfano '
              'que hay que borrar (issue #435)');
      expect(container.read(provider).uploading, isFalse);
    });

    test(
        'si el upload falla: no hay mensaje, no hay delete y el estado '
        'vuelve a idle sin relanzar', () async {
      final upload =
          _FakeChatMediaUploadService(uploadError: StateError('network down'));
      final container = makeContainer(upload: upload);
      await seedChat('u1_u2');
      final provider = chatMediaSendControllerProvider('u1_u2');
      final screen = container.listen(provider, (_, __) {});
      addTearDown(screen.close);

      await container.read(provider.notifier).sendMedia(
            localPath: '/tmp/pic.jpg',
            senderId: 'u1',
            mediaType: MediaType.image,
          );

      final msgs = await firestore
          .collection('chats')
          .doc('u1_u2')
          .collection('messages')
          .get();
      expect(msgs.docs, isEmpty);
      expect(upload.deletedUrls, isEmpty,
          reason: 'Nada llegó a subirse — no hay huérfano que borrar');
      expect(container.read(provider).uploading, isFalse);
    });

    test('ignora un segundo sendMedia mientras hay uno en vuelo', () async {
      final upload = _FakeChatMediaUploadService();
      final container = makeContainer(upload: upload);
      await seedChat('u1_u2');
      final provider = chatMediaSendControllerProvider('u1_u2');
      final screen = container.listen(provider, (_, __) {});
      addTearDown(screen.close);

      final notifier = container.read(provider.notifier);
      final first = notifier.sendMedia(
        localPath: '/tmp/a.jpg',
        senderId: 'u1',
        mediaType: MediaType.image,
      );
      await Future<void>.delayed(Duration.zero);
      await notifier.sendMedia(
        localPath: '/tmp/b.jpg',
        senderId: 'u1',
        mediaType: MediaType.image,
      );

      expect(upload.uploadCalls, 1);

      upload.uploadCompleter.complete('https://fake.url/a.jpg');
      await first;
    });

    testWidgets(
        'una falla avisa por el ScaffoldMessenger ROOT aunque el chat ya '
        'no esté montado', (tester) async {
      final upload =
          _FakeChatMediaUploadService(uploadError: StateError('boom'));
      final container = makeContainer(upload: upload);

      // App SIN ninguna pantalla de chat en el árbol — simula que el usuario
      // ya navegó a cualquier otro lado cuando la falla aterriza.
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          scaffoldMessengerKey:
              container.read(rootScaffoldMessengerKeyProvider),
          locale: const Locale('es', 'AR'),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      ));

      await container
          .read(chatMediaSendControllerProvider('u1_u2').notifier)
          .sendMedia(
            localPath: '/tmp/pic.jpg',
            senderId: 'u1',
            mediaType: MediaType.image,
          );
      await tester.pump();

      expect(find.text('No pudimos subir el archivo. Probá de nuevo.'),
          findsOneWidget,
          reason: 'La pérdida del adjunto no puede ser muda (issue #435)');
    });
  });
}
