import 'package:cloud_firestore/cloud_firestore.dart'
    show
        CollectionReference,
        DocumentSnapshot,
        FieldValue,
        FirebaseFirestore,
        Query;

import '../domain/chat.dart';
import '../domain/media_type.dart';
import '../domain/message.dart';

/// Repository de chats 1-1 entre PF y athlete. Doc id determinístico
/// (`sortedUids.join('_')`) para que ambos miembros resuelvan al mismo doc
/// sin coordinar.
class ChatRepository {
  ChatRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  /// Preview máximo guardado en `chats.lastMessageText`. Si el mensaje es
  /// más largo se trunca con elipsis Unicode (`…`).
  static const int previewMaxChars = 80;

  /// Default limit para `watchMessages`. Conversaciones MVP son cortas;
  /// paginación real entra cuando crezca.
  static const int defaultMessagesLimit = 50;

  CollectionReference<Map<String, Object?>> get _chats =>
      _firestore.collection('chats');

  CollectionReference<Map<String, Object?>> _messagesOf(String chatId) =>
      _chats.doc(chatId).collection('messages');

  // ─── chatIdFor ──────────────────────────────────────────────────────────
  //
  // Pure helper. Devuelve el doc id determinístico para el par. Orden de
  // los argumentos no importa.

  static String chatIdFor(String uidA, String uidB) {
    if (uidA == uidB) {
      throw ArgumentError.value(
          uidB, 'uidB', 'no se puede chatear con uno mismo');
    }
    final sorted = [uidA, uidB]..sort();
    return sorted.join('_');
  }

  // ─── getOrCreate ────────────────────────────────────────────────────────
  //
  // Idempotente. Si el doc ya existe lo devuelve tal cual; si no, lo crea
  // con createdAt:serverTimestamp + members ordenados.

  Future<Chat> getOrCreate({
    required String selfId,
    required String otherId,
  }) async {
    final id = chatIdFor(selfId, otherId);
    final ref = _chats.doc(id);
    final existing = await ref.get();
    if (existing.exists) {
      return _chatFromDoc(existing)!;
    }
    final members = [selfId, otherId]..sort();
    await ref.set({
      'chatId': id,
      'members': members,
      'createdAt': FieldValue.serverTimestamp(),
    });
    final created = await ref.get();
    return _chatFromDoc(created)!;
  }

  // ─── sendMessage ────────────────────────────────────────────────────────
  //
  // Batch: doc nuevo en messages + update del parent con preview. Atómico
  // para que la lista nunca muestre un preview desincronizado con el último
  // mensaje real.
  //
  // REQ-CHATMEDIA-003/004/005: accepts optional mediaUrl + mediaType.
  // Validation: text non-empty OR (mediaUrl non-null AND mediaType non-null).
  // Preview: caption (truncated 80) ?? '📷 Foto' / '🎥 Video'.

  Future<void> sendMessage({
    required String chatId,
    required String senderId,
    String text = '',
    String? mediaUrl,
    MediaType? mediaType,
  }) async {
    final trimmed = text.trim();

    // REQ-CHATMEDIA-005: at least one of text or mediaUrl must be present.
    if (trimmed.isEmpty && mediaUrl == null) {
      throw ArgumentError(
          'sendMessage: el mensaje debe tener texto o un archivo adjunto.');
    }

    // mediaUrl requires a mediaType to be meaningful.
    if (mediaUrl != null && mediaType == null) {
      throw ArgumentError(
          'sendMessage: mediaType es requerido cuando se adjunta mediaUrl.');
    }

    final batch = _firestore.batch();
    final msgRef = _messagesOf(chatId).doc();

    // Build the message document — omit null optional fields.
    final msgData = <String, Object?>{
      'id': msgRef.id,
      'senderId': senderId,
      'text': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (mediaType != null) 'mediaType': mediaType.toJson(),
    };

    batch.set(msgRef, msgData);
    batch.update(_chats.doc(chatId), {
      'lastMessageAt': FieldValue.serverTimestamp(),
      'lastMessageText': _previewOf(trimmed, mediaType),
      'lastMessageSenderId': senderId,
    });
    await batch.commit();
  }

  // ─── watchMessages ──────────────────────────────────────────────────────
  //
  // Stream ordenado desc por createdAt. El ChatScreen usa ListView.reverse
  // para mostrar el más nuevo al final visualmente sin shifting.

  Stream<List<Message>> watchMessages(
    String chatId, {
    int limit = defaultMessagesLimit,
  }) {
    final Query<Map<String, Object?>> query =
        _messagesOf(chatId).orderBy('createdAt', descending: true).limit(limit);
    return query.snapshots().map((snap) {
      return snap.docs.map(_messageFromDoc).whereType<Message>().toList();
    });
  }

  // ─── watchChatsForUser ──────────────────────────────────────────────────
  //
  // Stream de chats donde el uid es miembro, ordenados por lastMessageAt
  // desc. Nota: Firestore `orderBy('lastMessageAt')` excluye docs sin el
  // campo, así que los chats recién creados (todavía sin mensajes) no
  // aparecen en la lista hasta que tengan al menos un send. Es behavior
  // intencional para MVP — un chat vacío en la lista se ve raro.

  Stream<List<Chat>> watchChatsForUser(String uid) {
    final ordered = _chats
        .where('members', arrayContains: uid)
        .orderBy('lastMessageAt', descending: true);
    return ordered.snapshots().map((snap) {
      return snap.docs.map(_chatFromDoc).whereType<Chat>().toList();
    });
  }

  // ─── Private helpers ────────────────────────────────────────────────────

  Chat? _chatFromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    // createdAt puede llegar como null si justo se acaba de crear y el
    // serverTimestamp todavía no resolvió localmente; en ese caso el get()
    // posterior ya tiene el valor real.
    if (data['createdAt'] == null) return null;
    return Chat.fromJson({...data, 'chatId': snap.id});
  }

  Message? _messageFromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    // Mismo motivo que en _chatFromDoc: el serverTimestamp puede llegar
    // null en el primer snapshot local antes de que el server confirme.
    if (data['createdAt'] == null) return null;
    return Message.fromJson({...data, 'id': snap.id});
  }

  /// Computes the inbox preview string.
  ///
  /// If [text] is non-empty: use text (truncated to [previewMaxChars]).
  /// Else if [mediaType] is image: '📷 Foto'.
  /// Else if [mediaType] is video: '🎥 Video'.
  /// Else: empty string (degenerate fallback, should not happen with valid input).
  String _previewOf(String text, MediaType? mediaType) {
    if (text.isNotEmpty) {
      if (text.length <= previewMaxChars) return text;
      return '${text.substring(0, previewMaxChars)}…';
    }
    return switch (mediaType) {
      MediaType.image => '📷 Foto',
      MediaType.video => '🎥 Video',
      null => '',
    };
  }
}
