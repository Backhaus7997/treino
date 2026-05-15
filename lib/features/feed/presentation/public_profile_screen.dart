import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../auth/application/auth_providers.dart';
import '../application/public_profile_providers.dart';
import 'widgets/public_profile_follow_button.dart';
import 'widgets/public_profile_hero.dart';
import 'widgets/public_profile_stats_row.dart';

/// Which tab is selected inside the public profile screen.
/// Private to this file — the screen and `_ProfileTabPills` are the only
/// consumers (REQ-PROFILE-TABS-001 forbids cross-feature reuse).
enum _ProfileTab { rutinas, actividad }

/// Per-target tab state. Family keyed by `targetUid` so two simultaneous
/// profile visits don't share state.
final _profileTabProvider =
    StateProvider.autoDispose.family<_ProfileTab, String>(
  (ref, _) => _ProfileTab.rutinas,
);

/// Public profile screen for a non-self user. Watches a single composed
/// view-model provider and routes data / loading / error to subtrees.
class PublicProfileScreen extends ConsumerWidget {
  const PublicProfileScreen({super.key, required this.targetUid});

  final String targetUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final viewAsync = ref.watch(publicProfileViewProvider(targetUid));

    return viewAsync.when(
      data: (view) {
        final viewerUid =
            ref.watch(authStateChangesProvider).valueOrNull?.uid ?? '';
        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PublicProfileHero(view: view),
              const SizedBox(height: 20),
              if (!view.isSelf) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: PublicProfileFollowButton(
                          friendship: view.friendship,
                          viewerUid: viewerUid,
                          targetUid: targetUid,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(child: _MessageButtonStub()),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: PublicProfileStatsRow(),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _ProfileTabPills(targetUid: targetUid),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _ProfileTabBody(targetUid: targetUid),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
      loading: () => Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
      error: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Center(
          child: Text(
            'No pudimos cargar este perfil.',
            style: GoogleFonts.barlow(
              fontSize: 14,
              color: palette.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _MessageButtonStub extends StatelessWidget {
  const _MessageButtonStub();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Opacity(
      opacity: 0.6,
      child: GestureDetector(
        onTap: null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: palette.border, width: 1),
          ),
          child: Center(
            child: Text(
              'MENSAJE',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 1.0,
                color: palette.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileTabPills extends ConsumerWidget {
  const _ProfileTabPills({required this.targetUid});

  final String targetUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(_profileTabProvider(targetUid));
    return Row(
      children: [
        Expanded(
          child: _ProfilePill(
            label: 'RUTINAS PÚBLICAS',
            isActive: tab == _ProfileTab.rutinas,
            onTap: () => ref
                .read(_profileTabProvider(targetUid).notifier)
                .state = _ProfileTab.rutinas,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ProfilePill(
            label: 'ACTIVIDAD',
            isActive: tab == _ProfileTab.actividad,
            onTap: () => ref
                .read(_profileTabProvider(targetUid).notifier)
                .state = _ProfileTab.actividad,
          ),
        ),
      ],
    );
  }
}

class _ProfilePill extends StatelessWidget {
  const _ProfilePill({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? palette.accent : palette.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? palette.accent : palette.border,
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1.0,
              color: isActive ? palette.bg : palette.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileTabBody extends ConsumerWidget {
  const _ProfileTabBody({required this.targetUid});

  final String targetUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(_profileTabProvider(targetUid));
    final palette = AppPalette.of(context);

    final copy = switch (tab) {
      _ProfileTab.rutinas => 'Aún no hay rutinas públicas.',
      _ProfileTab.actividad => 'Aún no hay actividad reciente.',
    };

    // Placeholder: real content wired in Fase 5 (routines) / Fase 4 (activity).
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(
        child: Text(
          copy,
          style: GoogleFonts.barlow(
            fontSize: 14,
            color: palette.textMuted,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
