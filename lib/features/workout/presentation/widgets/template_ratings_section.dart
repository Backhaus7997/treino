import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../auth/application/auth_providers.dart';
import '../../../feed/presentation/widgets/post_avatar.dart';
import '../../../profile/application/user_public_profile_providers.dart';
import '../../../profile/domain/user_public_profile.dart';
import '../../../reviews/presentation/widgets/star_rating_display.dart';
import '../../application/template_rating_providers.dart';
import '../../domain/routine.dart';
import '../../domain/template_rating.dart';
import 'template_rating_sheet.dart';

/// Community reputation block of a PUBLISHED trainer template: the average
/// score, my own (editable) rating, and everyone's comments.
///
/// Only rendered for `trainer-template` routines with `visibility == public`
/// — the caller decides; this widget assumes the template is published.
///
/// The average comes from the CF-written `ratingAvg`/`ratingsCount` on the
/// routine doc, NOT from counting the streamed ratings: that list is capped
/// (and the aggregate is the server's authoritative number).
class TemplateRatingsSection extends ConsumerWidget {
  const TemplateRatingsSection({required this.routine, super.key});

  final Routine routine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final ratingsAsync = ref.watch(templateRatingsProvider(routine.id));
    final myRating =
        ref.watch(myTemplateRatingProvider(routine.id)).valueOrNull;
    final uid = ref.watch(authStateChangesProvider).valueOrNull?.uid;
    // The template's author never rates their own work (Firestore rules
    // enforce it too) — showing them the input would only produce a denied
    // write.
    final canRate = uid != null && uid != routine.assignedBy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.templateRatingsTitle,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 1.2,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(height: 12),
        _AverageRow(routine: routine),
        if (canRate) ...[
          const SizedBox(height: 18),
          _MyRatingRow(routine: routine, myRating: myRating),
        ],
        const SizedBox(height: 18),
        ratingsAsync.when(
          data: (ratings) {
            final withComments = [
              for (final r in ratings)
                if ((r.comment ?? '').trim().isNotEmpty) r,
            ];
            if (withComments.isEmpty) {
              return Text(
                l10n.templateRatingsEmpty,
                style:
                    GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
              );
            }
            return _CommentList(ratings: withComments);
          },
          loading: () => Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: palette.accent,
              ),
            ),
          ),
          error: (_, __) => Text(
            l10n.templateRatingsError,
            style: GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
          ),
        ),
      ],
    );
  }
}

/// Average score + how many people rated. With zero ratings it says so
/// plainly instead of rendering a hollow 0.0.
class _AverageRow extends StatelessWidget {
  const _AverageRow({required this.routine});

  final Routine routine;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final avg = routine.ratingAvg;
    final count = routine.ratingsCount ?? 0;

    if (avg == null || count == 0) {
      return Row(
        children: [
          Icon(TreinoIcon.starOutline, size: 18, color: palette.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              l10n.templateRatingsNoneYet,
              style: GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Text(
          avg.toStringAsFixed(1),
          key: const Key('template_rating_average'),
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 28,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(width: 12),
        StarRatingDisplay(rating: avg, starSize: 18),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            l10n.templateRatingsCount(count),
            style: GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
          ),
        ),
      ],
    );
  }
}

/// My own rating: the current value (if any) plus the CTA that opens the
/// editable sheet.
class _MyRatingRow extends StatelessWidget {
  const _MyRatingRow({required this.routine, required this.myRating});

  final Routine routine;
  final TemplateRating? myRating;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final mine = myRating;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          mine == null
              ? l10n.templateRatingsMineEmpty
              : l10n.templateRatingsMineLabel,
          style: GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (mine != null) ...[
              StarRatingDisplay(
                key: const Key('template_rating_mine'),
                rating: mine.rating.toDouble(),
                starSize: 18,
              ),
              const SizedBox(width: 12),
            ],
            TextButton(
              key: const Key('template_rating_cta'),
              onPressed: () => showTemplateRatingSheet(
                context,
                routineId: routine.id,
                existing: mine,
              ),
              style: TextButton.styleFrom(foregroundColor: palette.accent),
              child: Text(
                mine == null
                    ? l10n.templateRatingsRateCta
                    : l10n.templateRatingsEditCta,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// The comments, with their authors resolved in ONE batch lookup (the same
/// N+1-avoiding pattern the trainer RESEÑAS section uses).
class _CommentList extends ConsumerWidget {
  const _CommentList({required this.ratings});

  final List<TemplateRating> ratings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userIds =
        (ratings.map((r) => r.userId).toSet().toList()..sort()).join(',');
    final profiles = ref.watch(userPublicProfilesBatchProvider(userIds));

    return Column(
      children: [
        for (final rating in ratings)
          _CommentTile(
            rating: rating,
            profile: profiles.valueOrNull?[rating.userId],
            profileResolved: profiles.valueOrNull != null,
          ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.rating,
    required this.profile,
    required this.profileResolved,
  });

  final TemplateRating rating;
  final UserPublicProfile? profile;
  final bool profileResolved;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    // A null profile only means "deleted account" once the batch resolved;
    // while it loads, stay quiet instead of flashing "Usuario eliminado".
    final name = profile?.displayName ??
        (profileResolved ? l10n.reviewTileDeletedUser : '');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PostAvatar(
                authorDisplayName: name,
                authorAvatarUrl: profile?.avatarUrl,
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.barlow(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    StarRatingDisplay(rating: rating.rating.toDouble()),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            rating.comment!,
            style: GoogleFonts.barlow(fontSize: 13, color: palette.textPrimary),
          ),
        ],
      ),
    );
  }
}
