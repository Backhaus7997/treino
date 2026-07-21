import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_palette.dart';
import '../../core/widgets/treino_icon.dart';
import '../auth/application/auth_providers.dart';
import '../coach/application/trainer_discovery_providers.dart';
import '../coach/application/trainer_link_providers.dart';
import '../coach/domain/trainer_link_status.dart';
import '../coach/domain/trainer_public_profile.dart';
import '../workout/application/session_providers.dart' show currentUidProvider;
import 'application/user_providers.dart';

/// Trainer profile screen — matches docs/app-trainer/screens/perfil/perfil.png.
///
/// Layout: TU CUENTA / YO header → identity card (avatar + name + ALUMNOS /
/// RATING) → PERFIL PÚBLICO card with visibility badge and VER PREVIEW /
/// EDITAR CTAs → menu list (Solicitudes / Disponibilidad / Planes / Configu-
/// ración / Cerrar sesión).
///
/// Wired sections:
///   - Avatar + display name (userProfileProvider)
///   - ALUMNOS count (trainerLinksStreamProvider filtered active)
///   - Pending requests badge (same provider filtered pending)
///   - Public profile visibility, location summary, online flag (trainerById)
///   - VER PREVIEW → /coach/trainer/:uid
///   - EDITAR → /profile/edit-personal (shared form; full trainer fields TBD)
///   - Disponibilidad → /profile/availability-editor (mirror of the /coach
///     route so the PERFIL tab stays highlighted — issue #387)
///   - Configuración por defecto → /profile/settings
///   - Cerrar sesión → AuthNotifier.signOut
///
/// Placeholder (snackbar "Próximamente"):
///   - RATING (no aggregate score model yet)
///   - Planes comerciales (no billing module)
///   - "Plan Pro" subtitle (no billing tier model — hardcoded literal)
class TrainerProfileView extends ConsumerWidget {
  const TrainerProfileView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final profileAsync = ref.watch(userProfileProvider);
    final linksAsync = ref.watch(trainerLinksStreamProvider);
    final uid = ref.watch(currentUidProvider) ?? '';
    final pubAsync = uid.isEmpty
        ? const AsyncValue<TrainerPublicProfile?>.data(null)
        : ref.watch(trainerByIdProvider(uid));

    final displayName = profileAsync.valueOrNull?.displayName ?? '';
    final initials = _initials(displayName);
    final links = linksAsync.valueOrNull ?? const [];
    final activeAlumnos =
        links.where((l) => l.status == TrainerLinkStatus.active).length;
    final pendingRequests =
        links.where((l) => l.status == TrainerLinkStatus.pending).length;
    final pub = pubAsync.valueOrNull;
    final isVisible = pub != null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        // Header — TU CUENTA / YO
        Text(
          'TU CUENTA',
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 1.2,
            color: palette.accent,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'YO',
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 28,
            letterSpacing: 0.5,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 18),

        // Identity card — avatar + name + stats
        _IdentityCard(
          initials: initials.isEmpty ? '·' : initials,
          displayName: displayName.isEmpty ? 'Coach' : displayName,
          activeAlumnos: activeAlumnos,
          palette: palette,
        ),
        const SizedBox(height: 14),

        // Perfil público card
        _PerfilPublicoCard(
          uid: uid,
          isVisible: isVisible,
          pub: pub,
          palette: palette,
        ),
        const SizedBox(height: 18),

        // Menu rows — each a standalone card with 10px gaps.
        _MenuRow(
          icon: TreinoIcon.users,
          label: 'Solicitudes entrantes',
          badge: pendingRequests > 0 ? '$pendingRequests' : null,
          onTap: () => context.go('/home'),
          palette: palette,
        ),
        const SizedBox(height: 10),
        _MenuRow(
          icon: TreinoIcon.bell,
          label: 'Disponibilidad',
          // /profile twin of /coach/availability-editor so the bottom bar
          // keeps PERFIL highlighted while the editor is open (issue #387).
          onTap: () => uid.isEmpty
              ? _toast(context, 'Iniciá sesión para configurar.')
              : context.push('/profile/availability-editor?trainerId=$uid'),
          palette: palette,
        ),
        const SizedBox(height: 10),
        _MenuRow(
          icon: TreinoIcon.sparkle,
          label: 'Mis ejercicios',
          onTap: () => context.push('/profile/my-exercises'),
          palette: palette,
        ),
        const SizedBox(height: 10),
        // "Planes comerciales" menu row REMOVED 2026-05-28 — the dual
        // pricing model (profile monthly rate + plan catalog) was confusing.
        // Trainer pricing now lives ONLY in the PERFIL PÚBLICO card EDITAR
        // CTA above. Plan catalog can come back in a later phase once we
        // build the athlete-side subscribe flow that justifies multi-tier.
        //
        // "Configuración por defecto" menu row REMOVED 2026-05-28 — main
        // PR#4 pivot deleted the /profile/settings route. Settings surface
        // deferred to a future SDD (notifications/theme/language).
        _MenuRow(
          icon: TreinoIcon.signOut,
          label: 'Cerrar sesión',
          color: palette.highlight,
          onTap: () => ref.read(authNotifierProvider.notifier).signOut(),
          palette: palette,
        ),
      ],
    );
  }
}

// ── Identity card ─────────────────────────────────────────────────────────────

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.initials,
    required this.displayName,
    required this.activeAlumnos,
    required this.palette,
  });

  final String initials;
  final String displayName;
  final int activeAlumnos;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  palette.highlight,
                  palette.highlight.withAlpha(180),
                ],
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 20,
                letterSpacing: 0.5,
                color: palette.bg,
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Name + tier + stats
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayName,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    letterSpacing: 0.3,
                    color: palette.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                // Hardcoded tier label — billing module not implemented yet.
                Text(
                  'Coach · Plan Pro',
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _IdentityStat(
                      value: '$activeAlumnos',
                      label: 'ALUMNOS',
                      color: palette.accent,
                      palette: palette,
                    ),
                    const SizedBox(width: 18),
                    _IdentityStat(
                      value: '—',
                      label: 'RATING',
                      color: palette.textPrimary,
                      palette: palette,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IdentityStat extends StatelessWidget {
  const _IdentityStat({
    required this.value,
    required this.label,
    required this.color,
    required this.palette,
  });

  final String value;
  final String label;
  final Color color;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: color,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 10,
            letterSpacing: 1.2,
            color: palette.textMuted,
          ),
        ),
      ],
    );
  }
}

// ── Perfil público card ───────────────────────────────────────────────────────

class _PerfilPublicoCard extends StatelessWidget {
  const _PerfilPublicoCard({
    required this.uid,
    required this.isVisible,
    required this.pub,
    required this.palette,
  });

  final String uid;
  final bool isVisible;
  final TrainerPublicProfile? pub;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'PERFIL PÚBLICO',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 1.2,
                    color: palette.textMuted,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: isVisible
                      ? palette.accent.withAlpha(40)
                      : palette.textMuted.withAlpha(40),
                  borderRadius: BorderRadius.circular(9999),
                  border: Border.all(
                    color: isVisible ? palette.accent : palette.border,
                    width: 1,
                  ),
                ),
                child: Text(
                  isVisible ? 'VISIBLE' : 'OCULTO',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 1.0,
                    color: isVisible ? palette.accent : palette.textMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _summary(pub),
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w400,
              fontSize: 13,
              height: 1.4,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isVisible && uid.isNotEmpty
                      ? () => context.push('/coach/trainer/$uid')
                      : null,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: palette.border, width: 1),
                    foregroundColor: palette.textPrimary,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                  child: Text(
                    'VER PREVIEW',
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
                  // Edit the trainer's PUBLIC profile (bio, specialty,
                  // multi-location, monthly price, online toggle). Wires the
                  // new ProfileEditTrainerScreen merged from main PR #102.
                  // The basic name/avatar form remains at /profile/edit-
                  // personal — accessible to the trainer if they go through
                  // the athlete-shared cuenta section, not from this CTA.
                  onPressed: () => context.push('/profile/edit-trainer'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: palette.bg,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                  child: Text(
                    'EDITAR',
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

  String _summary(TrainerPublicProfile? p) {
    if (p == null) {
      return 'Aún no creaste tu perfil público. Tocá EDITAR para empezar.';
    }
    final parts = <String>['Aparecés en Coach Discovery'];
    final hasLocations = p.trainerLocations.isNotEmpty;
    if (hasLocations) parts.add('Presencial');
    if (p.trainerOffersOnline) parts.add('Online');
    return parts.join(' · ');
  }
}

// ── Menu row ──────────────────────────────────────────────────────────────────

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.palette,
    this.badge,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final AppPalette palette;
  final String? badge;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? palette.textPrimary;
    return Material(
      color: palette.bgCard,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.border, width: 1),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    color: fg,
                  ),
                ),
              ),
              if (badge != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: palette.accent,
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: Text(
                    badge!,
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                      color: palette.bg,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              if (color == null)
                Icon(TreinoIcon.forward, size: 16, color: palette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}

String _initials(String name) {
  final clean = name.trim();
  if (clean.isEmpty) return '';
  final parts = clean.split(RegExp(r'\s+'));
  if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
  if (parts[0].length >= 2) {
    return parts[0].substring(0, 2).toUpperCase();
  }
  return parts[0].toUpperCase();
}
