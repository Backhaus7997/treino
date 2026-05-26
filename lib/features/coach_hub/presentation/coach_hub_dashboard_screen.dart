import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../coach/application/trainer_link_providers.dart';
import '../../coach/domain/trainer_link.dart';
import '../../coach/domain/trainer_link_status.dart';
import '../../feed/presentation/widgets/post_avatar.dart';
import '../../profile/application/user_providers.dart';
import '../../profile/application/user_public_profile_providers.dart';

/// Landing dashboard del Coach Hub.
///
/// MVP minimalista — solo confirma que el ecosistema funciona:
/// - Bienvenida con displayName del PF
/// - Lista de alumnos activos (consume `linksForTrainerProvider`)
/// - Sign-out
///
/// NO incluye editor de planes ni uploader de Excel — eso es Etapa 8.
class CoachHubDashboardScreen extends ConsumerWidget {
  const CoachHubDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final profileAsync = ref.watch(userProfileProvider);
    final displayName = profileAsync.valueOrNull?.displayName ?? 'PF';
    final uid = profileAsync.valueOrNull?.uid;

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Padding(
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
                  const SizedBox(height: 24),
                  // Alumnos section
                  Text(
                    'TUS ALUMNOS',
                    style: GoogleFonts.barlowCondensed(
                      color: palette.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (uid == null)
                    Text(
                      'Cargando...',
                      style: TextStyle(color: palette.textMuted),
                    )
                  else
                    Expanded(child: _ActiveStudentsList(trainerId: uid)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveStudentsList extends ConsumerWidget {
  const _ActiveStudentsList({required this.trainerId});
  final String trainerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final linksAsync = ref.watch(linksForTrainerProvider(trainerId));

    return linksAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
      error: (_, __) => Text(
        'No pudimos cargar tus alumnos.',
        style: TextStyle(color: palette.textMuted),
      ),
      data: (links) {
        final active = links
            .where((l) => l.status == TrainerLinkStatus.active)
            .toList();
        if (active.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    TreinoIcon.users,
                    color: palette.textMuted,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Sin alumnos activos por ahora.',
                    style: TextStyle(color: palette.textMuted),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Cuando un atleta acepte tu vínculo, lo vas a ver acá.',
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.separated(
          itemCount: active.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            color: palette.border,
          ),
          itemBuilder: (_, i) => _StudentTile(link: active[i]),
        );
      },
    );
  }
}

class _StudentTile extends ConsumerWidget {
  const _StudentTile({required this.link});
  final TrainerLink link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final pubAsync = ref.watch(userPublicProfileProvider(link.athleteId));
    final name = pubAsync.valueOrNull?.displayName ?? 'Atleta';
    final avatar = pubAsync.valueOrNull?.avatarUrl;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
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
                  'Vinculado desde ${_formatDate(link.acceptedAt ?? link.requestedAt)}',
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

  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }
}
