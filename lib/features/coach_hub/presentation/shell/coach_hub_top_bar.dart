import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';

/// Top bar del Coach Hub web (REQ-CHW-TOPBAR-001). 64 px de alto.
///
/// - El toggle contraer/expandir del sidebar vive en el propio sidebar (ver
///   CoachHubSidebar). El breadcrumb de sección (`CoachHubBreadcrumb`) se quitó:
///   en W1 las rutas son de un solo nivel, así que siempre repetía el nombre
///   de la sección ya resaltada en el sidebar — pura duplicación sin info extra.
/// - **Derecha**: campana con badge de solicitudes de vínculo pendientes
///   (navega a `/solicitudes`, mirror del bell mobile → inbox de friend
///   requests) + menú de usuario con "Salir" (mismo
///   `FirebaseAuth.instance.signOut()` que dashboard/not-allowed).
class CoachHubTopBar extends ConsumerWidget {
  const CoachHubTopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);

    final displayName =
        ref.watch(userProfileProvider).valueOrNull?.displayName?.trim();
    final initial = (displayName != null && displayName.isNotEmpty)
        ? displayName.substring(0, 1).toUpperCase()
        : '?';
    final pending = ref.watch(pendingTrainerLinkCountProvider);

    return Container(
      height: 64,
      color: palette.bg,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const Spacer(),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: 'Notificaciones', // i18n: Fase W1
                icon: Icon(TreinoIcon.bell, color: palette.textMuted),
                onPressed: () => context.go('/solicitudes'),
              ),
              if (pending > 0)
                Positioned(
                  top: -4,
                  right: -5,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      constraints: const BoxConstraints(minWidth: 16),
                      decoration: BoxDecoration(
                        color: palette.accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        pending > 9 ? '9+' : '$pending',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.barlow(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          color: palette.bg,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
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
