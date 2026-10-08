import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/features/chat/application/chat_providers.dart';

import 'chat_section_screen.dart' show selectedChatIdProvider;

/// Resuelve (o crea) el chat 1-1 con [athleteId] y **navega al Chat** del
/// Coach Hub con la conversación ya seleccionada.
///
/// Vivía adentro de una fila del roster (`_RowActions._openChat`), donde no la
/// podía usar nadie más. El header de la ficha del alumno tenía su propio
/// botón de chat que abría un `Dialog` con la conversación adentro: el PF lo
/// tocaba esperando ir al chat y se quedaba en un modal. «Si toco el chat que
/// me redirija al chat directamente».
///
/// El router se captura ANTES del `await` a propósito. Las filas del roster se
/// rebuildean por sus streams y el `context` puede morir mientras
/// `getOrCreate` resuelve; con un `if (!context.mounted) return` la navegación
/// se perdía en silencio. Ese bug ya se pagó una vez en revisión en vivo, y
/// mover la función sin traerse el motivo lo habría reintroducido.
Future<void> abrirChatConAlumno(
  BuildContext context,
  WidgetRef ref,
  String athleteId,
) async {
  final router = GoRouter.of(context);
  final chat = await ref.read(chatForOtherUidProvider(athleteId).future);
  ref.read(selectedChatIdProvider.notifier).state = chat.chatId;
  router.go('/chat');
}
