import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final selectedChatId = ref.watch(selectedChatIdProvider);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _listPaneWidth,
          child: ChatListPane(selectedChatId: selectedChatId),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: selectedChatId == null
              ? const ChatEmptyPane()
              : ChatDetailPane(chatId: selectedChatId),
        ),
      ],
    );
  }
}
