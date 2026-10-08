import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../chat/application/chat_providers.dart'
    show chatsForCurrentUserProvider;
import '../../../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../../../../core/widgets/motion/treino_state_switcher.dart';
import 'widgets/chat_detail_pane.dart';
import 'widgets/chat_empty_pane.dart';
import 'widgets/chat_list_pane.dart';

/// State global del chat web: chat seleccionado (o `null` si nada elegido).
///
/// V1 usa un [StateProvider] simple. Si más adelante queremos URL-driven
/// (e.g. `/coach/chat?id=xyz` para que el PF copie/comparta links a
/// conversaciones), refactorizamos a query params + `addPostFrameCallback`.
/// Por ahora el sidebar persistente del Coach Hub no se beneficia de URLs
/// dentro de `/chat` — la fricción extra del routing no aporta.
final selectedChatIdProvider = StateProvider<String?>((ref) => null);

/// Pantalla principal del Chat web — split-pane WhatsApp Web style.
///
/// Layout: el panel izquierdo (lista de conversaciones) tiene ancho fijo
/// confortable para nombres + último mensaje + timestamp; el derecho
/// (conversación seleccionada o empty state) se estira al resto.
///
/// V1 = solo texto (decisión 2026-06-30): el composer tiene un botón
/// "Adjuntar" deshabilitado con tooltip "Próximamente" para señalar la
/// intención. La V2 con foto/video viene en un PR aparte y requiere refactor
/// del [ChatMediaUploadService] (`dart:io` → Web File API adapter) — ver
/// follow-up en el backlog.
class ChatSectionScreen extends ConsumerWidget {
  const ChatSectionScreen({super.key});

  /// Ancho fijo del panel izquierdo en pixels. Suficiente para mostrar
  /// nombre + último mensaje + timestamp sin truncar en la mayoría de los
  /// casos comunes; el resto del viewport queda para la conversación.
  static const double _listPaneWidth = 360;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final selectedChatId = ref.watch(selectedChatIdProvider);
    // El uid del interlocutor, resuelto ACÁ y pasado al pane.
    //
    // `ChatDetailPane` acepta `peerUid` para arrancar en caliente y no
    // mostrar «Usuario eliminado» mientras resuelve el nombre. El parámetro
    // existía, estaba cableado adentro y lo cubrían siete tests — y ninguna
    // pantalla se lo pasaba: su único consumidor era un modal que se sacó.
    //
    // Sale de los mismos datos que ya usa la lista de la izquierda
    // (`chatsForCurrentUserProvider`), así que no cuesta una lectura nueva.
    final peerUid = _peerUidDe(ref, selectedChatId);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _listPaneWidth,
          child: ChatListPane(selectedChatId: selectedChatId),
        ),
        VerticalDivider(width: 1, color: palette.border),
        Expanded(
          child: TreinoStateSwitcher(
            // ValueKey(selectedChatId == null), NO ValueKey(selectedChatId):
            // la key solo debe diferenciar empty↔detail (el momento
            // significativo que amerita cross-fade). Si la key varía en
            // CADA cambio de chat, AnimatedSwitcher desmonta el
            // ChatDetailPane viejo y monta uno nuevo — pierde el draft del
            // composer y rompe la invariante del issue #435 (el adjunto en
            // vuelo debe aterrizar en el chat donde el PF lo eligió; con
            // remount, el guard `!mounted` lo descarta en silencio). Cambiar
            // de chat→chat debe quedar in-place, sin remount, como en main.
            childKey: ValueKey(selectedChatId == null),
            child: selectedChatId == null
                ? const ChatEmptyPane()
                : ChatDetailPane(
                    chatId: selectedChatId,
                    peerUid: peerUid,
                  ),
          ),
        ),
      ],
    );
  }

  /// El otro miembro de [chatId], o `null` si todavía no hay chats cargados.
  ///
  /// Misma regla que la lista (`_otherUidOf`): el primer miembro que no soy
  /// yo, con fallback al primero para no romper el render si un chat quedara
  /// con un solo miembro.
  String? _peerUidDe(WidgetRef ref, String? chatId) {
    if (chatId == null) return null;
    final selfUid = ref.watch(currentUidProvider);
    if (selfUid == null) return null;
    final chats = ref.watch(chatsForCurrentUserProvider).valueOrNull;
    if (chats == null) return null;
    for (final c in chats) {
      if (c.chatId != chatId) continue;
      final otros = c.members.where((m) => m != selfUid);
      if (otros.isNotEmpty) return otros.first;
      return c.members.isNotEmpty ? c.members.first : null;
    }
    return null;
  }
}
