import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/kg_format.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../auth/application/auth_providers.dart';
import '../../../gyms/application/gym_providers.dart';
import '../../../gyms/domain/gym.dart' show kNoGymId;
import '../../../gyms/domain/gym_display_name.dart';
import '../../application/post_actions_notifier.dart';
import '../../domain/post.dart';
import '../../domain/routine_tag.dart';
import '../../domain/workout_snapshot.dart';
import 'post_avatar.dart';
import 'workout_snapshot_detail.dart';

/// #547: the theme's Barlow families carry no emoji glyphs, so an emoji inside
/// user-authored (or auto-generated) post content renders as tofu "▯". Pinning
/// the system emoji font per platform makes the engine fall back correctly —
/// same root cause and fix as `post_workout_summary_screen.dart` (PR #465),
/// applied here to the STYLE rather than to one string, so any emoji a user
/// types into a manual post renders too.
const List<String> _kEmojiFallback = ['Apple Color Emoji', 'Noto Color Emoji'];

/// Appends the emoji fonts to [style]'s existing `fontFamilyFallback` instead
/// of replacing it — `GoogleFonts.*()` styles already carry `[<base family>]`
/// there (the package's own variant→family fallback), which must survive.
TextStyle _withEmojiFallback(TextStyle style) => style.copyWith(
      fontFamilyFallback: [...?style.fontFamilyFallback, ..._kEmojiFallback],
    );

class PostCard extends ConsumerWidget {
  const PostCard({
    super.key,
    required this.post,
    this.onAuthorTap,
  });

  final Post post;
  final VoidCallback? onAuthorTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final viewerUid = ref.watch(authStateChangesProvider).valueOrNull?.uid;
    final isOwner = viewerUid != null && viewerUid == post.authorUid;

    // #549: `authorGymId` is an OPAQUE id, never a display name — gyms coming
    // from Google Places carry a place id (`ChIJ…`) and the card used to print
    // it uppercased as if it were the name. Resolve it against the `gyms/`
    // catalog instead, the same `gymByIdProvider` + `gymDisplayNameFromGym`
    // pattern `PublicProfileHero` and `PinnedCurrentGym` already use. The
    // provider is a non-autoDispose family, so a feed of N posts across K
    // distinct gyms costs K reads, cached for the app's lifetime.
    //
    // An unresolvable id (deleted gym, place id never upserted into the
    // catalog) yields '' → the gym segment is omitted and only the date shows.
    // Rendering the raw id is not a fallback we accept.
    final gymId = post.authorGymId;
    final gymAsync = (gymId == null || gymId.isEmpty || gymId == kNoGymId)
        ? null
        : ref.watch(gymByIdProvider(gymId));
    final gymName = gymDisplayNameFromGym(gymAsync?.valueOrNull);

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: palette.accent.withValues(alpha: 0.25),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.accent.withValues(alpha: 0.10),
            blurRadius: 10,
            spreadRadius: 0,
            offset: Offset.zero,
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── HEADER ROW ──────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onAuthorTap,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PostAvatar(
                        authorDisplayName: post.authorDisplayName,
                        authorAvatarUrl: post.authorAvatarUrl,
                        size: 40,
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              post.authorDisplayName,
                              style: _withEmojiFallback(
                                GoogleFonts.barlowCondensed(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  letterSpacing: 0.5,
                                  color: palette.textPrimary,
                                ),
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _formatMeta(gymName, post.createdAt),
                              style: GoogleFonts.barlow(
                                fontWeight: FontWeight.w400,
                                fontSize: 12,
                                color: palette.textMuted,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Overflow menu — Editar/Eliminar, own posts only
              // (REQ-FEED-POSTCARD-006).
              if (isOwner)
                Semantics(
                  button: true,
                  label: AppL10n.of(context).postCardMenuA11y,
                  child: IconButton(
                    icon: Icon(
                      TreinoIcon.dotsThree,
                      color: palette.textMuted,
                      size: 20,
                    ),
                    onPressed: () => _showPostMenu(context, ref),
                    tooltip: null,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 12),

          // ── BODY TEXT ───────────────────────────────────────────────
          Text(
            post.text,
            style: _withEmojiFallback(
              GoogleFonts.barlow(
                fontWeight: FontWeight.w400,
                fontSize: 14,
                color: palette.textPrimary,
              ),
            ),
          ),

          // Foto adjuntada desde el composer de entreno. memCacheWidth acota
          // el bitmap decodificado al ancho real de la card (mismo criterio
          // que PostAvatar) — sin eso, una foto de cámara de 4000px se
          // decodifica entera por cada card del ListView.
          if (post.photoUrl != null && post.photoUrl!.isNotEmpty) ...[
            const SizedBox(height: 12),
            _PostPhoto(url: post.photoUrl!),
          ],

          if (post.routineTag != null) ...[
            const SizedBox(height: 12),
            _RoutineTagChip(tag: post.routineTag!),
          ],

          // QA-FEED-364/389: real workout stats when the post came from sharing
          // a workout; otherwise the row is hidden entirely (manual + legacy
          // posts) instead of the old permanent "— kg / — min / — ej." stub.
          if (post.workoutStats != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '${formatVolumeKg(post.workoutStats!.volumeKg)} kg',
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(width: 18),
                Text(
                  '${post.workoutStats!.durationMin} min',
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(width: 18),
                Text(
                  '${post.workoutStats!.exerciseCount} ej.',
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ],

          // Detalle del entreno (ejercicios con sets + distribución muscular).
          // Sólo en posts compartidos desde el composer — los manuales y los
          // legacy no traen snapshot y la card queda idéntica a hoy.
          if (post.workoutSnapshot != null) ...[
            const SizedBox(height: 12),
            _WorkoutDetailSection(snapshot: post.workoutSnapshot!),
          ],
        ],
      ),
    );
  }

  // ── Overflow menu (owner only) ────────────────────────────────────────

  void _showPostMenu(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(TreinoIcon.edit, color: palette.textPrimary),
              title: Text(
                l10n.postCardMenuEdit,
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w400,
                  fontSize: 14,
                  color: palette.textPrimary,
                ),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push('/feed/create', extra: post);
              },
            ),
            ListTile(
              leading: Icon(TreinoIcon.trash, color: palette.danger),
              title: Text(
                l10n.postCardMenuDelete,
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w400,
                  fontSize: 14,
                  color: palette.danger,
                ),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _confirmDelete(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.postCardDeleteConfirmTitle),
        content: Text(l10n.postCardDeleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.postCardMenuDelete),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(postActionsProvider).deletePost(post.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.postCardDeleteSuccess)));
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.postCardDeleteError)));
    }
  }
}

// ── Private helpers ────────────────────────────────────────────────────────

String _relativeTime(DateTime createdAt) {
  final delta = DateTime.now().difference(createdAt);
  if (delta.inMinutes < 1) return 'recién';
  if (delta.inHours < 1) return 'hace ${delta.inMinutes}m';
  if (delta.inDays < 1) return 'hace ${delta.inHours}h';
  if (delta.inDays < 7) return 'hace ${delta.inDays}d';
  // createdAt viaja en UTC (Post.createdAt -> toUtc()); la fecha absoluta se
  // formatea en la zona del usuario para que las zonas de offset negativo
  // (Argentina, UTC-3) no muestren el día siguiente en los posts nocturnos.
  // Mismo criterio que el gemelo de chat_list_screen.
  final local = createdAt.toLocal();
  final d = local.day.toString().padLeft(2, '0');
  final m = local.month.toString().padLeft(2, '0');
  return '$d/$m';
}

/// Meta line under the author name: `"GIMNASIO · hace 2h"`, or just the time
/// when the gym is unknown.
///
/// #549: takes the RESOLVED gym name, never an id. The signature is the guard —
/// the helper can no longer be handed a `gymId` to print by mistake.
String _formatMeta(String gymName, DateTime createdAt) {
  final time = _relativeTime(createdAt);
  return gymName.isEmpty ? time : '${gymName.toUpperCase()} · $time';
}

// ── Private widgets ────────────────────────────────────────────────────────

/// Foto del post. `memCacheWidth` acota el bitmap decodificado — la card
/// ocupa el ancho de la pantalla, así que 2× el ancho lógico típico alcanza
/// para pantallas de densidad alta sin decodificar el original de cámara.
class _PostPhoto extends StatelessWidget {
  const _PostPhoto({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 320),
        child: SizedBox(
          width: double.infinity,
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            memCacheWidth: 1080,
            placeholder: (_, __) => Container(
              height: 200,
              color: palette.bg,
            ),
            // Una foto rota (objeto borrado, URL vencida) NO deja un hueco
            // ni rompe la card: se colapsa y el resto del post se lee igual.
            errorWidget: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

/// Sección expandible con el detalle del entreno compartido.
///
/// [StatefulWidget] propio (no estado en [PostCard], que es un
/// `ConsumerWidget` instanciado N veces en el `ListView` del feed) y el
/// contenido se construye SÓLO cuando está expandida — colapsada, la card
/// paga apenas el botón, no los N bloques de ejercicios ni el mini-gráfico.
class _WorkoutDetailSection extends StatefulWidget {
  const _WorkoutDetailSection({required this.snapshot});

  final WorkoutSnapshot snapshot;

  @override
  State<_WorkoutDetailSection> createState() => _WorkoutDetailSectionState();
}

class _WorkoutDetailSectionState extends State<_WorkoutDetailSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final label = _expanded
        ? l10n.postCardWorkoutDetailHide
        : l10n.postCardWorkoutDetailShow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _expanded,
          label: label,
          child: GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            behavior: HitTestBehavior.opaque,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: 1,
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 1.0,
                          color: palette.accent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _expanded
                            ? TreinoIcon.chevronUp
                            : TreinoIcon.chevronDown,
                        size: 14,
                        color: palette.accent,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 12),
          WorkoutSnapshotDetail(snapshot: widget.snapshot),
        ],
      ],
    );
  }
}

class _RoutineTagChip extends StatelessWidget {
  const _RoutineTagChip({required this.tag});

  final RoutineTag tag;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return GestureDetector(
      onTap: () => context.push('/workout/routine/${tag.routineId}'),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: palette.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: palette.accent.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(TreinoIcon.tabWorkout, color: palette.accent, size: 14),
            const SizedBox(width: 8),
            Text(
              tag.routineName,
              style: _withEmojiFallback(
                GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  letterSpacing: 0.8,
                  color: palette.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
