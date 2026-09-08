// El envío del chat del Coach Hub fallaba y no dejaba rastro: el `catch (_)`
// del composer se comía el error entero y el PF sólo veía "Reintentá".
//
// Reintentar es el consejo correcto para una caída de red y el equivocado para
// un `permission-denied`, que va a fallar igual las próximas cien veces. Estos
// tests fijan que las dos ramas se distingan por el CÓDIGO REAL de Firestore y
// no por una sospecha, y que el error llegue a la telemetría en vez de morirse
// adentro del catch.

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

Chat _stubChat() => Chat(
      chatId: _chatId,
      members: const [_pfUid, _athleteUid],
      createdAt: DateTime(2026, 6, 1),
      lastMessageAt: DateTime(2026, 7, 1, 10),
      lastMessageText: 'hola',
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
}
