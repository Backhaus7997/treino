import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../auth/application/auth_providers.dart';
import '../../workout/application/assigned_routine_providers.dart';
import '../../workout/presentation/widgets/routine_card.dart';

/// Lists trainer-assigned plans for the authenticated athlete.
///
/// REQ-PSR-020: only `source == 'trainer-assigned' AND assignedTo == myUid`.
/// REQ-PSR-021: renders empty state when no plans exist.
/// Reuses [RoutineCard] and [assignedRoutinesProvider] from the workout feature.
/// // i18n: Fase 6 Etapa 3
class ProfileRoutinesScreen extends ConsumerWidget {
  const ProfileRoutinesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final myUid = ref.watch(authStateChangesProvider).valueOrNull?.uid ?? '';

    final routinesAsync = ref.watch(assignedRoutinesProvider(myUid));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: GestureDetector(
            onTap: () => context.pop(),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Icon(TreinoIcon.back, size: 20, color: palette.textPrimary),
                const SizedBox(width: 14),
                Text(
                  'MIS RUTINAS', // i18n: Fase 6 Etapa 3
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Body
        Expanded(
          child: routinesAsync.when(
            loading: () => Center(
              child: CircularProgressIndicator(
                color: palette.accent,
              ),
            ),
            error: (_, __) => Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'No pudimos cargar tus rutinas. Intentá de nuevo.', // i18n: Fase 6 Etapa 3
                  textAlign: TextAlign.center,
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 14,
                    color: palette.textMuted,
                  ),
                ),
              ),
            ),
            data: (routines) {
              if (routines.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Tu PF todavía no te asignó ninguna rutina.', // i18n: Fase 6 Etapa 3
                      textAlign: TextAlign.center,
                      style: GoogleFonts.barlow(
                        fontWeight: FontWeight.w400,
                        fontSize: 14,
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                itemCount: routines.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => RoutineCard(routine: routines[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}
