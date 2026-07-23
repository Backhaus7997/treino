import 'package:cloud_firestore/cloud_firestore.dart'
    show
        CollectionReference,
        DocumentSnapshot,
        FieldValue,
        FirebaseFirestore,
        Query,
        Timestamp;

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
  //
  // #501: nunca desreferencia con `!`. `createdAt` es un serverTimestamp y
  // puede llegar sin resolver — ver [_chatFromDocOrPending].

  Future<Chat> getOrCreate({
    required String selfId,
    required String otherId,
  }) async {
    final id = chatIdFor(selfId, otherId);
    final ref = _chats.doc(id);
    final members = [selfId, otherId]..sort();
    final existing = await ref.get();
    if (existing.exists) {
      return _chatFromDocOrPending(existing, membersFallback: members);
    }
    // QA-CHAT-004: firestore.rules only allows the chat when the two members
    // have a real relationship. A friendship is checked by the doc id; a
    // coach↔athlete chat instead needs the id of their active trainer_link
    // stamped on the doc so the rule can verify it. Resolve it once, on create.
    final linkId = await _activeLinkIdBetween(selfId, otherId);
    await ref.set({
      'chatId': id,
      'members': members,
      'createdAt': FieldValue.serverTimestamp(),
      if (linkId != null) 'linkId': linkId,
    });
    final created = await ref.get();
    return _chatFromDocOrPending(created, membersFallback: members);
  }

  /// Returns the id of the active [TrainerLink] between [self] and [other], or
  /// null if there is none. Queries are self-constrained (athleteId/trainerId ==
  /// self) so they satisfy the trainer_links read rule; status and the other
  /// member are filtered in memory (mirrors TrainerLinkRepository's approach,
  /// so no composite index is needed).
  Future<String?> _activeLinkIdBetween(String self, String other) async {
    Future<String?> scan(Query<Map<String, dynamic>> query) async {
      final snap = await query.get();
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['status'] != 'active') continue;
        final trainerId = data['trainerId'] as String?;
        final athleteId = data['athleteId'] as String?;
        if ((trainerId == self && athleteId == other) ||
            (trainerId == other && athleteId == self)) {
          return doc.id;
        }
      }
      return null;
    }

    final links = _firestore.collection('trainer_links');
    return await scan(links.where('athleteId', isEqualTo: self)) ??
        await scan(links.where('trainerId', isEqualTo: self));
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

  // ─── markAsRead ─────────────────────────────────────────────────────────
  //
  // Writes only the caller's key in the lastRead map using a dotted-path
  // update — Firestore merges only that key, leaving sibling keys intact.

  Future<void> markAsRead({
    required String chatId,
    required String uid,
  }) =>
      _chats
          .doc(chatId)
          .update({'lastRead.$uid': FieldValue.serverTimestamp()});

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

  /// Variante one-shot de [_chatFromDoc] que NUNCA devuelve null.
  ///
  /// #501: `createdAt` es un serverTimestamp y queda en null en la cache local
  /// hasta que el server acusa recibo del write — offline eso puede no pasar
  /// en toda la sesión. Los streams se dan el lujo de descartar ese doc
  /// (`whereType`) porque el próximo snapshot lo trae resuelto; [getOrCreate]
  /// es one-shot y no tiene próximo snapshot: si descarta, el usuario se queda
  /// sin chat ("no pudimos abrir el chat") por un campo que ni se renderiza.
  ///
  /// Por eso el pending se degrada a un Chat provisional: mismos datos del
  /// doc, con `createdAt` aproximado por el reloj local. Lo que el caller
  /// necesita es el `chatId` (determinístico, ya lo tenemos) para abrir la
  /// pantalla; el valor real del server llega en la próxima lectura. No se
  /// espera ni se reintenta a propósito: offline no hay nada que esperar.
  Chat _chatFromDocOrPending(
    DocumentSnapshot<Map<String, Object?>> snap, {
    required List<String> membersFallback,
  }) {
    final resolved = _chatFromDoc(snap);
    if (resolved != null) return resolved;
    final data = snap.data() ?? const <String, Object?>{};
    return Chat.fromJson({
      ...data,
      'chatId': snap.id,
      'members': data['members'] ?? membersFallback,
      'createdAt': Timestamp.fromDate(DateTime.now().toUtc()),
    });
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
