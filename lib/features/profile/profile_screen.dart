import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_palette.dart';
import '../../core/utils/k_formatter.dart';
import '../../core/widgets/treino_icon.dart';
import '../../l10n/app_l10n.dart';
import '../auth/application/auth_providers.dart';
import 'application/profile_stats_providers.dart';
import 'application/ranking_optin_controller_provider.dart';
import 'application/user_providers.dart';
import 'application/user_public_profile_providers.dart';
import 'domain/user_role.dart';
import 'presentation/widgets/eliminar_cuenta_sheet.dart';
import 'presentation/widgets/profile_avatar_card.dart';
import 'presentation/widgets/profile_cuenta_section.dart';
import 'presentation/widgets/profile_header.dart';
import 'presentation/widgets/profile_section_tile.dart';
import 'presentation/widgets/profile_trainer_section.dart';
import 'trainer_profile_view.dart';

/// Role-aware profile screen.
///
/// - Trainer → [TrainerProfileView] (matches docs/app-trainer/screens/perfil).
/// - Athlete (default) → existing rewrite chain (PR#1..PR#3 / Fase 3 Etapa 7):
///   header + stats + avatar card + cuenta section + legacy footer sign out.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserRole? role = ref.watch(
      userProfileProvider.select((async) => async.valueOrNull?.role),
    );

    // Default to athlete (dominant role, matches HomeScreen/WorkoutScreen).
    return role == UserRole.trainer
        ? const TrainerProfileView()
        : const _AthleteProfile();
  }
}

/// Athlete profile — original [ProfileScreen] body extracted intact.
class _AthleteProfile extends ConsumerWidget {
  const _AthleteProfile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);
    final l10n = AppL10n.of(context);

    return SingleChildScrollView(
      // SingleChildScrollView does NOT inherit the ambient MediaQuery inset —
      // pad the bottom so content can scroll out from behind the floating bar.
      padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
      child: Column(
        children: [
          // a11y: ProfileHeader renders "TU CUENTA" + "PERFIL" as the screen
          // title block. header:true lets VoiceOver/TalkBack treat it as a
          // navigable heading. (Per-section-title headings are handled by
          // _A11ySectionGroup below.)
          Semantics(header: true, child: const ProfileHeader()),
          // Avatar card BEFORE stats — mockup parity 2026-06-01 polish pass.
          // Visual hierarchy: header → identity (who I am) → stats (what I did).
          // a11y: MergeSemantics fuses the avatar image node (PostAvatar, no
          // label of its own) with the name/handle/gym text into one identity
          // node, so the avatar is announced with the user's name instead of
          // surfacing as an empty image node.
          const MergeSemantics(child: ProfileAvatarCard()),
          _OwnProfileStatsRow(palette: palette, theme: theme),
          const ProfileCuentaSection(),
          // Sección "ENTRENADOR" condicional — solo visible cuando
          // role == trainer. Tile que abre /profile/edit-trainer para
          // editar perfil público multi-location (Fase 6 Etapa 0 PR#3).
          const ProfileTrainerSection(),
          // ── Entrenamiento — acceso del alumno a sus ejercicios custom ────
          // Reusa MyExercisesScreen (/profile/my-exercises) que ya existía
          // solo para el entrenador. El backend (users/{uid}/customExercises)
          // es uid-keyed → funciona para el alumno sin cambios.
          _A11ySectionGroup(
            title: 'ENTRENAMIENTO',
            palette: palette,
            tiles: [
              // a11y: button:true + label gives the bare-GestureDetector tile a
              // button role; excludeSemantics drops the child subtree (raw
              // title Text + unlabeled chevron) so VoiceOver announces one
              // clean "Mis ejercicios, button" node. No AppL10n key exists for
              // this label yet (deferred to i18n Fase 6 Etapa 3) — reuse the
              // visible title so the announcement matches the screen.
              Semantics(
                button: true,
                label: 'Mis ejercicios',
                excludeSemantics: true,
                child: ProfileSectionTile(
                  icon: TreinoIcon.sparkle,
                  title: 'Mis ejercicios',
                  inGroup: true,
                  onTap: () => context.push('/profile/my-exercises'),
                ),
              ),
              // ── Rankings tile — navigates to the per-gym leaderboards
              // AND carries the rankingOptIn toggle as its trailing widget
              // (design `sdd/rankings/design` — Placement: opt-in toggle
              // lives in the profile sub-tree, entry point next to the
              // rest of ENTRENAMIENTO).
              const _RankingsTile(),
            ],
          ),
          // ── Apariencia section (REQ-LM-009) ──────────────────────────────
          _A11ySectionGroup(
            title: l10n.profileSectionAppearance.toUpperCase(),
            palette: palette,
            tiles: [
              Semantics(
                button: true,
                label: l10n.appearanceTitle,
                excludeSemantics: true,
                child: ProfileSectionTile(
                  icon: TreinoIcon.appearance,
                  title: l10n.appearanceTitle,
                  inGroup: true,
                  onTap: () => context.push('/profile/settings/appearance'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── Sesión section — PR#4 v2 pivot 2026-05-28 ────────────────────
          // Sign-out + account deletion grouped in one boxed section, mockup
          // parity polish 2026-06-01. Settings as a dedicated surface stays
          // deferred to a future SDD (notifications, theme, language).
          _A11ySectionGroup(
            title: 'SESIÓN', // i18n: Fase 6 Etapa 3
            palette: palette,
            tiles: [
              // a11y: button role + label, chevron/raw text excluded.
              Semantics(
                button: true,
                label: l10n.authProfileSignOut, // 'Cerrar sesión'
                excludeSemantics: true,
                child: ProfileSectionTile(
                  icon: TreinoIcon.signOut,
                  title: 'Cerrar sesión', // i18n: Fase 6 Etapa 3
                  inGroup: true,
                  onTap: () =>
                      ref.read(authNotifierProvider.notifier).signOut(),
                ),
              ),
              Semantics(
                button: true,
                label: l10n.eliminarCuentaSheetTitle, // 'Eliminar cuenta'
                excludeSemantics: true,
                child: ProfileSectionTile(
                  icon: TreinoIcon.trash,
                  title: 'Eliminar cuenta', // i18n: Fase 6 Etapa 3
                  destructive: true,
                  inGroup: true,
                  onTap: () => showModalBottomSheet<void>(
                    context: context,
                    useRootNavigator: true,
                    backgroundColor: palette.bgCard,
                    shape: const RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(18)),
                    ),
                    isScrollControlled: true,
                    builder: (_) => const EliminarCuentaSheet(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ── Rankings tile (entry point + opt-in toggle) ─────────────────────────────

/// "Rankings" row in the ENTRENAMIENTO section — tapping the row (outside the
/// trailing toggle) navigates to `/profile/rankings`; the trailing [Switch]
/// reflects and flips `rankingOptIn` via [RankingOptInControllerBase].
///
/// Reads `rankingOptIn` from [userPublicProfileProvider] (own uid) rather
/// than [userProfileProvider] — that field lives on the PUBLIC profile doc
/// (spec `gym-rankings`), not the private one.
class _RankingsTile extends ConsumerStatefulWidget {
  const _RankingsTile();

  @override
  ConsumerState<_RankingsTile> createState() => _RankingsTileState();
}

class _RankingsTileState extends ConsumerState<_RankingsTile> {
  bool _pending = false;

  Future<void> _toggle(String uid, bool newValue) async {
    setState(() => _pending = true);
    try {
      final controller = ref.read(rankingOptInControllerProvider);
      if (newValue) {
        await controller.enableRankingOptIn(uid);
      } else {
        await controller.disableRankingOptIn(uid);
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final myUid = ref.watch(authStateChangesProvider).valueOrNull?.uid ?? '';
    final optIn =
        ref.watch(userPublicProfileProvider(myUid)).valueOrNull?.rankingOptIn ??
            false;

    return Semantics(
      button: true,
      label: 'Rankings',
      excludeSemantics: true,
      child: ProfileSectionTile(
        icon: TreinoIcon.ranking,
        title: 'Rankings',
        inGroup: true,
        onTap: () => context.push('/profile/rankings'),
        trailing: _pending
            ? SizedBox(
                key: const Key('profile_ranking_optin_loading'),
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: palette.accent,
                ),
              )
            : Switch(
                key: const Key('profile_ranking_optin_switch'),
                value: optIn,
                activeThumbColor: palette.accent,
                onChanged:
                    myUid.isEmpty ? null : (value) => _toggle(myUid, value),
              ),
      ),
    );
  }
}

// ── Section group (a11y-aware) ──────────────────────────────────────────────────

/// In-file variant of `ProfileSectionGroup` that accepts arbitrary [Widget]
/// tiles (so each row can be wrapped in [Semantics] for button role + label)
/// and marks the group [title] as a heading.
///
/// Visual treatment is kept byte-for-byte identical to `ProfileSectionGroup`
/// (same padding, Barlow Condensed title, bgCard container, 14px radius, border
/// + hairline divider alphas) so there is no layout drift — the only delta is
/// the semantics tree. `ProfileSectionGroup.tiles` is typed
/// `List<ProfileSectionTile>`, which cannot hold a `Semantics`-wrapped tile,
/// hence this local group.
class _A11ySectionGroup extends StatelessWidget {
  const _A11ySectionGroup({
    required this.title,
    required this.tiles,
    required this.palette,
  });

  final String title;
  final List<Widget> tiles;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    // Interleave tiles with hairline dividers (1px, muted). Dividers are
    // decorative → ExcludeSemantics keeps them out of the semantics tree.
    final children = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      if (i > 0) {
        children.add(
          ExcludeSemantics(
            child: Container(
              height: 1,
              color: palette.textMuted.withValues(alpha: 0.10),
            ),
          ),
        );
      }
      children.add(tiles[i]);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 18, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            // a11y: section title is a navigable heading.
            child: Semantics(
              header: true,
              child: Text(
                title, // i18n: Fase 6 Etapa 3
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 1.4,
                  color: palette.textMuted,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: palette.textMuted.withValues(alpha: 0.12),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stats row ─────────────────────────────────────────────────────────────────

class _OwnProfileStatsRow extends ConsumerWidget {
  const _OwnProfileStatsRow({
    required this.palette,
    required this.theme,
  });

  final AppPalette palette;
  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(userSessionStatsProvider);

    // Mockup parity 2026-06-01 polish: wrap in a card with light border +
    // vertical dividers between the 3 stats. Numbers prominent, label small
    // beneath (was the inverse in the pre-polish layout).
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Container(
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: palette.textMuted.withValues(alpha: 0.12),
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: IntrinsicHeight(
          child: Row(
            children: [
              _StatTile(
                label: 'SESIONES', // i18n: Fase 6 Etapa 3
                value: statsAsync.when(
                  data: (s) => s.totalSessions.toString(),
                  loading: () => '--',
                  error: (_, __) => '--',
                ),
                valueColor: palette.accent,
                theme: theme,
                palette: palette,
              ),
              _StatDivider(palette: palette),
              _StatTile(
                label: 'VOLUMEN KG', // i18n: Fase 6 Etapa 3
                value: statsAsync.when(
                  data: (s) => kFormatMagnitude(s.totalVolumeKg),
                  loading: () => '--',
                  error: (_, __) => '--',
                ),
                valueColor: palette.accent,
                theme: theme,
                palette: palette,
              ),
              _StatDivider(palette: palette),
              _StatTile(
                label: 'RACHA', // i18n: Fase 6 Etapa 3
                value: statsAsync.when(
                  data: (s) => s.streak.toString(),
                  loading: () => '--',
                  error: (_, __) => '--',
                ),
                valueColor: palette.highlight,
                theme: theme,
                palette: palette,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    // a11y: purely decorative separator — keep it out of the semantics tree.
    return ExcludeSemantics(
      child: Container(
        width: 1,
        margin: const EdgeInsets.symmetric(vertical: 8),
        color: palette.textMuted.withValues(alpha: 0.18),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.theme,
    required this.palette,
  });

  final String label;
  final String value;
  final Color valueColor;
  final ThemeData theme;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    // Mockup parity 2026-06-01: number prominent ON TOP, label small below
    // (previous order was inverted). Value font bumped to headlineMedium for
    // the visual weight the mockup uses (143 / 92k / 12 read first).
    //
    // a11y: MergeSemantics fuses the value + label text nodes into one
    // accessible node so a screen reader announces each stat as a single unit
    // (e.g. "143 SESIONES") instead of two disconnected fragments.
    return Expanded(
      child: MergeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: valueColor,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: palette.textMuted,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
