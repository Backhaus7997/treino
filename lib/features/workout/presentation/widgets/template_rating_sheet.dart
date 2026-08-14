import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../auth/application/auth_providers.dart';
import '../../../reviews/presentation/widgets/star_rating_input.dart';
import '../../application/routine_providers.dart';
import '../../domain/template_rating.dart';

/// Opens the rate-a-template sheet. Mirrors `ReviewBottomSheet`'s shape:
/// stars + optional comment + cancel/submit.
Future<void> showTemplateRatingSheet(
  BuildContext context, {
  required String routineId,
  TemplateRating? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppPalette.of(context).bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (_) => TemplateRatingSheet(
      routineId: routineId,
      existing: existing,
    ),
  );
}

/// Star + comment editor for a community template rating.
///
/// Submitting upserts `routines/{routineId}/ratings/{myUid}`; the Cloud
/// Function recomputes the template's average, and the detail screen's
/// routine stream picks it up on its own.
class TemplateRatingSheet extends ConsumerStatefulWidget {
  const TemplateRatingSheet({
    required this.routineId,
    this.existing,
    super.key,
  });

  final String routineId;

  /// Pre-populates the sheet when editing my existing rating.
  final TemplateRating? existing;

  @override
  ConsumerState<TemplateRatingSheet> createState() =>
      _TemplateRatingSheetState();
}

class _TemplateRatingSheetState extends ConsumerState<TemplateRatingSheet> {
  late int _rating;
  late TextEditingController _commentController;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _rating = widget.existing?.rating ?? 0;
    _commentController =
        TextEditingController(text: widget.existing?.comment ?? '');
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _onSubmit(String uid) async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    setState(() => _submitting = true);
    final comment = _commentController.text.trim();
    // `createdAt` is preserved by the repository on edits (the Firestore rule
    // pins it), so sending "now" on both is correct for create AND edit.
    final now = DateTime.now();
    try {
      await ref.read(routineRepositoryProvider).upsertTemplateRating(
            routineId: widget.routineId,
            rating: TemplateRating(
              userId: uid,
              rating: _rating,
              comment: comment.isEmpty ? null : comment,
              createdAt: now,
              updatedAt: now,
            ),
          );
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.templateRatingSheetSuccess)),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.templateRatingSheetError)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    // Watched (not read on submit): a StreamProvider nobody watches answers
    // AsyncLoading on its first read, which would make the submit a silent
    // no-op. Watching also keeps the button honestly disabled while auth
    // resolves.
    final uid = ref.watch(authStateChangesProvider).valueOrNull?.uid;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              widget.existing == null
                  ? l10n.templateRatingSheetTitle
                  : l10n.templateRatingSheetTitleEdit,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: StarRatingInput(
                rating: _rating,
                onRatingChanged: (v) => setState(() => _rating = v),
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _commentController,
              maxLength: 500,
              maxLines: 4,
              minLines: 2,
              style: GoogleFonts.barlow(color: palette.textPrimary),
              decoration: InputDecoration(
                hintText: l10n.templateRatingSheetCommentHint,
                hintStyle: GoogleFonts.barlow(color: palette.textMuted),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: palette.border),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: palette.accent),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed:
                        _submitting ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      l10n.templateRatingSheetCancel,
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        letterSpacing: 0.8,
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    key: const Key('template_rating_submit'),
                    onPressed: (_rating > 0 && !_submitting && uid != null)
                        ? () => _onSubmit(uid)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: palette.bg,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                    ),
                    child: _submitting
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: palette.bg,
                            ),
                          )
                        : Text(
                            l10n.templateRatingSheetSubmit,
                            style: GoogleFonts.barlowCondensed(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              letterSpacing: 0.8,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
