import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/tokens/tokens.dart';
import '../../../core/widgets/treino_confirm_dialog.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../core/widgets/treino_toast.dart';
import '../../../l10n/app_l10n.dart';
import '../application/chat_providers.dart' show chatRepositoryProvider;

// Acciones de un chat: archivar, desarchivar y eliminar. Las disparan tres
// superficies —el long-press y el swipe de la bandeja, y el ⋮ del chat— y
// todas pasan por acá, así que el texto, el toast y la confirmación son uno.
//
// Las tres son POR USUARIO (`Chat.archivedAt` / `Chat.hiddenBefore`): no
// cambian nada de lo que ve el otro participante.
//
// Cada función lee el repo y el messenger ANTES del primer `await`: la fila
// que la disparó se va de la lista apenas el stream refleja el cambio, y con
// ella su `context` y su `ref`.

/// Archiva el chat para [uid]. Inmediato, con «Deshacer» en el toast.
/// Devuelve `true` si se escribió.
Future<bool> archiveChat(
  BuildContext context,
  WidgetRef ref, {
  required String chatId,
  required String uid,
}) {
  final repo = ref.read(chatRepositoryProvider);
  return _run(
    context,
    () => repo.archive(chatId: chatId, uid: uid),
    done: AppL10n.of(context).chatArchivedToast,
    undo: () => repo.unarchive(chatId: chatId, uid: uid),
  );
}

/// Devuelve el chat a la bandeja. Devuelve `true` si se escribió.
Future<bool> unarchiveChat(
  BuildContext context,
  WidgetRef ref, {
  required String chatId,
  required String uid,
}) {
  final repo = ref.read(chatRepositoryProvider);
  return _run(
    context,
    () => repo.unarchive(chatId: chatId, uid: uid),
    done: AppL10n.of(context).chatUnarchivedToast,
  );
}

/// Elimina el chat para [uid], SIEMPRE con confirmación: es lo único de las
/// tres que no se deshace desde el toast. Devuelve `true` sólo si se
/// confirmó y se escribió.
Future<bool> confirmAndDeleteChat(
  BuildContext context,
  WidgetRef ref, {
  required String chatId,
  required String uid,
}) async {
  final l10n = AppL10n.of(context);
  final repo = ref.read(chatRepositoryProvider);
  final messenger = ScaffoldMessenger.of(context);
  final confirmed = await showTreinoConfirmDialog(
    context,
    title: l10n.chatDeleteConfirmTitle,
    body: l10n.chatDeleteConfirmBody,
    confirmLabel: l10n.commonDelete,
  );
  if (!confirmed) return false;
  return _runOn(
    messenger,
    l10n,
    () => repo.hideForUser(chatId: chatId, uid: uid),
    done: l10n.chatDeletedToast,
  );
}

/// Sheet de acciones de un chat: mismo look que el menú de moderación
/// (`showModerationMenu`).
///
/// [onViewProfile] agrega «Ver perfil» arriba de todo (el ⋮ del chat; en la
/// bandeja la fila ya es la persona). [onLeft] corre cuando el chat dejó de
/// estar donde estaba —archivado, desarchivado o eliminado—, para que el
/// chat abierto pueda volver a la bandeja.
Future<void> showChatActionsSheet(
  BuildContext context,
  WidgetRef ref, {
  required String chatId,
  required String uid,
  required bool archived,
  VoidCallback? onViewProfile,
  VoidCallback? onLeft,
}) async {
  final palette = AppPalette.of(context);
  final l10n = AppL10n.of(context);

  Widget tile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final color = danger ? palette.dangerText : palette.textPrimary;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: GoogleFonts.barlow(
          fontWeight: FontWeight.w400,
          fontSize: AppTextSize.body,
          color: color,
        ),
      ),
      onTap: onTap,
    );
  }

  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: palette.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onViewProfile != null)
            tile(
              icon: TreinoIcon.tabProfile,
              label: l10n.chatActionViewProfile,
              onTap: () {
                Navigator.of(sheetContext).pop();
                onViewProfile();
              },
            ),
          tile(
            icon: TreinoIcon.archive,
            label: archived ? l10n.chatActionUnarchive : l10n.chatActionArchive,
            onTap: () async {
              Navigator.of(sheetContext).pop();
              final pending = archived
                  ? unarchiveChat(context, ref, chatId: chatId, uid: uid)
                  : archiveChat(context, ref, chatId: chatId, uid: uid);
              if (await pending) onLeft?.call();
            },
          ),
          tile(
            icon: TreinoIcon.trash,
            label: l10n.chatActionDelete,
            danger: true,
            onTap: () async {
              Navigator.of(sheetContext).pop();
              final ok = await confirmAndDeleteChat(
                context,
                ref,
                chatId: chatId,
                uid: uid,
              );
              if (ok) onLeft?.call();
            },
          ),
        ],
      ),
    ),
  );
}

Future<bool> _run(
  BuildContext context,
  Future<void> Function() action, {
  required String done,
  Future<void> Function()? undo,
}) =>
    _runOn(
      ScaffoldMessenger.of(context),
      AppL10n.of(context),
      action,
      done: done,
      undo: undo,
    );

Future<bool> _runOn(
  ScaffoldMessengerState messenger,
  AppL10n l10n,
  Future<void> Function() action, {
  required String done,
  Future<void> Function()? undo,
}) async {
  try {
    await action();
  } catch (_) {
    showTreinoToastOn(
      messenger,
      l10n.chatActionError,
      type: TreinoToastType.error,
    );
    return false;
  }
  showTreinoToastOn(
    messenger,
    done,
    type: TreinoToastType.success,
    action: undo == null
        ? null
        : TreinoToastAction(
            label: l10n.chatActionUndo,
            onPressed: () => undo().catchError((Object _) {}),
          ),
  );
  return true;
}
