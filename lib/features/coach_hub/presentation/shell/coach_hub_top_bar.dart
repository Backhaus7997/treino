import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/application/sidebar_collapsed_provider.dart';
import 'package:treino/features/profile/application/user_providers.dart';

import 'coach_hub_breadcrumb.dart';
import 'responsive.dart' as rsp;

/// Top bar del Coach Hub web (REQ-CHW-TOPBAR-001). 64 px de alto.
///
/// - **Izquierda**: toggle del sidebar (chevron). Deshabilitado en viewport
///   compact, donde el sidebar queda forzado a colapsado (ADR-CHW-004).
/// - **Centro**: [CoachHubBreadcrumb].
/// - **Derecha**: campana inerte (ODQ-4, sin badge) + menú de usuario con
///   "Salir" (mismo `FirebaseAuth.instance.signOut()` que dashboard/not-allowed).
class CoachHubTopBar extends ConsumerWidget {
  const CoachHubTopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final viewport = rsp.viewportFor(MediaQuery.sizeOf(context).width);
    final prefsReady = ref.watch(sharedPreferencesProvider).hasValue;

    // Mismo gateo defensivo que el sidebar: si prefs no resolvió, default
    // expandido (false) para no romper con `requireValue`.
    final collapsed = prefsReady ? ref.watch(sidebarCollapsedProvider) : false;

    // En compact el sidebar está forzado a colapsado; el toggle no aplica.
    final canToggle = viewport == rsp.Viewport.desktop && prefsReady;

    final displayName =
        ref.watch(userProfileProvider).valueOrNull?.displayName?.trim();
    final initial = (displayName != null && displayName.isNotEmpty)
        ? displayName.substring(0, 1).toUpperCase()
        : '?';

    return Container(
      height: 64,
      color: palette.bg,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Contraer/expandir menú', // i18n: Fase W1
            icon: Icon(
              collapsed ? TreinoIcon.chevronRight : TreinoIcon.chevronLeft,
              color: palette.textMuted,
            ),
            onPressed: canToggle
                ? () => ref.read(sidebarCollapsedProvider.notifier).toggle()
                : null,
          ),
          const SizedBox(width: 4),
          const Expanded(child: CoachHubBreadcrumb()),
          IconButton(
            tooltip: 'Notificaciones', // i18n: Fase W1
            icon: Icon(TreinoIcon.bell, color: palette.textMuted),
            onPressed: () {}, // ODQ-4: visible pero inerte en W1
          ),
          PopupMenuButton<String>(
            tooltip: 'Cuenta', // i18n: Fase W1
            onSelected: (value) {
              if (value == 'signout') {
                FirebaseAuth.instance.signOut();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(
                value: 'signout',
                child: Row(
                  children: [
                    Icon(TreinoIcon.signOut,
                        size: 18, color: palette.textPrimary),
                    const SizedBox(width: 8),
                    const Text('Salir'), // i18n: Fase W1
                  ],
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: palette.bgCard,
                child: Text(
                  initial,
                  style: TextStyle(
                    color: palette.accent,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
