import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../profile/application/user_public_profile_providers.dart';
import '../../application/trainer_link_providers.dart';
import '../../domain/trainer_link_status.dart';

/// Shows a modal bottom sheet listing the trainer's currently active
/// alumnos. Returns the picked `athleteId`, or `null` if dismissed.
///
/// Used by the trainer's template library — tapping "Asignar a alumno"
/// on a template opens this sheet, and the selection drives the copy
/// from template → trainer-assigned routine.
Future<String?> showAthletePickerSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _AthletePickerSheetContent(),
  );
}

class _AthletePickerSheetContent extends ConsumerWidget {
  const _AthletePickerSheetContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final linksAsync = ref.watch(trainerLinksStreamProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: palette.espresso,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Text(
                  'ASIGNAR A UN ALUMNO',
                  style: GoogleFonts.barlowCondensed(
                    color: palette.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              Expanded(
                child: linksAsync.when(
                  loading: () => Center(
                    child: CircularProgressIndicator(color: palette.accent),
                  ),
                  error: (_, __) => Center(
                    child: Text(
                      'No pudimos cargar tus alumnos.',
                      style: GoogleFonts.barlow(
                          color: palette.textMuted, fontSize: 14),
                    ),
                  ),
                  data: (links) {
                    final active = links
                        .where((l) => l.status == TrainerLinkStatus.active)
                        .toList();
                    if (active.isEmpty) {
                      return _EmptyState(palette: palette);
                    }
                    return ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: active.length,
                      separatorBuilder: (_, __) =>
                          Divider(color: palette.border, height: 1),
                      itemBuilder: (context, index) {
                        final link = active[index];
                        return _AthleteTile(
                          athleteId: link.athleteId,
                          palette: palette,
                          onTap: () =>
                              Navigator.of(context).pop(link.athleteId),
                        );
                      },
                    );
                  },
                ),
              ),
              SizedBox(height: MediaQuery.of(context).viewPadding.bottom + 8),
            ],
          ),
        );
      },
    );
  }
}

class _AthleteTile extends ConsumerWidget {
  const _AthleteTile({
    required this.athleteId,
    required this.palette,
    required this.onTap,
  });

  final String athleteId;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userPublicProfileProvider(athleteId));
    final displayName =
        profileAsync.valueOrNull?.displayName?.trim().isNotEmpty == true
            ? profileAsync.valueOrNull!.displayName!
            : 'Alumno';
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: palette.bgCard,
        child: Icon(TreinoIcon.tabProfile, size: 18, color: palette.textMuted),
      ),
      title: Text(
        displayName,
        style: GoogleFonts.barlow(
          color: palette.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing:
          Icon(TreinoIcon.chevronRight, size: 14, color: palette.textMuted),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(TreinoIcon.users, size: 36, color: palette.textMuted),
          const SizedBox(height: 12),
          Text(
            'Todavía no tenés alumnos activos.',
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(
              color: palette.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Cuando alguien acepte tu vínculo vas a poder asignarle plantillas.',
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(
              color: palette.textMuted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
