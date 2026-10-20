import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../app/theme/app_palette.dart';
import '../../l10n/app_l10n.dart';

/// "¿Descartar cambios?" — la confirmación al salir de un formulario con datos
/// cargados sin guardar (#1502).
///
/// Es el mismo diálogo del editor de planes (`routine_editor_screen.dart`,
/// `_confirmDiscard`), extraído para que los demás formularios no tengan que
/// copiarlo: mismo copy (`routineEditorDiscard*`, que a pesar del prefijo es
/// genérico), mismo estilo. Devuelve `true` si el usuario eligió descartar y
/// `false` si canceló o cerró el diálogo.
///
/// Uso típico, junto a un `PopScope(canPop: !dirty)`:
///
/// ```dart
/// if (!dirty) { leave(); return; }
/// if (await confirmDiscardChanges(context) && mounted) leave();
/// ```
Future<bool> confirmDiscardChanges(BuildContext context) async {
  final l10n = AppL10n.of(context);
  final discard = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final palette = AppPalette.of(ctx);
      return AlertDialog(
        backgroundColor: palette.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: Text(
          l10n.routineEditorDiscardTitle,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: AppTextSize.title,
            color: palette.textPrimary,
          ),
        ),
        content: Text(
          l10n.routineEditorDiscardBody,
          style: GoogleFonts.barlow(
            fontSize: AppTextSize.body,
            color: palette.textMuted,
          ),
        ),
        actions: [
          OutlinedButton(
            key: const Key('discard_changes_cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              l10n.commonCancel,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: AppTextSize.body,
                color: palette.textPrimary,
              ),
            ),
          ),
          ElevatedButton(
            key: const Key('discard_changes_confirm'),
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.highlight,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              l10n.routineEditorDiscardConfirm,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: AppTextSize.body,
                color: palette.bg,
              ),
            ),
          ),
        ],
      );
    },
  );
  return discard ?? false;
}
