import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../application/review_notifier.dart';
import '../../domain/review.dart';
import 'star_rating_input.dart';

/// Which trigger opened this sheet — affects title copy.
///
/// Fase 6 Etapa 7.
enum ReviewTriggerVariant {
  /// Default: athlete opened from profile CTA or post-termination.
  standard,

  /// Opened by the 30-day automatic prompt.
  thirtyDay,
}

/// Bottom sheet for submitting or editing a trainer review.
///
/// Title logic:
///   - existing != null → "Editá tu reseña"
///   - variant == thirtyDay → 30-day prompt title
///   - otherwise → "¿Cómo fue tu experiencia con {trainerName}?"
///
/// On success: pops sheet + shows SnackBar "¡Gracias por tu reseña!".
/// On error: shows SnackBar, no auto-retry.
///
/// REQ-RV-WRITE-003. Fase 6 Etapa 7.
class ReviewBottomSheet extends ConsumerStatefulWidget {
  const ReviewBottomSheet({
    super.key,
    required this.linkId,
    required this.trainerId,
    required this.trainerName,
    required this.athleteId,
    this.existing,
    required this.triggerVariant,
  });

  final String linkId;
  final String trainerId;
  final String trainerName;
  final String athleteId;

  /// Pre-populate when editing an existing review.
  final Review? existing;

  final ReviewTriggerVariant triggerVariant;

  @override
  ConsumerState<ReviewBottomSheet> createState() => _ReviewBottomSheetState();
}

class _ReviewBottomSheetState extends ConsumerState<ReviewBottomSheet> {
  late int _rating;
  late TextEditingController _commentController;

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

  ReviewNotifierArgs get _args => ReviewNotifierArgs(
        linkId: widget.linkId,
        trainerId: widget.trainerId,
        athleteId: widget.athleteId,
      );

  String _title() {
    if (widget.existing != null) {
      return 'Editá tu reseña'; // i18n: Fase 6 Etapa 7
    }
    if (widget.triggerVariant == ReviewTriggerVariant.thirtyDay) {
      return 'Ya llevás un mes entrenando con ${widget.trainerName}. ¿Cómo va?'; // i18n: Fase 6 Etapa 7
    }
    return '¿Cómo fue tu experiencia con ${widget.trainerName}?'; // i18n: Fase 6 Etapa 7
  }

  Future<void> _onSubmit() async {
    final notifier = ref.read(reviewNotifierProvider(_args).notifier);
    await notifier.submit(
      rating: _rating,
      comment: _commentController.text.isEmpty ? null : _commentController.text,
      existing: widget.existing,
    );
    if (!mounted) return;
    final state = ref.read(reviewNotifierProvider(_args));
    if (state is AsyncError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No pudimos guardar tu reseña. Probá de nuevo.', // i18n: Fase 6 Etapa 7
          ),
        ),
      );
    } else {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('¡Gracias por tu reseña!'), // i18n: Fase 6 Etapa 7
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final notifierState = ref.watch(reviewNotifierProvider(_args));
    final isLoading = notifierState is AsyncLoading;

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
            // Drag handle
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
            // Title
            Text(
              _title(),
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 18),
            // Star rating
            Center(
              child: StarRatingInput(
                rating: _rating,
                onRatingChanged: (v) => setState(() => _rating = v),
              ),
            ),
            const SizedBox(height: 18),
            // Comment field
            TextField(
              controller: _commentController,
              maxLength: 500,
              maxLines: 4,
              minLines: 2,
              style: GoogleFonts.barlow(color: palette.textPrimary),
              decoration: InputDecoration(
                hintText:
                    'Contanos cómo fue (opcional)', // i18n: Fase 6 Etapa 7
                hintStyle: GoogleFonts.barlow(color: palette.textMuted),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: palette.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: palette.accent),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 18),
            // Action row
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed:
                        isLoading ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      'CANCELAR', // i18n: Fase 6 Etapa 7
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
                    onPressed: (_rating > 0 && !isLoading) ? _onSubmit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: palette.bg,
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9999),
                      ),
                    ),
                    child: isLoading
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: palette.bg,
                            ),
                          )
                        : Text(
                            'ENVIAR', // i18n: Fase 6 Etapa 7
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
