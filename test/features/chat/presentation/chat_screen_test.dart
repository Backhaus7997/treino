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
import 'package:treino/features/chat/presentation/chat_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

import 'package:treino/features/feed/domain/follow.dart';
import 'package:treino/features/feed/domain/follow_status.dart';

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

  @override
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    String text = '',
    String? mediaUrl,
    MediaType? mediaType,
  }) =>
      gate.future;
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

/// Siembra la arista ENTRANTE `follows/{otro}_{yo}` aceptada.
///
/// Desde REQ-FOLLOW-021 el composer sólo se habilita si el OTRO me sigue, así
/// que cualquier test que ejercite el ENVÍO necesita esta precondición — igual
/// que la necesita el usuario real.
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

      expect(find.text('Coach Joe'), findsOneWidget);
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
  // Composer bloqueado — REQ-FOLLOW-021 / SCENARIO-843/844.
  //
  // Desde el flip de rules hay usuarios que NO PUEDEN ENVIAR en un chat que se
  // ve completamente normal. Sin esta UI el modo de falla es un
  // `permission-denied` crudo DESPUÉS de escribir el mensaje — la peor forma
  // posible de comunicar una decisión de producto.
  //
  // El permiso lo da la arista ENTRANTE (`follows/{otro}_{yo}` aceptada), o sea
  // el espejo exacto de `senderMayPost` en las rules. Si cliente y servidor no
  // coinciden, o el usuario escribe y rebota, o ve gris algo que sí puede
  // hacer.
  // ─────────────────────────────────────────────────────────────────────────
  group('ChatScreen — composer y permiso de escritura', () {
    /// Siembra el chat y, opcionalmente, la arista entrante y un `linkId`.
    Future<FakeFirebaseFirestore> seed({
      Follow? incomingEdge,
      String? linkId,
    }) async {
      final fake = FakeFirebaseFirestore();
      await fake.collection('chats').doc('aaa_bbb').set({
        'chatId': 'aaa_bbb',
        'members': ['aaa', 'bbb'],
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 5, 20)),
        if (linkId != null) 'linkId': linkId,
      });
      if (incomingEdge != null) {
        await fake
            .collection('follows')
            .doc(incomingEdge.id)
            .set({...incomingEdge.toJson(), 'createdAt': Timestamp.now()});
      }
      return fake;
    }

    /// `follows/bbb_aaa` — el OTRO me sigue a mí. Es la que habilita escribir.
    Follow incoming(FollowStatus status) => Follow(
          id: Follow.edgeId('bbb', 'aaa'),
          followerUid: 'bbb',
          followeeUid: 'aaa',
          status: status,
          members: const ['bbb', 'aaa'],
          createdAt: DateTime.utc(2026, 1, 1),
        );

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

    // SCENARIO-843
    testWidgets('sin arista entrante → composer bloqueado y aviso visible',
        (tester) async {
      await pump(tester, await seed());

      // El campo SIGUE visible, apagado: si desapareciera, la pantalla se
      // vería rota sin explicación. El aviso dice por qué.
      expect(find.byType(TextField), findsOneWidget);
      expect(composerEnabled(tester), isFalse);
      expect(find.textContaining('tiene que seguirte'), findsOneWidget);
    });

    // SCENARIO-843 — la mitad que no se toca.
    testWidgets('el historial se sigue viendo con el composer bloqueado',
        (tester) async {
      await pump(tester, await seed());

      // Bloquear la escritura NO puede esconder lo que ya se recibió.
      expect(find.text('mensaje previo'), findsOneWidget);
    });

    testWidgets('arista entrante pending → sigue bloqueado', (tester) async {
      await pump(
          tester, await seed(incomingEdge: incoming(FollowStatus.pending)));

      expect(composerEnabled(tester), isFalse);
    });

    // SCENARIO-844
    testWidgets('arista entrante aceptada → composer habilitado, sin aviso',
        (tester) async {
      await pump(
          tester, await seed(incomingEdge: incoming(FollowStatus.accepted)));

      expect(composerEnabled(tester), isTrue);
      expect(find.textContaining('tiene que seguirte'), findsNothing);
    });

    // EL QUE PROTEGE AL COACH.
    //
    // El plan asumía que los chats de Coach no pasan por esta pantalla. Es
    // FALSO: `athlete_coach_view.dart:593` (atleta → su PF) y
    // `athlete_detail_screen.dart:309` (PF → su alumno) los dos empujan
    // `/coach/chat/...`, que renderiza ChatScreen. Gatear sólo por la arista
    // le sacaría el chat al entrenador, aunque el servidor se lo permita
    // (`senderMayPost` escapa por `'linkId' in chat`).
    testWidgets('chat de Coach con linkId y CERO aristas → HABILITADO',
        (tester) async {
      await pump(tester, await seed(linkId: 'link-1'));

      expect(composerEnabled(tester), isTrue);
      expect(find.textContaining('tiene que seguirte'), findsNothing);
    });
  });
}
