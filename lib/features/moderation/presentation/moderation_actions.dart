import 'package:flutter/material.dart';
import '../../../../app/theme/tokens/primitives.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../application/moderation_providers.dart';
import '../domain/report_target_kind.dart';
import 'widgets/block_confirmation_sheet.dart';
import 'widgets/report_reason_sheet.dart';
import 'package:treino/core/widgets/treino_toast.dart';

/// Único punto de orquestación de las acciones de moderación (reportar,
/// bloquear), compartido por los cuatro call sites de la feature: `PostCard`,
/// la burbuja de chat, `ReviewTile` y `PublicProfileScreen`. Ninguno de esos
/// widgets llama a un repositorio directamente — todos pasan por acá, así
/// que el flujo (sheet → write → snackbar de éxito/error) vive en un solo
/// lugar en vez de cuatro copias divergentes.
///
/// Mismo look que el menú "Editar/Eliminar" de `PostCard._showPostMenu`:
/// `showModalBottomSheet` con `backgroundColor: palette.bgCard` y esquinas
/// `AppRadius.lg` arriba (`public_profile_follow_button.dart` usa el mismo
/// shape para `UnfriendConfirmationSheet`).

/// Menú "Reportar / Bloquear" para contenido de OTRA persona.
///
/// [targetOwnerUid] hace doble uso: es el `targetOwnerUid` del reporte Y el
/// uid a bloquear. Vale para los cuatro targets de la taxonomía — el dueño
/// del contenido reportado es siempre la persona a la que tendría sentido
/// bloquear (autor del post/review, o el perfil mismo).
///
/// Si esa persona YA está bloqueada, el segundo ítem es «Desbloquear» (#1698:
/// bloquear no tenía vuelta). Se resuelve con un `Consumer` dentro del sheet y
/// no con un `ref.read` al abrirlo: [myBlockedUidsProvider] es `autoDispose` y,
/// desde un call site que no lo observa (p. ej. `ReviewTile`), un `read` en
/// frío daría `[]` y ofrecería «Bloquear» sobre alguien ya bloqueado.
Future<void> showModerationMenu(
  BuildContext context,
  WidgetRef ref, {
  required ReportTargetKind targetKind,
  required String targetId,
  required String targetOwnerUid,
  required String targetOwnerDisplayName,
}) async {
  final palette = AppPalette.of(context);
  final l10n = AppL10n.of(context);

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
          ListTile(
            leading: Icon(TreinoIcon.report, color: palette.textPrimary),
            title: Text(
              l10n.moderationReportAction,
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w400,
                fontSize: AppTextSize.body,
                color: palette.textPrimary,
              ),
            ),
            onTap: () {
              Navigator.of(sheetContext).pop();
              reportContent(
                context,
                ref,
                targetKind: targetKind,
                targetId: targetId,
                targetOwnerUid: targetOwnerUid,
              );
            },
          ),
          Consumer(
            builder: (_, sheetRef, __) {
              final yaBloqueado = sheetRef
                  .watch(myBlockedUidsProvider)
                  .contains(targetOwnerUid);
              // Deshacer no es destructivo: color de texto normal, no el rojo
              // de «Bloquear».
              return ListTile(
                leading: Icon(
                  TreinoIcon.block,
                  color: yaBloqueado ? palette.textPrimary : palette.dangerText,
                ),
                title: Text(
                  yaBloqueado
                      ? l10n.moderationUnblockAction
                      : l10n.moderationBlockAction,
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: AppTextSize.body,
                    color:
                        yaBloqueado ? palette.textPrimary : palette.dangerText,
                  ),
                ),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  if (yaBloqueado) {
                    unblockUser(
                      context,
                      ref,
                      targetUid: targetOwnerUid,
                      targetDisplayName: targetOwnerDisplayName,
                    );
                  } else {
                    blockUser(
                      context,
                      ref,
                      targetUid: targetOwnerUid,
                      targetDisplayName: targetOwnerDisplayName,
                    );
                  }
                },
              );
            },
          ),
        ],
      ),
    ),
  );
}

/// Abre el sheet de motivos y, si se confirma, manda el reporte.
///
/// Usado directamente (sin pasar por [showModerationMenu]) por la burbuja de
/// chat: ahí sólo hay UNA acción posible, así que el long-press abre este
/// sheet de una, sin el menú intermedio.
Future<void> reportContent(
  BuildContext context,
  WidgetRef ref, {
  required ReportTargetKind targetKind,
  required String targetId,
  required String targetOwnerUid,
}) async {
  final reporterUid = ref.read(currentUidProvider);
  if (reporterUid == null) return;

  final palette = AppPalette.of(context);
  final l10n = AppL10n.of(context);
  final messenger = ScaffoldMessenger.of(context);

  final submission = await showModalBottomSheet<ReportSubmission>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: palette.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (_) => const ReportReasonSheet(),
  );
  if (submission == null) return; // El usuario canceló — sin write.

  try {
    await ref.read(reportRepositoryProvider).report(
          reporterUid: reporterUid,
          targetKind: targetKind,
          targetId: targetId,
          targetOwnerUid: targetOwnerUid,
          reason: submission.reason,
          detail: submission.detail,
        );
    showTreinoToastOn(
      messenger,
      l10n.moderationReportSuccess,
      type: TreinoToastType.success,
    );
  } catch (_) {
    showTreinoToastOn(
      messenger,
      l10n.moderationReportError,
      type: TreinoToastType.error,
    );
  }
}

/// Abre la confirmación y, si se confirma, bloquea a [targetUid].
Future<void> blockUser(
  BuildContext context,
  WidgetRef ref, {
  required String targetUid,
  required String targetDisplayName,
}) async {
  final blockerUid = ref.read(currentUidProvider);
  if (blockerUid == null) return;

  final palette = AppPalette.of(context);
  final l10n = AppL10n.of(context);
  final messenger = ScaffoldMessenger.of(context);

  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    backgroundColor: palette.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (_) => BlockConfirmationSheet(
      targetDisplayName: targetDisplayName,
      onConfirm: () async {
        try {
          await ref.read(blockRepositoryProvider).block(blockerUid, targetUid);
          showTreinoToastOn(
            messenger,
            l10n.moderationBlockSuccess(targetDisplayName),
            type: TreinoToastType.success,
          );
        } catch (_) {
          showTreinoToastOn(
            messenger,
            l10n.moderationBlockError,
            type: TreinoToastType.error,
          );
        }
      },
    ),
  );
}

/// Desbloquea a [targetUid]. Sin confirmación, a propósito: es el camino de
/// vuelta, no destruye nada y se re-bloquea en dos toques — al revés que
/// [blockUser], que sí confirma porque borra los follows en las dos
/// direcciones. **Desbloquear no los restaura**: cada uno vuelve a seguir al
/// otro si quiere (el trigger `removeFollowEdgesOnBlock` corre sólo al crear).
///
/// Devuelve `true` si se escribió. Lo comparten el menú de moderación, el aviso
/// del chat y la lista de bloqueados, así que el toast es uno solo.
Future<bool> unblockUser(
  BuildContext context,
  WidgetRef ref, {
  required String targetUid,
  required String targetDisplayName,
}) async {
  final blockerUid = ref.read(currentUidProvider);
  if (blockerUid == null) return false;

  final l10n = AppL10n.of(context);
  final messenger = ScaffoldMessenger.of(context);
  // Antes del `await`: quien disparó esto puede irse de pantalla apenas el
  // stream de bloqueados refleja el cambio, y con él su `ref`.
  final repo = ref.read(blockRepositoryProvider);

  try {
    await repo.unblock(blockerUid, targetUid);
    showTreinoToastOn(
      messenger,
      l10n.moderationUnblockSuccess(targetDisplayName),
      type: TreinoToastType.success,
    );
    return true;
  } catch (_) {
    showTreinoToastOn(
      messenger,
      l10n.moderationUnblockError,
      type: TreinoToastType.error,
    );
    return false;
  }
}
