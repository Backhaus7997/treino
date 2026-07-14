import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../../../app/theme/app_palette.dart';
import '../../../../../chat/application/chat_providers.dart';
import '../../../../../chat/domain/chat.dart';
import '../../../../../profile/application/user_public_profile_providers.dart';
import '../../../../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../chat_section_screen.dart' show selectedChatIdProvider;
import 'avatar_color.dart';

/// Panel izquierdo del split-pane: lista de conversaciones del PF.
///
/// Reusa 100% el data layer mobile (`chatsForCurrentUserProvider` +
/// `userPublicProfileProvider`) — el PF logueado en web ve sus mismos chats
/// que en mobile porque la query Firestore es `chats where members array-
/// contains uid`.
class ChatListPane extends ConsumerStatefulWidget {
  const ChatListPane({super.key, required this.selectedChatId});

  /// chatId actualmente seleccionado, para resaltar la row activa.
  final String? selectedChatId;

  @override
  ConsumerState<ChatListPane> createState() => _ChatListPaneState();
}

class _ChatListPaneState extends ConsumerState<ChatListPane> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Renderiza la lista preservando el ÚLTIMO dato bueno durante reloads o
  /// errores transitorios. Sin esto, al cambiar de chat el StreamProvider
  /// re-emite loading/error por un frame y la lista parpadea a vacío/"no
  /// pudimos cargar" (bug reportado). `valueOrNull` sobrevive esos estados.
  Widget _buildList(
    AsyncValue<List<Chat>> chatsAsync,
    String? uid,
    AppPalette palette,
  ) {
    final chats = chatsAsync.valueOrNull;

    // Solo mostramos loading/error si NUNCA hubo datos (primer load real).
    if (chats == null) {
      if (chatsAsync.isLoading) {
        return Center(child: CircularProgressIndicator(color: palette.accent));
      }
      return _ErrorState();
    }

    if (chats.isEmpty) return const _EmptyListState();
    if (uid == null) return const SizedBox.shrink();

    final filtered = _query.isEmpty
        ? chats
        : chats
            .where(
                (c) => (c.lastMessageText ?? '').toLowerCase().contains(_query))
            .toList();
    if (filtered.isEmpty) return const _NoMatchState();

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final chat = filtered[index];
        return _ChatRow(
          chat: chat,
          currentUid: uid,
          isSelected: chat.chatId == widget.selectedChatId,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final uid = ref.watch(currentUidProvider);
    final chatsAsync = ref.watch(chatsForCurrentUserProvider);

    return Container(
      color: palette.bgCard,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Buscador de conversación (mockup). Filtra por el último mensaje
          // client-side; el nombre del otro user vive en un provider async por
          // fila, así que buscar por nombre requeriría resolverlos todos —
          // fuera de scope de este pulido visual.
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              style:
                  GoogleFonts.barlow(fontSize: 13, color: palette.textPrimary),
              decoration: InputDecoration(
                hintText: 'Buscar conversación', // i18n: Fase W2
                hintStyle:
                    GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
                prefixIcon:
                    Icon(Icons.search, size: 18, color: palette.textMuted),
                isDense: true,
                filled: true,
                fillColor: palette.bg,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: palette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: palette.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: palette.accent),
                ),
              ),
            ),
          ),
          Expanded(
            child: _buildList(chatsAsync, uid, palette),
          ),
        ],
      ),
    );
  }
}

class _ChatRow extends ConsumerWidget {
  const _ChatRow({
    required this.chat,
    required this.currentUid,
    required this.isSelected,
  });

  final Chat chat;
  final String currentUid;
  final bool isSelected;

  /// Resuelve el otro miembro del chat 1:1. Defensivo: si por algún motivo
  /// el chat tiene > 2 members (group chat futuro, no soportado hoy) o solo
  /// 1 (self-chat por bug), devolvemos el primer no-self con fallback al
  /// primer member para nunca crashear el render.
  String _otherUidOf(Chat c, String selfUid) {
    final others = c.members.where((m) => m != selfUid).toList();
    if (others.isNotEmpty) return others.first;
    return c.members.isNotEmpty ? c.members.first : '';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final otherUid = _otherUidOf(chat, currentUid);
    final pubAsync = ref.watch(userPublicProfileProvider(otherUid));
    final hasUnread = chatHasUnread(chat, currentUid);

    return InkWell(
      key: Key('chat_row_${chat.chatId}'),
      onTap: () {
        ref.read(selectedChatIdProvider.notifier).state = chat.chatId;
      },
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? palette.bg : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isSelected ? palette.accent : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 22,
              // Mockup: avatares de color por usuario (inicial en blanco)
              // cuando no hay foto.
              backgroundColor: avatarColorFor(otherUid),
              backgroundImage: pubAsync.maybeWhen(
                data: (p) => (p?.avatarUrl != null && p!.avatarUrl!.isNotEmpty)
                    ? NetworkImage(p.avatarUrl!)
                    : null,
                orElse: () => null,
              ),
              child: pubAsync.maybeWhen(
                data: (p) =>
                    (p?.avatarUrl == null || (p?.avatarUrl ?? '').isEmpty)
                        ? Text(
                            (p?.displayName ?? '?').isNotEmpty
                                ? (p?.displayName ?? '?')[0].toUpperCase()
                                : '?',
                            style: GoogleFonts.barlowCondensed(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          )
                        : null,
                orElse: () => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          pubAsync.maybeWhen(
                            data: (p) => p?.displayName ?? 'Usuario eliminado',
                            orElse: () => '…',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.barlow(
                            fontWeight:
                                hasUnread ? FontWeight.w700 : FontWeight.w600,
                            fontSize: 14,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      if (chat.lastMessageAt != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          _formatTimestamp(chat.lastMessageAt!),
                          style: GoogleFonts.barlow(
                            fontWeight: FontWeight.w400,
                            fontSize: 11,
                            color:
                                hasUnread ? palette.accent : palette.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          (chat.lastMessageText ?? '').isEmpty
                              ? 'Sin mensajes todavía' // i18n: Fase W2
                              : chat.lastMessageText!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.barlow(
                            fontWeight:
                                hasUnread ? FontWeight.w600 : FontWeight.w400,
                            fontSize: 12,
                            color: hasUnread
                                ? palette.textPrimary
                                : palette.textMuted,
                          ),
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: 6),
                        // Mockup: badge circular mint con "●" (el conteo real
                        // por-chat no está en el modelo hoy; se muestra el
                        // indicador de no-leído como badge, no un puntito).
                        Container(
                          constraints: const BoxConstraints(minWidth: 18),
                          height: 18,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          decoration: BoxDecoration(
                            color: palette.accent,
                            borderRadius: BorderRadius.circular(9999),
                          ),
                          child: Icon(
                            Icons.circle,
                            size: 6,
                            color: palette.bg,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hoy → solo hora `HH:mm`. Esta semana → día abreviado `lun/mar/...`.
  /// Más viejo → `dd/MM`. Sin años porque cabe siempre en ~5 chars.
  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final local = dt.toLocal();
    final isToday = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (isToday) return DateFormat('HH:mm').format(local);
    final daysAgo = now.difference(local).inDays;
    if (daysAgo < 7) return DateFormat('E', 'es').format(local).toLowerCase();
    return DateFormat('dd/MM').format(local);
  }
}

class _EmptyListState extends StatelessWidget {
  const _EmptyListState();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          'Todavía no tenés conversaciones.\nLos chats aparecen cuando un alumno te escribe.', // i18n: Fase W2
          textAlign: TextAlign.center,
          style: GoogleFonts.barlow(
            fontWeight: FontWeight.w400,
            fontSize: 13,
            color: palette.textMuted,
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Text(
        'No pudimos cargar tus chats.', // i18n: Fase W2
        style: GoogleFonts.barlow(
          fontWeight: FontWeight.w400,
          fontSize: 13,
          color: palette.textMuted,
        ),
      ),
    );
  }
}

class _NoMatchState extends StatelessWidget {
  const _NoMatchState();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Text(
        'Sin resultados.', // i18n: Fase W2
        style: GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
      ),
    );
  }
}
