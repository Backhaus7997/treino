import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_palette.dart';
import '../../core/widgets/treino_icon.dart';
import '../profile/application/user_public_profile_providers.dart';
import '../profile/domain/user_public_profile.dart';
import '../workout/application/session_providers.dart' show currentUidProvider;
import 'application/trainer_link_providers.dart';
import 'domain/trainer_link.dart';
import 'domain/trainer_link_status.dart';
import 'presentation/trainer_agenda_tab.dart';

class TrainerCoachView extends StatelessWidget {
  const TrainerCoachView({super.key, this.initialTab});

  /// Optional initial sub-tab — accepts `'alumnos'`, `'agenda'`, or
  /// `'comunidades'`. Read from the `?tab=` query param by [CoachScreen]
  /// so deep links from the trainer dashboard land on the right tab.
  final String? initialTab;

  static const _labels = <String>['ALUMNOS', 'AGENDA', 'COMUNIDADES'];

  static int _resolveInitialIndex(String? tab) {
    switch (tab) {
      case 'agenda':
        return 1;
      case 'comunidades':
        return 2;
      case 'alumnos':
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

    return DefaultTabController(
      length: _labels.length,
      initialIndex: _resolveInitialIndex(initialTab),
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            indicatorColor: palette.accent,
            labelColor: palette.textPrimary,
            unselectedLabelColor: palette.textMuted,
            labelPadding: const EdgeInsets.symmetric(horizontal: 12),
            labelStyle: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
            tabs: [for (final l in _labels) Tab(text: l)],
            // Close any open popup (e.g. agenda day sheet) when the trainer
            // switches sub-tabs. Pop both navigators because showModalBottomSheet
            // defaults to useRootNavigator: false (local navigator).
            onTap: (_) {
              Navigator.of(context).popUntil((route) => route is! PopupRoute);
              Navigator.of(context, rootNavigator: true)
                  .popUntil((route) => route is! PopupRoute);
            },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                const _AlumnosTab(),
                Consumer(
                  builder: (context, ref, _) {
                    final uid = ref.watch(currentUidProvider) ?? '';
                    return TrainerAgendaTab(trainerId: uid);
                  },
                ),
                const _SubTabPlaceholder(label: 'COMUNIDADES'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── ALUMNOS tab ───────────────────────────────────────────────────────────────

class _AlumnosTab extends ConsumerWidget {
  const _AlumnosTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final linksAsync = ref.watch(trainerLinksStreamProvider);

    return linksAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
      error: (_, __) => Center(
        child: Text(
          'No pudimos cargar tus alumnos.',
          style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
        ),
      ),
      data: (links) {
        final visible = links
            .where((l) =>
                l.status == TrainerLinkStatus.active ||
                l.status == TrainerLinkStatus.paused)
            .toList();
        if (visible.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(TreinoIcon.users, size: 48, color: palette.textMuted),
                  const SizedBox(height: 18),
                  Text(
                    'Sin alumnos activos todavía.',
                    style: GoogleFonts.barlow(
                      fontWeight: FontWeight.w400,
                      fontSize: 14,
                      color: palette.textMuted,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          physics: const ClampingScrollPhysics(),
          itemCount: visible.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _ActiveAlumnoCard(link: visible[i]),
        );
      },
    );
  }
}

// ── Active alumno card ────────────────────────────────────────────────────────

class _ActiveAlumnoCard extends ConsumerWidget {
  const _ActiveAlumnoCard({required this.link});
  final TrainerLink link;

  Future<void> _confirmAndRun(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String body,
    required String confirmLabel,
    required Color confirmBg,
    required Future<void> Function() action,
  }) async {
    final palette = AppPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: palette.textPrimary,
          ),
        ),
        content: Text(
          body,
          style: GoogleFonts.barlow(fontSize: 14, color: palette.textPrimary),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: palette.textPrimary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmBg,
              foregroundColor: palette.bg,
            ),
            child: Text(
              confirmLabel,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await action();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final pubAsync = ref.watch(userPublicProfileProvider(link.athleteId));
    final isPaused = link.status == TrainerLinkStatus.paused;

    return InkWell(
      onTap: () => context.push('/coach/athlete/${link.athleteId}'),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.border, width: 1),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _UserHeader(
              pubAsync: pubAsync,
              subtitle: isPaused
                  ? 'Vínculo pausado · ${_formatAcceptedAt(link)}'
                  : 'Vinculado desde ${_formatAcceptedAt(link)}',
              statusBadge: isPaused
                  ? _StatusBadge(
                      label: 'PAUSADO',
                      color: palette.textMuted,
                    )
                  : null,
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: isPaused
                  ? ElevatedButton(
                      onPressed: () => _confirmAndRun(
                        context,
                        ref,
                        title: 'Reanudar vínculo',
                        body:
                            '¿Querés reanudar el vínculo con este alumno? Va a poder ver tus updates de nuevo.',
                        confirmLabel: 'Reanudar',
                        confirmBg: palette.accent,
                        action: () => ref
                            .read(trainerLinkRepositoryProvider)
                            .resume(link.id),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: palette.accent,
                        foregroundColor: palette.bg,
                        minimumSize: const Size.fromHeight(40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9999),
                        ),
                      ),
                      child: Text(
                        'REANUDAR VÍNCULO',
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 0.8,
                        ),
                      ),
                    )
                  : OutlinedButton(
                      onPressed: () => _confirmAndRun(
                        context,
                        ref,
                        title: 'Pausar vínculo',
                        body:
                            '¿Querés pausar el vínculo con este alumno? Va a quedar en read-only hasta que reanudes.',
                        confirmLabel: 'Pausar',
                        confirmBg: palette.accent,
                        action: () => ref
                            .read(trainerLinkRepositoryProvider)
                            .pause(link.id),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: palette.accent, width: 1),
                        foregroundColor: palette.accent,
                        minimumSize: const Size.fromHeight(40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9999),
                        ),
                      ),
                      child: Text(
                        'PAUSAR VÍNCULO',
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _confirmAndRun(
                  context,
                  ref,
                  title: 'Terminar vínculo',
                  body:
                      '¿Seguro que querés terminar el vínculo con este alumno?',
                  confirmLabel: 'Terminar',
                  confirmBg: palette.highlight,
                  action: () => ref
                      .read(trainerLinkRepositoryProvider)
                      .terminate(link.id, reason: 'trainer-terminated'),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: palette.border, width: 1),
                  foregroundColor: palette.textMuted,
                  minimumSize: const Size.fromHeight(40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9999),
                  ),
                ),
                child: Text(
                  'TERMINAR VÍNCULO',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatAcceptedAt(TrainerLink l) {
    final dt = (l.acceptedAt ?? l.requestedAt).toLocal();
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    return '$dd/$mm/${dt.year}';
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _UserHeader extends StatelessWidget {
  const _UserHeader({
    required this.pubAsync,
    required this.subtitle,
    this.statusBadge,
  });
  final AsyncValue<UserPublicProfile?> pubAsync;
  final String subtitle;
  final Widget? statusBadge;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final name = pubAsync.valueOrNull?.displayName ?? '...';

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.bg,
            border: Border.all(color: palette.border, width: 1),
          ),
          alignment: Alignment.center,
          child:
              Icon(TreinoIcon.tabProfile, size: 22, color: palette.textMuted),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: palette.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w400,
                  fontSize: 12,
                  color: palette.textMuted,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        if (statusBadge != null) ...[
          const SizedBox(width: 8),
          statusBadge!,
        ],
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        label,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 10,
          letterSpacing: 0.8,
          color: color,
        ),
      ),
    );
  }
}

// ── Placeholder sub-tab (AGENDA, COMUNIDADES) ────────────────────────────────

class _SubTabPlaceholder extends StatelessWidget {
  const _SubTabPlaceholder({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 28,
              color: palette.highlight,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'PRÓXIMAMENTE',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
