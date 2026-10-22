import 'dart:async' show Completer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/chat/data/chat_repository.dart';
import 'package:treino/features/chat/domain/media_type.dart';
import 'package:treino/features/chat/domain/message.dart';
import 'package:treino/features/chat/presentation/chat_image_bubble.dart';
import 'package:treino/features/chat/presentation/chat_screen.dart';
import 'package:treino/features/moderation/application/moderation_providers.dart';
import 'package:treino/features/chat/presentation/chat_video_bubble.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../helpers/fake_analytics_service.dart';

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('es', 'AR'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: child,
      ),
    );

UserPublicProfile _pub(String uid, String name) => UserPublicProfile(
      uid: uid,
      displayName: name,
      displayNameLowercase: name.toLowerCase(),
    );

/// Repo real salvo por `sendMessage`, que queda colgado hasta que el test
/// completa [gate]. Sirve para tener un envío en vuelo mientras la pantalla
/// se destruye.
class _GatedChatRepository extends ChatRepository {
  _GatedChatRepository({required super.firestore, required this.gate});

  final Completer<void> gate;

  /// Cuántas veces se llamó a `sendMessage`: un envío en vuelo no puede dejar
  /// pasar un segundo.
  int calls = 0;

  @override
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    String text = '',
    String? mediaUrl,
    MediaType? mediaType,
  }) {
    calls++;
    return gate.future;
  }
}

Message _msg({
  required String id,
  required String senderId,
  required String text,
  DateTime? at,
}) =>
    Message(
      id: id,
      senderId: senderId,
      text: text,
      createdAt: at ?? DateTime.utc(2026, 5, 21, 11, 0),
    );

Message _mediaMsg({
  required String senderId,
  required MediaType mediaType,
}) =>
    Message(
      id: 'md1',
      senderId: senderId,
      text: '',
      mediaUrl: 'https://firebasestorage.googleapis.com/x',
      mediaType: mediaType,
      createdAt: DateTime.utc(2026, 5, 21, 11, 0),
    );

/// Siembra la arista ENTRANTE `follows/{otro}_{yo}` aceptada.
///
/// Desde el cambio de producto del 2026-10-21 el composer ya no depende de
/// ningún follow (sólo de un bloqueo); los tests de envío la siguen sembrando
/// para ejercitar un par real, no porque haga falta.
Future<void> _seedIncomingFollow(
  FakeFirebaseFirestore firestore, {
  String other = 'bbb',
  String me = 'aaa',
}) =>
    firestore.collection('follows').doc('${other}_$me').set({
      'id': '${other}_$me',
      'followerUid': other,
      'followeeUid': me,
      'status': 'accepted',
      'members': [other, me],
      'createdAt': Timestamp.now(),
    });

void main() {
  group('ChatScreen', () {
    testWidgets('empty state cuando no hay mensajes', (tester) async {
      await tester.pumpWidget(_wrap(
        const ChatScreen(chatId: 'aaa_bbb', otherUid: 'bbb'),
        overrides: [
          currentUidProvider.overrideWith((_) => 'aaa'),
          messagesProvider('aaa_bbb').overrideWith(
            (_) => Stream.value(const <Message>[]),
          ),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('Sin mensajes todavía'), findsOneWidget);
      expect(find.textContaining('el primero'), findsOneWidget);
    });

    testWidgets('marca el chat como leído al abrir (REQ-CHATUNREAD-007)',
        (tester) async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('chats').doc('aaa_bbb').set({
        'chatId': 'aaa_bbb',
        'members': ['aaa', 'bbb'],
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 5, 20)),
        'lastMessageAt': Timestamp.fromDate(DateTime.utc(2026, 5, 21)),
        'lastMessageText': 'hola',
        'lastMessageSenderId': 'bbb',
      });
      await tester.pumpWidget(_wrap(
        const ChatScreen(chatId: 'aaa_bbb', otherUid: 'bbb'),
        overrides: [
          firestoreProvider.overrideWithValue(fake),
          currentUidProvider.overrideWith((_) => 'aaa'),
          messagesProvider('aaa_bbb').overrideWith(
            (_) => Stream.value(const <Message>[]),
          ),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
        ],
      ));
      await tester.pumpAndSettle();

      // The current user's lastRead key is written; the other member's is not.
      final doc = await fake.collection('chats').doc('aaa_bbb').get();
      final lastRead = doc.data()!['lastRead'] as Map<String, dynamic>?;
      expect(lastRead, isNotNull);
      expect(lastRead!['aaa'], isNotNull);
      expect(lastRead.containsKey('bbb'), isFalse);
    });

    testWidgets(
        'renderiza burbujas propias (derecha) y ajenas con textos distintos',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const ChatScreen(chatId: 'aaa_bbb', otherUid: 'bbb'),
        overrides: [
          currentUidProvider.overrideWith((_) => 'aaa'),
          messagesProvider('aaa_bbb').overrideWith(
            (_) => Stream.value([
              // recordá: en el stream vienen desc por createdAt
              _msg(
                  id: 'm2',
                  senderId: 'bbb',
                  text: 'dale, ahí voy',
                  at: DateTime.utc(2026, 5, 21, 11, 5)),
              _msg(
                  id: 'm1',
                  senderId: 'aaa',
                  text: 'arranca a las 18',
                  at: DateTime.utc(2026, 5, 21, 11, 0)),
            ]),
          ),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('arranca a las 18'), findsOneWidget);
      expect(find.text('dale, ahí voy'), findsOneWidget);
    });

    testWidgets('título del AppBar usa displayName del otro miembro',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const ChatScreen(chatId: 'aaa_bbb', otherUid: 'bbb'),
        overrides: [
          currentUidProvider.overrideWith((_) => 'aaa'),
          messagesProvider('aaa_bbb').overrideWith(
            (_) => Stream.value(const <Message>[]),
          ),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
        ],
      ));
      await tester.pumpAndSettle();

      // Heading del header: Barlow Condensed en mayúsculas (AGENTS.md §2).
      expect(find.text('COACH JOE'), findsOneWidget);
    });

    testWidgets('tap en send escribe el mensaje vía repo y limpia el textfield',
        (tester) async {
      // Usamos un repo real sobre FakeFirebaseFirestore para no mockear.
      final firestore = FakeFirebaseFirestore();
      final repo = ChatRepository(firestore: firestore);
      final chat = await repo.getOrCreate(selfId: 'aaa', otherId: 'bbb');
      await _seedIncomingFollow(firestore);
      final analytics = FakeAnalyticsService();

      await tester.pumpWidget(_wrap(
        ChatScreen(chatId: chat.chatId, otherUid: 'bbb'),
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
          currentUidProvider.overrideWith((_) => 'aaa'),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
          analyticsServiceProvider.overrideWithValue(analytics),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hola');
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();

      // Mensaje persistido
      final snap = await firestore
          .collection('chats')
          .doc(chat.chatId)
          .collection('messages')
          .get();
      expect(snap.docs.length, 1);
      expect(snap.docs.first.data()['text'], 'hola');

      // Textfield limpio
      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.controller!.text, '');

      // Analytics event disparado.
      expect(analytics.events, contains('chat_message_sent'));
    });

    testWidgets(
        'send que termina después de cerrar la pantalla no toca el controller '
        '(#501)', (tester) async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('chats').doc('aaa_bbb').set({
        'chatId': 'aaa_bbb',
        'members': ['aaa', 'bbb'],
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 5, 20)),
      });
      await _seedIncomingFollow(firestore);
      // El envío queda en vuelo hasta que el test abre la compuerta, así el
      // await sobrevive al dispose de la pantalla.
      final gate = Completer<void>();
      final analytics = FakeAnalyticsService();

      // Riverpod no admite cambiar la cantidad de overrides entre pumps: el
      // segundo pumpWidget reusa exactamente la misma lista.
      final overrides = <Override>[
        firestoreProvider.overrideWithValue(firestore),
        chatRepositoryProvider.overrideWithValue(
          _GatedChatRepository(firestore: firestore, gate: gate),
        ),
        currentUidProvider.overrideWith((_) => 'aaa'),
        messagesProvider('aaa_bbb').overrideWith(
          (_) => Stream.value(const <Message>[]),
        ),
        userPublicProfileProvider('bbb').overrideWith(
          (_) => Stream.value(_pub('bbb', 'Coach Joe')),
        ),
        analyticsServiceProvider.overrideWithValue(analytics),
      ];

      await tester.pumpWidget(_wrap(
        const ChatScreen(chatId: 'aaa_bbb', otherUid: 'bbb'),
        overrides: overrides,
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'hola');
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pump();

      // La pantalla muere con el envío todavía en vuelo (back, deep-link,
      // logout): el TextEditingController queda disposed.
      await tester.pumpWidget(
        _wrap(const SizedBox.shrink(), overrides: overrides),
      );
      await tester.pump();

      gate.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // El mensaje salió igual, así que el evento corresponde: lo único que
      // no debe pasar es que se toque la UI ya muerta.
      expect(analytics.events, contains('chat_message_sent'));
    });

    group('composer — teclado y borde (#1466)', () {
      /// Chat con permiso de escribir y un repo cuyo `sendMessage` queda
      /// colgado hasta que el test abre [gate].
      Future<_GatedChatRepository> pumpGated(
        WidgetTester tester,
        Completer<void> gate, {
        ThemeData? theme,
      }) async {
        final firestore = FakeFirebaseFirestore();
        await firestore.collection('chats').doc('aaa_bbb').set({
          'chatId': 'aaa_bbb',
          'members': ['aaa', 'bbb'],
          'createdAt': Timestamp.fromDate(DateTime.utc(2026, 5, 20)),
        });
        await _seedIncomingFollow(firestore);
        final repo = _GatedChatRepository(firestore: firestore, gate: gate);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              firestoreProvider.overrideWithValue(firestore),
              chatRepositoryProvider.overrideWithValue(repo),
              currentUidProvider.overrideWith((_) => 'aaa'),
              messagesProvider('aaa_bbb').overrideWith(
                (_) => Stream.value(const <Message>[]),
              ),
              userPublicProfileProvider('bbb').overrideWith(
                (_) => Stream.value(_pub('bbb', 'Coach Joe')),
              ),
              analyticsServiceProvider
                  .overrideWithValue(FakeAnalyticsService()),
            ],
            child: MaterialApp(
              theme: theme ?? AppTheme.dark(),
              locale: const Locale('es', 'AR'),
              localizationsDelegates: AppL10n.localizationsDelegates,
              supportedLocales: AppL10n.supportedLocales,
              home: const ChatScreen(chatId: 'aaa_bbb', otherUid: 'bbb'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        return repo;
      }

      FocusNode focoDelCampo(WidgetTester tester) =>
          tester.widget<EditableText>(find.byType(EditableText)).focusNode;

      testWidgets(
          'con el envío en vuelo el campo conserva el foco y el teclado: sólo '
          'se bloquea el botón', (tester) async {
        final gate = Completer<void>();
        final repo = await pumpGated(tester, gate);

        await tester.enterText(find.byType(TextField), 'hola');
        expect(focoDelCampo(tester).hasFocus, isTrue);
        await tester.tap(find.byTooltip('Enviar'));
        await tester.pump();

        expect(repo.calls, 1);
        expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue,
            reason: 'un TextField deshabilitado pierde el foco');
        expect(focoDelCampo(tester).hasFocus, isTrue);
        expect(tester.testTextInput.isVisible, isTrue,
            reason: 'el teclado no se cierra al enviar');

        // El botón quedó bloqueado: un segundo tap no manda otro mensaje.
        final boton = tester.widget<IconButton>(
          find.ancestor(
            of: find.byType(CircularProgressIndicator),
            matching: find.byType(IconButton),
          ),
        );
        expect(boton.onPressed, isNull);

        gate.complete();
        await tester.pumpAndSettle();

        expect(repo.calls, 1);
        expect(focoDelCampo(tester).hasFocus, isTrue);
        expect(tester.testTextInput.isVisible, isTrue);
      });

      testWidgets(
          'el campo se vacía al enviar: lo que se escribe durante el envío no '
          'se pierde cuando termina', (tester) async {
        final gate = Completer<void>();
        await pumpGated(tester, gate);

        await tester.enterText(find.byType(TextField), 'hola');
        await tester.tap(find.byTooltip('Enviar'));
        await tester.pump();
        expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            '');

        await tester.enterText(find.byType(TextField), 'siguiente');
        gate.complete();
        await tester.pumpAndSettle();

        expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            'siguiente');
      });

      testWidgets(
          'si el envío falla el texto vuelve al campo, antes de lo que se '
          'escribió después', (tester) async {
        final gate = Completer<void>();
        await pumpGated(tester, gate);

        await tester.enterText(find.byType(TextField), 'hola');
        await tester.tap(find.byTooltip('Enviar'));
        await tester.pump();
        await tester.enterText(find.byType(TextField), 'otra');

        gate.completeError(Exception('sin red'));
        await tester.pumpAndSettle();

        expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            'hola\notra');
        expect(find.text('No pudimos enviar el mensaje. Probá de nuevo.'),
            findsOneWidget);
      });

      for (final (nombre, theme) in [
        ('oscuro', AppTheme.dark()),
        ('claro', AppTheme.light()),
      ]) {
        testWidgets(
            'tema $nombre: el campo va sin borde ni relleno propios (una sola '
            'caja, la del contenedor)', (tester) async {
          await pumpGated(tester, Completer<void>(), theme: theme);

          final d = tester
              .widget<InputDecorator>(
                find.descendant(
                  of: find.byType(TextField),
                  matching: find.byType(InputDecorator),
                ),
              )
              .decoration;

          // Los bordes que importan son los de cada ESTADO: el
          // `InputDecorationTheme` de la app los define y mandan sobre
          // `border`.
          for (final borde in [
            d.border,
            d.enabledBorder,
            d.focusedBorder,
            d.disabledBorder,
            d.errorBorder,
            d.focusedErrorBorder,
          ]) {
            expect(borde?.borderSide, BorderSide.none);
          }
          expect(d.filled, isFalse);
          expect(d.contentPadding, EdgeInsets.zero);
        });
      }
    });

    testWidgets('tap en send con texto vacío no crea ningún mensaje',
        (tester) async {
      final firestore = FakeFirebaseFirestore();
      final repo = ChatRepository(firestore: firestore);
      final chat = await repo.getOrCreate(selfId: 'aaa', otherId: 'bbb');

      await tester.pumpWidget(_wrap(
        ChatScreen(chatId: chat.chatId, otherUid: 'bbb'),
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
          currentUidProvider.overrideWith((_) => 'aaa'),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();

      final snap = await firestore
          .collection('chats')
          .doc(chat.chatId)
          .collection('messages')
          .get();
      expect(snap.docs.length, 0);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Permiso de escritura: espejo de `senderMayPost` en las rules. Desde el
  // cambio de producto del 2026-10-21, en un chat existente escriben los dos
  // miembros sin requisito de follow; lo único que corta es un bloqueo. Si
  // cliente y servidor no coinciden, o el usuario escribe y rebota, o ve gris
  // algo que sí puede hacer.
  // ─────────────────────────────────────────────────────────────────────────
  group('ChatScreen — composer y permiso de escritura', () {
    /// Siembra el chat y, opcionalmente, un `linkId`, la marca de consulta o
    /// un bloqueo MÍO sobre el otro (`blocks/aaa_bbb`).
    Future<FakeFirebaseFirestore> seed({
      String? linkId,
      bool inquiry = false,
      bool iBlockedThem = false,
    }) async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('chats').doc('aaa_bbb').set({
        'chatId': 'aaa_bbb',
        'members': ['aaa', 'bbb'],
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 5, 20)),
        if (linkId != null) 'linkId': linkId,
        if (inquiry) 'kind': 'inquiry',
      });
      if (iBlockedThem) {
        await fake.collection('blocks').doc('aaa_bbb').set({
          'id': 'aaa_bbb',
          'blockerUid': 'aaa',
          'blockedUid': 'bbb',
          'members': ['aaa', 'bbb'],
          'createdAt': Timestamp.now(),
        });
      }
      return fake;
    }

    Future<void> pump(WidgetTester tester, FakeFirebaseFirestore fake) async {
      await tester.pumpWidget(_wrap(
        const ChatScreen(chatId: 'aaa_bbb', otherUid: 'bbb'),
        overrides: [
          firestoreProvider.overrideWithValue(fake),
          currentUidProvider.overrideWith((_) => 'aaa'),
          analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
          messagesProvider('aaa_bbb').overrideWith(
            (_) => Stream.value([
              _msg(id: 'm1', senderId: 'bbb', text: 'mensaje previo'),
            ]),
          ),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
        ],
      ));
      await tester.pumpAndSettle();
    }

    bool composerEnabled(WidgetTester tester) =>
        tester.widget<TextField>(find.byType(TextField)).enabled ?? true;

    testWidgets('sin ninguna arista → HABILITADO: responde sin seguirlo',
        (tester) async {
      await pump(tester, await seed());

      expect(composerEnabled(tester), isTrue);
      expect(find.textContaining('Bloqueaste'), findsNothing);
    });

    testWidgets('lo bloqueé → composer apagado y el aviso dice por qué',
        (tester) async {
      await pump(tester, await seed(iBlockedThem: true));

      // El campo SIGUE visible, apagado: si desapareciera, la pantalla se
      // vería rota sin explicación.
      expect(find.byType(TextField), findsOneWidget);
      expect(composerEnabled(tester), isFalse);
      expect(find.textContaining('Bloqueaste a esta persona'), findsOneWidget);
    });

    testWidgets('el historial se sigue viendo con el composer apagado',
        (tester) async {
      await pump(tester, await seed(iBlockedThem: true));

      // Bloquear la escritura NO puede esconder lo que ya se recibió.
      expect(find.text('mensaje previo'), findsOneWidget);
    });

    testWidgets('chat de Coach con linkId y CERO aristas → HABILITADO',
        (tester) async {
      await pump(tester, await seed(linkId: 'link-1'));
      expect(composerEnabled(tester), isTrue);
    });

    testWidgets('chat de pre-consulta con CERO aristas → HABILITADO',
        (tester) async {
      await pump(tester, await seed(inquiry: true));
      expect(composerEnabled(tester), isTrue);
    });

    // El frame de carga: con los bloqueos todavía sin llegar, no saber no
    // puede leerse como "bloqueado".
    testWidgets('mientras los bloqueos cargan → HABILITADO y sin aviso',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const ChatScreen(chatId: 'aaa_bbb', otherUid: 'bbb'),
        overrides: [
          firestoreProvider.overrideWithValue(await seed()),
          currentUidProvider.overrideWith((_) => 'aaa'),
          analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
          messagesProvider('aaa_bbb').overrideWith(
            (_) => Stream.value(const <Message>[]),
          ),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
          blockedUidsProvider('aaa').overrideWith((_) => const Stream.empty()),
        ],
      ));
      await tester.pump();

      expect(composerEnabled(tester), isTrue);
      expect(find.textContaining('Bloqueaste'), findsNothing);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // moderacion-reporte-y-bloqueo — la burbuja de texto no tenía NINGÚN gesto.
  // ─────────────────────────────────────────────────────────────────────────
  group('ChatScreen — burbuja: reportar por long-press', () {
    testWidgets('long-press en un mensaje AJENO abre el sheet de reporte',
        (tester) async {
      await tester.pumpWidget(_wrap(
        const ChatScreen(chatId: 'aaa_bbb', otherUid: 'bbb'),
        overrides: [
          currentUidProvider.overrideWith((_) => 'aaa'),
          messagesProvider('aaa_bbb').overrideWith(
            (_) => Stream.value([
              _msg(id: 'm1', senderId: 'bbb', text: 'mensaje ajeno'),
            ]),
          ),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('mensaje ajeno'));
      await tester.pumpAndSettle();

      expect(find.text('¿Por qué lo reportás?'), findsOneWidget);
    });

    testWidgets('long-press en un mensaje PROPIO no abre nada', (tester) async {
      await tester.pumpWidget(_wrap(
        const ChatScreen(chatId: 'aaa_bbb', otherUid: 'bbb'),
        overrides: [
          currentUidProvider.overrideWith((_) => 'aaa'),
          messagesProvider('aaa_bbb').overrideWith(
            (_) => Stream.value([
              _msg(id: 'm1', senderId: 'aaa', text: 'mensaje propio'),
            ]),
          ),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
        ],
      ));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('mensaje propio'));
      await tester.pumpAndSettle();

      expect(find.text('¿Por qué lo reportás?'), findsNothing);
    });
  });

  // Las burbujas de media retornaban ANTES del wrapper de long-press, así que
  // una foto o un video AJENO no tenía forma de reportarse — el contenido de
  // más riesgo del chat y lo primero que mira la Guideline 1.2.
  //
  // Acá se assertea el CABLEADO (`onLongPress` presente o en null) en vez de
  // disparar el gesto y esperar el sheet: las dos burbujas muestran un spinner
  // mientras carga la media, así que `pumpAndSettle` no termina nunca en esta
  // pantalla. Que el gesto dispare el callback lo cubren
  // `chat_image_bubble_test.dart` y `chat_video_bubble_test.dart`.
  group('ChatScreen — burbujas de media: reportar por long-press', () {
    testWidgets('foto AJENA queda reportable', (tester) async {
      await tester.pumpWidget(_wrap(
        const ChatScreen(chatId: 'aaa_bbb', otherUid: 'bbb'),
        overrides: [
          currentUidProvider.overrideWith((_) => 'aaa'),
          messagesProvider('aaa_bbb').overrideWith(
            (_) => Stream.value([
              _mediaMsg(senderId: 'bbb', mediaType: MediaType.image),
            ]),
          ),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
        ],
      ));
      await tester.pump();

      final bubble =
          tester.widget<ChatImageBubble>(find.byType(ChatImageBubble));
      expect(bubble.onLongPress, isNotNull);
    });

    testWidgets('foto PROPIA no queda reportable', (tester) async {
      await tester.pumpWidget(_wrap(
        const ChatScreen(chatId: 'aaa_bbb', otherUid: 'bbb'),
        overrides: [
          currentUidProvider.overrideWith((_) => 'aaa'),
          messagesProvider('aaa_bbb').overrideWith(
            (_) => Stream.value([
              _mediaMsg(senderId: 'aaa', mediaType: MediaType.image),
            ]),
          ),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
        ],
      ));
      await tester.pump();

      final bubble =
          tester.widget<ChatImageBubble>(find.byType(ChatImageBubble));
      expect(bubble.onLongPress, isNull);
    });

    testWidgets('video AJENO queda reportable', (tester) async {
      await tester.pumpWidget(_wrap(
        const ChatScreen(chatId: 'aaa_bbb', otherUid: 'bbb'),
        overrides: [
          currentUidProvider.overrideWith((_) => 'aaa'),
          messagesProvider('aaa_bbb').overrideWith(
            (_) => Stream.value([
              _mediaMsg(senderId: 'bbb', mediaType: MediaType.video),
            ]),
          ),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
        ],
      ));
      await tester.pump();

      final bubble =
          tester.widget<ChatVideoBubble>(find.byType(ChatVideoBubble));
      expect(bubble.onLongPress, isNotNull);
    });

    testWidgets('video PROPIO no queda reportable', (tester) async {
      await tester.pumpWidget(_wrap(
        const ChatScreen(chatId: 'aaa_bbb', otherUid: 'bbb'),
        overrides: [
          currentUidProvider.overrideWith((_) => 'aaa'),
          messagesProvider('aaa_bbb').overrideWith(
            (_) => Stream.value([
              _mediaMsg(senderId: 'aaa', mediaType: MediaType.video),
            ]),
          ),
          userPublicProfileProvider('bbb').overrideWith(
            (_) => Stream.value(_pub('bbb', 'Coach Joe')),
          ),
        ],
      ));
      await tester.pump();

      final bubble =
          tester.widget<ChatVideoBubble>(find.byType(ChatVideoBubble));
      expect(bubble.onLongPress, isNull);
    });
  });
}
