import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../coach/domain/trainer_link.dart';
import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../data/chat_repository.dart';
import '../domain/chat.dart';
import '../domain/message.dart';

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(firestore: ref.watch(firestoreProvider)),
);

/// Stream de chats del usuario actual, ordenados por lastMessageAt desc.
/// Lo consume ChatListScreen.
final chatsForCurrentUserProvider =
    StreamProvider.autoDispose<List<Chat>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.read(chatRepositoryProvider).watchChatsForUser(uid);
});

/// Stream de mensajes de un chat, ordenados por createdAt desc (más nuevo
/// primero). El ChatScreen usa `ListView.reverse: true` para que se vea más
/// nuevo abajo sin shifting.
final messagesProvider =
    StreamProvider.autoDispose.family<List<Message>, String>(
  (ref, chatId) {
    if (chatId.isEmpty) return Stream.value(const []);
    return ref.read(chatRepositoryProvider).watchMessages(chatId);
  },
);

/// Resuelve (creando si hace falta) el Chat asociado a un TrainerLink
/// activo. Usado por el entry point "MENSAJE" (Fase B de Etapa 5).
final chatForLinkProvider =
    FutureProvider.autoDispose.family<Chat, TrainerLink>((ref, link) async {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    throw StateError('No hay usuario autenticado');
  }
  final otherId = uid == link.athleteId ? link.trainerId : link.athleteId;
  return ref
      .read(chatRepositoryProvider)
      .getOrCreate(selfId: uid, otherId: otherId);
});
