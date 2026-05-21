import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_palette.dart';
import '../../core/widgets/treino_icon.dart';
import '../profile/application/user_public_profile_providers.dart';
import '../profile/domain/user_public_profile.dart';
import 'application/trainer_link_providers.dart';
import 'domain/trainer_link.dart';
import 'domain/trainer_link_status.dart';

class TrainerCoachView extends StatelessWidget {
  const TrainerCoachView({super.key});

  static const _labels = <String>[
    'DASHBOARD',
    'ALUMNOS',
    'AGENDA',
    'COMUNIDADES',
  ];

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

    return DefaultTabController(
      length: _labels.length,
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
          ),
          const SizedBox(height: 8),
          const Expanded(
            child: TabBarView(
              physics: NeverScrollableScrollPhysics(),
              children: [
                _DashboardTab(),
                _AlumnosTab(),
                _SubTabPlaceholder(label: 'AGENDA'),
                _SubTabPlaceholder(label: 'COMUNIDADES'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── DASHBOARD tab ─────────────────────────────────────────────────────────────

class _DashboardTab extends ConsumerWidget {
  const _DashboardTab();

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
          'No pudimos cargar tus vínculos.',
          style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
        ),
      ),
      data: (links) {
        final pending =
            links.where((l) => l.status == TrainerLinkStatus.pending).toList();
        final active =
            links.where((l) => l.status == TrainerLinkStatus.active).toList();

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          physics: const ClampingScrollPhysics(),
          children: [
            _SectionHeader(
              label: 'SOLICITUDES PENDIENTES',
              count: pending.length,
            ),
            const SizedBox(height: 12),
            if (pending.isEmpty)
              const _EmptyHint(message: 'Sin solicitudes nuevas por ahora.')
            else
              for (final link in pending) ...[
                _PendingRequestCard(link: link),
                const SizedBox(height: 12),
              ],
            const SizedBox(height: 20),
            _SectionHeader(
              label: 'ALUMNOS ACTIVOS',
              count: active.length,
            ),
            const SizedBox(height: 12),
            if (active.isEmpty)
              const _EmptyHint(
                  message:
                      'Cuando aceptes solicitudes, tus alumnos van a aparecer acá.')
            else
              Text(
                'Tenés ${active.length} ${active.length == 1 ? "alumno activo" : "alumnos activos"}. Tocá la tab ALUMNOS para verlos.',
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w400,
                  fontSize: 14,
                  color: palette.textMuted,
                ),
              ),
          ],
        );
      },
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
        final active =
            links.where((l) => l.status == TrainerLinkStatus.active).toList();
        if (active.isEmpty) {
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
          itemCount: active.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _ActiveAlumnoCard(link: active[i]),
        );
      },
    );
  }
}

// ── Pending request card ─────────────────────────────────────────────────────

class _PendingRequestCard extends ConsumerWidget {
  const _PendingRequestCard({required this.link});
  final TrainerLink link;

  Future<void> _accept(WidgetRef ref) async {
    await ref.read(trainerLinkRepositoryProvider).accept(link.id);
  }

  Future<void> _decline(WidgetRef ref) async {
    await ref.read(trainerLinkRepositoryProvider).decline(link.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final pubAsync = ref.watch(userPublicProfileProvider(link.athleteId));

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border, width: 1),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          _UserHeader(pubAsync: pubAsync, subtitle: _formatRequestedAt(link)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _decline(ref),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: palette.highlight, width: 1),
                    foregroundColor: palette.highlight,
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                  child: Text(
                    'RECHAZAR',
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _accept(ref),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: palette.bg,
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                  child: Text(
                    'ACEPTAR',
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
        ],
      ),
    );
  }

  String _formatRequestedAt(TrainerLink l) {
    final dt = l.requestedAt.toLocal();
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    return 'Solicitó vincularse el $dd/$mm';
  }
}

// ── Active alumno card ────────────────────────────────────────────────────────

class _ActiveAlumnoCard extends ConsumerWidget {
  const _ActiveAlumnoCard({required this.link});
  final TrainerLink link;

  Future<void> _terminate(BuildContext context, WidgetRef ref) async {
    final palette = AppPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Terminar vínculo',
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: palette.textPrimary,
          ),
        ),
        content: Text(
          '¿Seguro que querés terminar el vínculo con este alumno?',
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
              backgroundColor: palette.highlight,
              foregroundColor: palette.bg,
            ),
            child: Text(
              'Terminar',
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
    await ref
        .read(trainerLinkRepositoryProvider)
        .terminate(link.id, reason: 'trainer-terminated');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final pubAsync = ref.watch(userPublicProfileProvider(link.athleteId));

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
              subtitle: 'Vinculado desde ${_formatAcceptedAt(link)}',
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _terminate(context, ref),
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
  const _UserHeader({required this.pubAsync, required this.subtitle});
  final AsyncValue<UserPublicProfile?> pubAsync;
  final String subtitle;

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
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      children: [
        Text(
          label,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 1.2,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color:
                count > 0 ? palette.accent.withValues(alpha: 0.15) : palette.bg,
            borderRadius: BorderRadius.circular(9999),
            border: Border.all(
              color: count > 0 ? palette.accent : palette.border,
              width: 1,
            ),
          ),
          child: Text(
            '$count',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 11,
              color: count > 0 ? palette.accent : palette.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Text(
        message,
        style: GoogleFonts.barlow(
          fontWeight: FontWeight.w400,
          fontSize: 13,
          color: palette.textMuted,
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
