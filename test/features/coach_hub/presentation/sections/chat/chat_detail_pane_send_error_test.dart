// El envío del chat del Coach Hub fallaba y no dejaba rastro: el `catch (_)`
// del composer se comía el error entero y el PF sólo veía "Reintentá".
//
// Reintentar es el consejo correcto para una caída de red y el equivocado para
// un `permission-denied`, que va a fallar igual las próximas cien veces. Estos
// tests fijan que las dos ramas se distingan por el CÓDIGO REAL de Firestore y
// no por una sospecha, y que el error llegue a la telemetría en vez de morirse
// adentro del catch.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/chat/data/chat_repository.dart';
import 'package:treino/features/chat/domain/chat.dart';
import 'package:treino/features/chat/domain/media_type.dart';
import 'package:treino/features/chat/domain/message.dart';
import 'package:treino/features/coach_hub/presentation/sections/chat/chat_section_screen.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

const _pfUid = 'pf-1';
const _athleteUid = 'athlete-1';
const _chatId = 'chat-1';
const _athleteUid2 = 'athlete-2';
const _chatId2 = 'chat-2';

/// Repositorio que falla siempre en `sendMessage` con el error que se le pase.
/// Todo lo demás lo hereda del real contra un Firestore falso, así el detail
/// pane se monta igual que en producción.
class _FailingSendRepository extends ChatRepository {
  _FailingSendRepository(this._error)
      : super(firestore: FakeFirebaseFirestore());

  final Object _error;

  @override
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    String text = '',
    String? mediaUrl,
    MediaType? mediaType,
  }) async =>
      throw _error;
}

/// Repositorio cuyo envío queda COLGADO hasta que el test lo resuelve. Es lo
/// que permite meterse en el medio y cambiar de conversación con el envío en
/// vuelo, que es el caso que rompía el diagnóstico.
class _PendingSendRepository extends ChatRepository {
  _PendingSendRepository() : super(firestore: FakeFirebaseFirestore());

  final completer = Completer<void>();

  @override
  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    String text = '',
    String? mediaUrl,
    MediaType? mediaType,
  }) =>
      completer.future;
}

Chat _stubChat() => Chat(
      chatId: _chatId,
      members: const [_pfUid, _athleteUid],
      createdAt: DateTime(2026, 6, 1),
      lastMessageAt: DateTime(2026, 7, 1, 10),
      lastMessageText: 'hola',
    );

Chat _stubChat2() => Chat(
      chatId: _chatId2,
      members: const [_pfUid, _athleteUid2],
      createdAt: DateTime(2026, 6, 1),
      lastMessageAt: DateTime(2026, 7, 1, 9),
      lastMessageText: 'buenas',
    );

UserPublicProfile _stubPub2() => const UserPublicProfile(
      uid: _athleteUid2,
      displayName: 'Mariano',
      avatarUrl: null,
      gymId: null,
    );

UserPublicProfile _stubPub() => const UserPublicProfile(
      uid: _athleteUid,
      displayName: 'Vicente',
      avatarUrl: null,
      gymId: null,
    );

Widget _wrapSection({required List<Override> overrides}) => MediaQuery(
      data: const MediaQueryData(size: Size(1200, 800)),
      child: ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          home: const Scaffold(body: ChatSectionScreen()),
        ),
      ),
    );

List<Override> _overrides(Object error) => [
      currentUidProvider.overrideWithValue(_pfUid),
      chatRepositoryProvider.overrideWithValue(_FailingSendRepository(error)),
      chatsForCurrentUserProvider.overrideWith(
        (ref) => Stream<List<Chat>>.value([_stubChat()]),
      ),
      userPublicProfileProvider(_athleteUid).overrideWith(
        (ref) => Stream<UserPublicProfile?>.value(_stubPub()),
      ),
      messagesProvider(_chatId).overrideWith(
        (ref) => Stream<List<Message>>.value(const []),
      ),
    ];

/// Abre el chat, escribe en el composer y manda. Devuelve cuando el snackbar
/// ya está en pantalla.
Future<void> _intentarEnviar(WidgetTester tester, Object error) async {
  await tester.pumpWidget(_wrapSection(overrides: _overrides(error)));
  await tester.pumpAndSettle();

  await tester.tap(find.text('Vicente').first);
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextField).last, 'hola');
  await tester.testTextInput.receiveAction(TextInputAction.send);
  await tester.pumpAndSettle();
}

void main() {
  group('ChatDetailPane — el error del envío deja de ser invisible', () {
    testWidgets('permission-denied NO dice "reintentá"', (tester) async {
      await _intentarEnviar(
        tester,
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );

      // Mandar a reintentar contra una denegación de las reglas es mandarlo a
      // repetir algo que va a fallar las próximas cien veces igual.
      expect(find.text('No tenés permiso para escribir en este chat.'),
          findsOneWidget);
      expect(find.text('No pudimos enviar el mensaje. Reintentá.'), findsNothing);
    });

    testWidgets('cualquier otro código sí invita a reintentar', (tester) async {
      await _intentarEnviar(
        tester,
        FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
      );

      // `unavailable` es la caída de red de verdad: acá reintentar sirve.
      expect(
          find.text('No pudimos enviar el mensaje. Reintentá.'), findsOneWidget);
      expect(find.text('No tenés permiso para escribir en este chat.'),
          findsNothing);
    });

    testWidgets('un error que no es de Firebase cae en la rama genérica',
        (tester) async {
      // Sin esto, un `isPermissionDenied` mal escrito —uno que mirara sólo el
      // texto del error, por ejemplo— pasaría los dos tests de arriba.
      await _intentarEnviar(tester, StateError('cualquier otra cosa'));

      expect(
          find.text('No pudimos enviar el mensaje. Reintentá.'), findsOneWidget);
    });

    testWidgets('el composer no se limpia cuando el envío falla',
        (tester) async {
      await _intentarEnviar(
        tester,
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );

      // Borrarle el texto al PF después de un envío fallido le hace perder el
      // mensaje: sólo se limpia en el camino feliz.
      expect(find.text('hola'), findsWidgets);
    });
  });

  // `ChatSectionScreen` REUSA el State del pane cuando el PF cambia de
  // conversación —de eso se ocupa `didUpdateWidget`—, así que `widget.chatId`
  // puede ser otro para cuando el envío responde. Leerlo después del await
  // hace que el diagnóstico mienta con total seguridad.
  //
  // Lo encontró la review de Codex sobre el primer commit de este PR.
  group('ChatDetailPane — el envío en vuelo sobrevive al cambio de chat', () {
    /// Deja un envío colgado en el chat de Vicente y salta al de Mariano.
    /// Devuelve el repo para que el test decida cómo termina ese envío.
    Future<_PendingSendRepository> enviarYCambiarDeChat(
      WidgetTester tester,
    ) async {
      final repo = _PendingSendRepository();
      await tester.pumpWidget(_wrapSection(overrides: [
        currentUidProvider.overrideWithValue(_pfUid),
        chatRepositoryProvider.overrideWithValue(repo),
        chatsForCurrentUserProvider.overrideWith(
          (ref) => Stream<List<Chat>>.value([_stubChat(), _stubChat2()]),
        ),
        userPublicProfileProvider(_athleteUid).overrideWith(
          (ref) => Stream<UserPublicProfile?>.value(_stubPub()),
        ),
        userPublicProfileProvider(_athleteUid2).overrideWith(
          (ref) => Stream<UserPublicProfile?>.value(_stubPub2()),
        ),
        messagesProvider(_chatId).overrideWith(
          (ref) => Stream<List<Message>>.value(const []),
        ),
        messagesProvider(_chatId2).overrideWith(
          (ref) => Stream<List<Message>>.value(const []),
        ),
      ]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Vicente').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'para vicente');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump(); // el envío arranca y queda colgado

      await tester.tap(find.text('Mariano').first);
      // `pump()` y no `pumpAndSettle()`: con el envío en vuelo el composer
      // muestra un indicador de progreso que anima para siempre, así que
      // `pumpAndSettle` se cuelga hasta el timeout. No es el widget: es que
      // no hay nada que "asentar" mientras el spinner gira.
      await tester.pump();
      await tester.pump();
      return repo;
    }

    testWidgets('el cartel no dice "este chat" sobre la conversación nueva',
        (tester) async {
      final repo = await enviarYCambiarDeChat(tester);

      repo.completer.completeError(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
        StackTrace.current,
      );
      await tester.pumpAndSettle();

      // El deíctico "este" señalaría a la conversación de Mariano, donde no se
      // intentó mandar nada. Un error que apunta al chat equivocado es peor
      // que no tener error, que es la razón entera de este PR.
      expect(find.text('No tenés permiso para escribir en este chat.'),
          findsNothing);
      expect(
        find.text(
          'No pudimos enviar el mensaje: no tenés permiso en esa conversación.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'un éxito tardío limpia el composer aunque el PF ya se haya movido',
        (tester) async {
      final repo = await enviarYCambiarDeChat(tester);

      repo.completer.complete();
      await tester.pumpAndSettle();

      // La simetría con el `catch` tienta a guardar también el `clear()` con
      // un `if (widget.chatId == chatIdDelEnvio)`. Sería un error: el composer
      // va con `enabled: !sending`, así que mientras el envío está en vuelo no
      // se puede tipear en ningún lado y NO HAY borrador nuevo que proteger.
      //
      // Lo único que esa guarda lograría es dejar el texto YA ENVIADO cargado
      // en la conversación de Mariano, a un Enter de mandárselo a la persona
      // equivocada. El `_composerCtrl` es uno solo y sobrevive al cambio.
      expect(find.text('para vicente'), findsNothing);
    });
  });
}
