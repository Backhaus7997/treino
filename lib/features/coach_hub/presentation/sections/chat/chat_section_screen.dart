import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../../app/theme/tokens/primitives.dart';
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
/// (conversación seleccionada o empty state) se estira al resto. Ambos panes
/// son cards flotantes redondeadas (`_ChatPaneSurface`) sobre el fondo ink
/// del shell — SIN líneas divisorias verticales full-height (rediseño
/// ronda de revisión 2026-07-23: "esa división con líneas" se sentía cruda;
/// la profundidad ahora la da el contraste bgCard/ink + un borde de 1px,
/// nunca un boxShadow — regla dura del design system).
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
    return Padding(
      // Gutter entre el shell (ink) y las cards, y entre las dos cards —
      // reemplaza el `VerticalDivider` full-height anterior.
      padding: const EdgeInsets.all(AppSpacing.s20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _listPaneWidth,
            child: _ChatPaneSurface(
              child: ChatListPane(selectedChatId: selectedChatId),
            ),
          ),
          const SizedBox(width: AppSpacing.s18),
          Expanded(
            child: _ChatPaneSurface(
              // Cross-fade al pasar de "sin selección" a "conversación
              // abierta" (y viceversa). Keyed por presencia de selección,
              // NO por chatId puntual: cambiar de chat A → chat B debe
              // seguir resolviendo vía `didUpdateWidget` de `ChatDetailPane`
              // (sin remount) — si la key incluyera el chatId, cada cambio
              // de conversación abierta forzaría un remount completo.
              child: TreinoStateSwitcher(
                childKey: ValueKey(
                  selectedChatId == null ? 'chat_empty' : 'chat_detail',
                ),
                child: selectedChatId == null
                    ? const ChatEmptyPane()
                    : ChatDetailPane(chatId: selectedChatId),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Superficie flotante compartida por ambos panes del split-pane (lista +
/// detalle): card redondeada `bgCard` + borde sutil, SIN sombra (regla dura
/// del design system — la profundidad la da el contraste bgCard/ink + el
/// borde, nunca un `boxShadow`). Cada pane pinta su propio fondo interno
/// (header/composer en `bgCard`, cuerpo en `bg`) — el `ClipRRect` recorta
/// esos rectángulos internos a las 4 esquinas redondeadas de la card.
class _ChatPaneSurface extends StatelessWidget {
  const _ChatPaneSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        decoration: BoxDecoration(
          color: palette.bgCard,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: child,
      ),
    );
  }
}
