import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/analytics/analytics_service.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../coach/application/trainer_link_providers.dart';
import '../../coach/domain/trainer_link.dart';
import '../../coach/domain/trainer_link_status.dart';
import '../../feed/presentation/widgets/post_avatar.dart';
import '../../profile/application/user_providers.dart';
import '../../profile/application/user_public_profile_providers.dart';

/// Coach Hub status filter for the dashboard sections.
///
/// Ephemeral UI state, file-private. Three sections (ACTIVOS / PAUSADOS /
/// HISTORIAL) gate their visibility on whether the corresponding
/// [TrainerLinkStatus] is in the set. autoDispose so the filter resets when
/// the dashboard is left (ADR-CHLM-04).
final _statusFilterProvider = StateProvider.autoDispose<Set<TrainerLinkStatus>>(
  (_) => {
    TrainerLinkStatus.active,
    TrainerLinkStatus.paused,
    TrainerLinkStatus.terminated,
  },
);

/// Maps a raw `terminationReason` value to its es-AR display string.
/// Falls back to a generic "Vínculo terminado" so unknown / null reasons
/// never crash the historial render (REQ-CHLM-009 + defensive default).
String _reasonDisplay(String? raw) {
  switch (raw) {
    case 'declined':
      return 'Rechazado por el PF';
    case 'cancelled-by-athlete':
      return 'Cancelado por el atleta';
    case 'trainer-terminated':
      return 'Terminado por el PF';
    default:
      return 'Vínculo terminado';
  }
}

/// Wraps Material [AlertDialog] confirm flow used by Pausar / Reanudar /
/// Terminar actions. Coach Hub is desktop-first web — AlertDialog matches
/// Material 3 desktop guidance (ADR-CHLM-06).
///
/// Returns `true` if user tapped the confirm button, `false` (or `null`
/// normalized to `false`) on cancel / dismiss.
Future<bool> _confirmAction(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Formats a [DateTime] as DD/MM/YYYY using the raw values (no timezone
/// conversion). Used by the PAUSADOS section so a UTC-stored pausedAt
/// renders the same day everywhere (REQ-CHLM-008).
String _formatPauseDate(DateTime dt) {
  final dd = dt.day.toString().padLeft(2, '0');
  final mm = dt.month.toString().padLeft(2, '0');
  return '$dd/$mm/${dt.year}';
}

/// Landing dashboard del Coach Hub.
///
/// Sections, all driven by [trainerLinksStreamProvider] so any transition
/// elsewhere (pause/resume/terminate from web or mobile) reflects in
/// real-time without manual refresh (ADR-CHLM-03):
///
/// - SOLICITUDES PENDIENTES (pending links, accept/decline)
/// - Status filter chip row (ACTIVOS / PAUSADOS / HISTORIAL)
/// - ACTIVOS, PAUSADOS, HISTORIAL — each gated by [_statusFilterProvider]
///
/// REQ-CHLM-006..012, CAP-CHLM-002..004.
class CoachHubDashboardScreen extends ConsumerWidget {
  const CoachHubDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final profileAsync = ref.watch(userProfileProvider);
    final displayName = profileAsync.valueOrNull?.displayName ?? 'PF';

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header con brand + sign-out
                  Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TREINO COACH HUB',
                            style: GoogleFonts.barlowCondensed(
                              color: palette.highlight,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.8,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'BIENVENIDO, ${displayName.toUpperCase()}',
                            style: GoogleFonts.barlowCondensed(
                              color: palette.textPrimary,
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () async {
                          await FirebaseAuth.instance.signOut();
                          // El router redirige automáticamente al /login
                          // cuando authStateChangesProvider emite null.
                        },
                        icon: Icon(
                          TreinoIcon.signOut,
                          color: palette.textMuted,
                          size: 18,
                        ),
                        label: Text(
                          'Salir',
                          style: TextStyle(color: palette.textMuted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: () => context.go('/upload-plan'),
                    icon: Icon(TreinoIcon.upload, size: 18, color: palette.bg),
                    label: Text(
                      'IMPORTAR PLAN DESDE EXCEL',
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 1.4,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: palette.bg,
                      minimumSize: const Size.fromHeight(48),
                      shape: const StadiumBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Pending requests (only renders when there's at least one)
                  const _PendingRequestsList(),
                  // Status filter chips
                  const _FilterChipRow(),
                  const SizedBox(height: 14),
                  // Three sections, each gated on _statusFilterProvider
                  const _ActiveStudentsList(),
                  const _PausedStudentsList(),
                  const _HistorialList(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Filter chip row ─────────────────────────────────────────────────────────

class _FilterChipRow extends ConsumerWidget {
  const _FilterChipRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final filter = ref.watch(_statusFilterProvider);

    void toggle(TrainerLinkStatus status) {
      final next = Set<TrainerLinkStatus>.from(filter);
      if (next.contains(status)) {
        next.remove(status);
      } else {
        next.add(status);
      }
      ref.read(_statusFilterProvider.notifier).state = next;
    }

    Widget chip(TrainerLinkStatus status, String label) => FilterChip(
          label: Text(label),
          selected: filter.contains(status),
          onSelected: (_) => toggle(status),
          showCheckmark: false,
          backgroundColor: palette.bgCard,
          selectedColor: palette.accent.withValues(alpha: 0.18),
          side: BorderSide(
            color: filter.contains(status) ? palette.accent : palette.border,
          ),
          labelStyle: GoogleFonts.barlowCondensed(
            color: filter.contains(status) ? palette.accent : palette.textMuted,
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 1.2,
          ),
        );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip(TrainerLinkStatus.active, 'ACTIVOS'),
        chip(TrainerLinkStatus.paused, 'PAUSADOS'),
        chip(TrainerLinkStatus.terminated, 'HISTORIAL'),
      ],
    );
  }
}

// ─── Active students section ─────────────────────────────────────────────────
//
// Section headers were intentionally omitted — the FilterChip row already
// labels each section (ACTIVOS / PAUSADOS / HISTORIAL). Duplicating the
// label as a section header would just add visual noise and made the widget
// tests have to fight `findsOneWidget` vs `findsNWidgets(2)` matchers.

class _ActiveStudentsList extends ConsumerWidget {
  const _ActiveStudentsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final filter = ref.watch(_statusFilterProvider);
    if (!filter.contains(TrainerLinkStatus.active)) {
      return const SizedBox.shrink();
    }

    final linksAsync = ref.watch(trainerLinksStreamProvider);
    return linksAsync.when(
      loading: () => const _SectionLoading(),
      error: (_, __) =>
          const _SectionError(message: 'No pudimos cargar tus alumnos.'),
      data: (links) {
        final active =
            links.where((l) => l.status == TrainerLinkStatus.active).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (active.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  'Sin alumnos activos por ahora.',
                  style: TextStyle(color: palette.textMuted),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ...active.map((l) => _StudentTile(link: l)),
          ],
        );
      },
    );
  }
}

// ─── Paused students section ─────────────────────────────────────────────────

class _PausedStudentsList extends ConsumerWidget {
  const _PausedStudentsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final filter = ref.watch(_statusFilterProvider);
    if (!filter.contains(TrainerLinkStatus.paused)) {
      return const SizedBox.shrink();
    }

    final linksAsync = ref.watch(trainerLinksStreamProvider);
    return linksAsync.maybeWhen(
      data: (links) {
        final paused =
            links.where((l) => l.status == TrainerLinkStatus.paused).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (paused.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  'No hay alumnos pausados.',
                  style: TextStyle(color: palette.textMuted),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ...paused.map((l) => _PausedStudentTile(link: l)),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

// ─── Historial (terminated) section ──────────────────────────────────────────

class _HistorialList extends ConsumerWidget {
  const _HistorialList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final filter = ref.watch(_statusFilterProvider);
    if (!filter.contains(TrainerLinkStatus.terminated)) {
      return const SizedBox.shrink();
    }

    final linksAsync = ref.watch(trainerLinksStreamProvider);
    return linksAsync.maybeWhen(
      data: (links) {
        final terminated = links
            .where((l) => l.status == TrainerLinkStatus.terminated)
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (terminated.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  'Sin vínculos terminados todavía.',
                  style: TextStyle(color: palette.textMuted),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ...terminated.map((l) => _TerminatedStudentTile(link: l)),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

// ─── Section helpers (loading / error) ───────────────────────────────────────

class _SectionLoading extends StatelessWidget {
  const _SectionLoading();
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
    );
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Text(
        message,
        style: TextStyle(color: palette.textMuted),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ─── Active student tile (with Pausar + Terminar) ────────────────────────────

class _StudentTile extends ConsumerWidget {
  const _StudentTile({required this.link});
  final TrainerLink link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final pubAsync = ref.watch(userPublicProfileProvider(link.athleteId));
    final name = pubAsync.valueOrNull?.displayName ?? 'Atleta';
    final avatar = pubAsync.valueOrNull?.avatarUrl;

    Future<void> handlePause() async {
      final ok = await _confirmAction(
        context,
        title: 'Pausar vínculo',
        body:
            'El alumno verá el plan pero no podrá registrar sesiones nuevas hasta que reanudes el vínculo.',
        confirmLabel: 'Confirmar',
      );
      if (!ok) return;
      try {
        await ref.read(trainerLinkRepositoryProvider).pause(link.id);
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No pudimos pausar el vínculo.')),
        );
      }
    }

    Future<void> handleTerminate() async {
      final ok = await _confirmAction(
        context,
        title: 'Terminar vínculo',
        body: 'Esta acción no se puede deshacer. El historial se conserva.',
        confirmLabel: 'Confirmar',
      );
      if (!ok) return;
      try {
        await ref
            .read(trainerLinkRepositoryProvider)
            .terminate(link.id, reason: 'trainer-terminated');
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No pudimos terminar el vínculo.')),
        );
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          PostAvatar(
            authorDisplayName: name,
            authorAvatarUrl: avatar,
            size: 44,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Vinculado desde ${_formatPauseDate(link.acceptedAt ?? link.requestedAt)}',
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: handlePause,
            style: TextButton.styleFrom(foregroundColor: palette.textMuted),
            child: const Text('Pausar'),
          ),
          TextButton(
            onPressed: handleTerminate,
            style: TextButton.styleFrom(foregroundColor: palette.highlight),
            child: const Text('Terminar vínculo'),
          ),
        ],
      ),
    );
  }
}

// ─── Paused student tile (with Reanudar + Terminar) ──────────────────────────

class _PausedStudentTile extends ConsumerWidget {
  const _PausedStudentTile({required this.link});
  final TrainerLink link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final pubAsync = ref.watch(userPublicProfileProvider(link.athleteId));
    final name = pubAsync.valueOrNull?.displayName ?? 'Atleta';
    final avatar = pubAsync.valueOrNull?.avatarUrl;

    Future<void> handleResume() async {
      final ok = await _confirmAction(
        context,
        title: 'Reanudar vínculo',
        body: pubAsync.valueOrNull != null
            ? '¿Reanudar el vínculo con $name?'
            : '¿Reanudar el vínculo?',
        confirmLabel: 'Confirmar',
      );
      if (!ok) return;
      try {
        await ref.read(trainerLinkRepositoryProvider).resume(link.id);
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No pudimos reanudar el vínculo.')),
        );
      }
    }

    Future<void> handleTerminate() async {
      final ok = await _confirmAction(
        context,
        title: 'Terminar vínculo',
        body: 'Esta acción no se puede deshacer. El historial se conserva.',
        confirmLabel: 'Confirmar',
      );
      if (!ok) return;
      try {
        await ref
            .read(trainerLinkRepositoryProvider)
            .terminate(link.id, reason: 'trainer-terminated');
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No pudimos terminar el vínculo.')),
        );
      }
    }

    final pausedAt = link.pausedAt;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          PostAvatar(
            authorDisplayName: name,
            authorAvatarUrl: avatar,
            size: 44,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  pausedAt != null
                      ? 'Pausado el ${_formatPauseDate(pausedAt)}'
                      : 'Pausado',
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: handleResume,
            style: TextButton.styleFrom(foregroundColor: palette.accent),
            child: const Text('Reanudar'),
          ),
          TextButton(
            onPressed: handleTerminate,
            style: TextButton.styleFrom(foregroundColor: palette.highlight),
            child: const Text('Terminar vínculo'),
          ),
        ],
      ),
    );
  }
}

// ─── Terminated student tile (historial — read-only) ─────────────────────────

class _TerminatedStudentTile extends ConsumerWidget {
  const _TerminatedStudentTile({required this.link});
  final TrainerLink link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final pubAsync = ref.watch(userPublicProfileProvider(link.athleteId));
    final name = pubAsync.valueOrNull?.displayName ?? 'Atleta';
    final avatar = pubAsync.valueOrNull?.avatarUrl;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Opacity(
            opacity: 0.65,
            child: PostAvatar(
              authorDisplayName: name,
              authorAvatarUrl: avatar,
              size: 40,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _reasonDisplay(link.terminationReason),
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Pending requests section ────────────────────────────────────────────────

/// Solicitudes pendientes — solo aparece cuando hay al menos una.
/// Cada solicitud muestra avatar + nombre + Aceptar/Rechazar.
/// Acciones disparan `TrainerLinkRepository.accept()` / `.decline()`;
/// el stream provider refresca solo, sin invalidate manual (ADR-CHLM-03).
class _PendingRequestsList extends ConsumerWidget {
  const _PendingRequestsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final linksAsync = ref.watch(trainerLinksStreamProvider);

    return linksAsync.maybeWhen(
      data: (links) {
        final pending =
            links.where((l) => l.status == TrainerLinkStatus.pending).toList();
        if (pending.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'SOLICITUDES PENDIENTES · ${pending.length}',
              style: GoogleFonts.barlowCondensed(
                color: palette.highlight,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            ...pending.map(
              (link) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _PendingRequestTile(link: link),
              ),
            ),
            const SizedBox(height: 18),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _PendingRequestTile extends ConsumerStatefulWidget {
  const _PendingRequestTile({required this.link});
  final TrainerLink link;

  @override
  ConsumerState<_PendingRequestTile> createState() =>
      _PendingRequestTileState();
}

class _PendingRequestTileState extends ConsumerState<_PendingRequestTile> {
  bool _busy = false;

  Future<void> _accept() async {
    if (_busy) return;
    setState(() => _busy = true);
    final repo = ref.read(trainerLinkRepositoryProvider);
    try {
      await repo.accept(widget.link.id);
      ref
          .read(analyticsServiceProvider)
          .logLinkAccepted(linkId: widget.link.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vínculo aceptado.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos aceptar el vínculo.')),
      );
    }
  }

  Future<void> _decline() async {
    if (_busy) return;
    setState(() => _busy = true);
    final repo = ref.read(trainerLinkRepositoryProvider);
    try {
      await repo.decline(widget.link.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solicitud rechazada.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos rechazar la solicitud.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final pubAsync =
        ref.watch(userPublicProfileProvider(widget.link.athleteId));
    final name = pubAsync.valueOrNull?.displayName ?? 'Atleta';
    final avatar = pubAsync.valueOrNull?.avatarUrl;

    return Container(
      key: Key('pending_request_${widget.link.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.highlight.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          PostAvatar(
            authorDisplayName: name,
            authorAvatarUrl: avatar,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Quiere vincularse con vos',
                  style: TextStyle(
                    color: palette.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_busy)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: palette.accent,
              ),
            )
          else ...[
            TextButton(
              key: Key('decline_${widget.link.id}'),
              onPressed: _decline,
              style: TextButton.styleFrom(
                foregroundColor: palette.textMuted,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: const Text('Rechazar'),
            ),
            const SizedBox(width: 4),
            ElevatedButton(
              key: Key('accept_${widget.link.id}'),
              onPressed: _accept,
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: palette.bg,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: const StadiumBorder(),
              ),
              child: const Text('Aceptar'),
            ),
          ],
        ],
      ),
    );
  }
}
