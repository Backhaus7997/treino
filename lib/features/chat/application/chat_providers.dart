import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../coach/domain/trainer_link.dart';
import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../data/chat_media_upload_service.dart';
import '../data/chat_media_upload_service_web.dart';
import '../data/chat_repository.dart';
import '../domain/chat.dart';
import '../domain/message.dart';

// ─── Pure helpers ──────────────────────────────────────────────────────────

/// Returns true when [c] has an unread message for [uid].
///
/// Logic:
/// - No lastMessageAt → no message at all → read.
/// - Sender is [uid] → own message → read.
/// - lastRead[uid] absent → never read → unread.
/// - lastMessageAt strictly after lastRead[uid] → unread.
/// - equal or before → read.
bool chatHasUnread(Chat c, String uid) {
  final lastMessageAt = c.lastMessageAt;
  if (lastMessageAt == null) return false;
  if (c.lastMessageSenderId == uid) return false;
  final readAt = c.lastRead?[uid];
  if (readAt == null) return true;
  return lastMessageAt.isAfter(readAt);
}

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(firestore: ref.watch(firestoreProvider)),
);

/// Resolves the platform-appropriate media upload service.
///
/// - Native (iOS/Android/desktop) → [ChatMediaUploadServiceMobile] uses
///   `dart:io.File` + `putFile`.
/// - Web → [ChatMediaUploadServiceWeb] uses `XFile.readAsBytes()` +
///   `putData()` because `dart:io` does not compile in the web toolchain.
///
/// Callers depend only on the abstract [ChatMediaUploadService], so switching
/// impls at build-time via `kIsWeb` is transparent to the chat UI code.
final chatMediaUploadServiceProvider = Provider<ChatMediaUploadService>(
  (ref) =>
      kIsWeb ? ChatMediaUploadServiceWeb() : ChatMediaUploadServiceMobile(),
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

/// Resuelve el [Chat] entre el usuario actual y [otherUid], creándolo si no
/// existe. Equivalente a [chatForLinkProvider] pero keyed por uid plano —
/// útil cuando el caller ya tiene el uid del otro a mano (Alumno detalle del
/// Coach Hub web) y no necesita traer el [TrainerLink] solo para inferirlo.
final chatForOtherUidProvider =
    FutureProvider.autoDispose.family<Chat, String>((ref, otherUid) async {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) {
    throw StateError('No hay usuario autenticado');
  }
  return ref
      .read(chatRepositoryProvider)
      .getOrCreate(selfId: uid, otherId: otherUid);
});

/// Whether the current user has an unread message from a specific other user.
///
/// Keyed by [otherUid]. Derives from the live [chatsForCurrentUserProvider]
/// stream — zero new Firestore listeners. Returns false when uid is null, the
/// stream is not in data state, or no chat with [otherUid] exists.
final hasUnreadFromProvider =
    Provider.autoDispose.family<bool, String>((ref, otherUid) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return false;
  return ref.watch(chatsForCurrentUserProvider).maybeWhen(
        data: (chats) {
          for (final chat in chats) {
            if (chat.members.contains(otherUid)) {
              return chatHasUnread(chat, uid);
            }
          }
          return false;
        },
        orElse: () => false,
      );
});

/// Count of unread chats for the current user.
///
/// Derives from the existing [chatsForCurrentUserProvider] stream — zero new
/// Firestore listeners. Returns 0 when uid is null or the stream is in
/// loading/error state so consumers never render stale counts.
final totalUnreadCountProvider = Provider.autoDispose<int>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return 0;
  return ref.watch(chatsForCurrentUserProvider).maybeWhen(
        data: (chats) => chats.where((c) => chatHasUnread(c, uid)).length,
        orElse: () => 0,
      );
});
