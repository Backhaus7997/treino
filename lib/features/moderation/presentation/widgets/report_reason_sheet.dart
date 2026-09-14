import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/motion/treino_fade_slide_in.dart';
import '../../../../core/widgets/motion/treino_tappable.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../domain/report_reason.dart';

/// Resultado que devuelve [ReportReasonSheet] al confirmar. `null` (el sheet
/// descartado) significa "el usuario se arrepintió" — [ModerationActions]
/// no manda ningún write en ese caso.
class ReportSubmission {
  const ReportSubmission({required this.reason, this.detail});

  final ReportReason reason;

  /// Texto libre opcional, ya recortado y `null` si quedó vacío.
  final String? detail;
}

/// Sheet de reporte: elegí UN motivo de la taxonomía + detalle opcional.
///
/// Widget "tonto" a propósito — no llama a ningún repositorio ni conoce el
/// `targetKind`/`targetId` que se está reportando. Sólo junta la elección del
/// usuario y la devuelve por `Navigator.pop`; quien orquesta el write es
/// `ModerationActions.reportContent` (`moderation_actions.dart`), que es el
/// único punto compartido por los cuatro call sites (post, mensaje, review,
/// perfil).
class ReportReasonSheet extends StatefulWidget {
  const ReportReasonSheet({super.key});

  @override
  State<ReportReasonSheet> createState() => _ReportReasonSheetState();
}

class _ReportReasonSheetState extends State<ReportReasonSheet> {
  ReportReason? _selected;
  final _detailController = TextEditingController();

  @override
  void dispose() {
    _detailController.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _selected;
    if (reason == null) return;
    final detail = _detailController.text.trim();
    Navigator.of(context).pop(
      ReportSubmission(reason: reason, detail: detail.isEmpty ? null : detail),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final canSubmit = _selected != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + bottomInset),
      child: TreinoFadeSlideIn(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                l10n.moderationReportSheetTitle,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: AppTextSize.title,
                  color: palette.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final reason in ReportReason.values)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ReasonRow(
                            label: _reasonLabel(l10n, reason),
                            selected: _selected == reason,
                            onTap: () => setState(() => _selected = reason),
                          ),
                        ),
                      const SizedBox(height: 8),
                      // Mismo patrón que `_Composer` del chat
                      // (chat_screen.dart): el tema fuerza `filled: true` en
                      // TODO InputDecoration, así que un TextField SIN
                      // Container propio pinta una banda oscura detrás. Acá
                      // el Container es el dueño del fondo y el
                      // InputDecoration se apaga con `border: InputBorder.none`.
                      Container(
                        decoration: BoxDecoration(
                          color: palette.bgCard,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(color: palette.border),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: TextField(
                          controller: _detailController,
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontSize: AppTextSize.body,
                          ),
                          maxLines: 3,
                          minLines: 1,
                          maxLength: 1000,
                          decoration: InputDecoration(
                            hintText: l10n.moderationReportDetailHint,
                            hintStyle: TextStyle(color: palette.textMuted),
                            border: InputBorder.none,
                            isCollapsed: true,
                            counterStyle: TextStyle(color: palette.textMuted),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _SheetButton(
                      label: l10n.moderationReportCancel,
                      bg: Colors.transparent,
                      borderColor: palette.border,
                      textColor: palette.textPrimary,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Opacity(
                      opacity: canSubmit ? 1.0 : 0.5,
                      child: _SheetButton(
                        label: l10n.moderationReportSubmit,
                        bg: palette.accent,
                        borderColor: palette.accent,
                        textColor: TreinoButtonTokens.foreground(context),
                        onPressed: canSubmit ? _submit : null,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _reasonLabel(AppL10n l10n, ReportReason reason) => switch (reason) {
      ReportReason.harassment => l10n.moderationReportReasonHarassment,
      ReportReason.sexualContent => l10n.moderationReportReasonSexualContent,
      ReportReason.violenceOrSelfHarm =>
        l10n.moderationReportReasonViolenceOrSelfHarm,
      ReportReason.dangerousHealthAdvice =>
        l10n.moderationReportReasonDangerousHealthAdvice,
      ReportReason.impersonation => l10n.moderationReportReasonImpersonation,
      ReportReason.spam => l10n.moderationReportReasonSpam,
      ReportReason.thirdPartyData => l10n.moderationReportReasonThirdPartyData,
      ReportReason.intellectualProperty =>
        l10n.moderationReportReasonIntellectualProperty,
      ReportReason.other => l10n.moderationReportReasonOther,
    };

// ---------------------------------------------------------------------------
// Private widgets
// ---------------------------------------------------------------------------

class _ReasonRow extends StatelessWidget {
  const _ReasonRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: TreinoTappable(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: selected
                  ? palette.accent.withValues(alpha: 0.12)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: selected ? palette.accent : palette.border,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.barlow(
                      fontSize: AppTextSize.body,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? palette.accent : palette.textPrimary,
                    ),
                  ),
                ),
                if (selected)
                  Icon(TreinoIcon.checkCircleFill,
                      size: 18, color: palette.accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.bg,
    required this.borderColor,
    required this.textColor,
    required this.onPressed,
  });

  final String label;
  final Color bg;
  final Color borderColor;
  final Color textColor;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TreinoTappable(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: borderColor),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: AppTextSize.bodyDense,
              letterSpacing: 1.0,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}
