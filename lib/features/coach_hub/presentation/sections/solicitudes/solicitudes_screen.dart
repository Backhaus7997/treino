// NOTE: el Scaffold y el SafeArea los provee CoachHubScaffold (el shell).
// NO los agregues acá (ADR-CHW-005).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/core/widgets/motion/treino_tappable.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/widgets/pending_requests_list.dart';

/// Pantalla `/solicitudes` — lista de solicitudes de vínculo PENDIENTES,
/// alcanzada desde la campana del top bar (mirror de `FriendRequestsInboxScreen`
/// mobile, ver `feed/presentation/friend_requests_inbox_screen.dart`).
///
/// No tiene item de sidebar propio (ver `routes.dart`): la campana es la única
/// entrada, igual que el bell del feed mobile.
class SolicitudesScreen extends ConsumerWidget {
  const SolicitudesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final linksAsync = ref.watch(trainerLinksStreamProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SolicitudesHeader(palette: palette),
        Expanded(
          child: linksAsync.when(
            loading: () => Center(
              child: CircularProgressIndicator(color: palette.accent),
            ),
            error: (_, __) => Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'No pudimos cargar las solicitudes.', // i18n
                  style: GoogleFonts.barlow(
                    fontSize: 14,
                    color: palette.textMuted,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            data: (links) {
              final hasPending =
                  links.any((l) => l.status == TrainerLinkStatus.pending);
              if (!hasPending) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'No tenés solicitudes pendientes.', // i18n
                      style: GoogleFonts.barlow(
                        fontSize: 14,
                        color: palette.textMuted,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return const SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: PendingRequestsList(),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _SolicitudesHeader extends StatelessWidget {
  const _SolicitudesHeader({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Volver', // i18n
            child: TreinoTappable(
              // El bell hace context.go('/solicitudes') (no push), así que
              // el back vuelve al dashboard con el mismo mecanismo — mirror
              // del "‹ Alumnos" back de alumno_detail_screen.dart.
              onTap: () => context.go('/dashboard'),
              child: Container(
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                alignment: Alignment.centerLeft,
                child:
                    Icon(TreinoIcon.back, size: 20, color: palette.textPrimary),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            'SOLICITUDES', // i18n
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              letterSpacing: 1.2,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
