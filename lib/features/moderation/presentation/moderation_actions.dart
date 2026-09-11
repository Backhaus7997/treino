import 'package:flutter/material.dart';
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
                fontSize: 14,
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
          ListTile(
            leading: Icon(TreinoIcon.block, color: palette.danger),
            title: Text(
              l10n.moderationBlockAction,
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w400,
                fontSize: 14,
                color: palette.danger,
              ),
            ),
            onTap: () {
              Navigator.of(sheetContext).pop();
              blockUser(
                context,
                ref,
                targetUid: targetOwnerUid,
                targetDisplayName: targetOwnerDisplayName,
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
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.moderationReportSuccess)));
  } catch (_) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.moderationReportError)));
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
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(l10n.moderationBlockSuccess(targetDisplayName)),
              ),
            );
        } catch (_) {
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: Text(l10n.moderationBlockError)),
            );
        }
      },
    ),
  );
}
