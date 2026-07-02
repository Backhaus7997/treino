// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/domain/routine.dart';

import 'template_detail_dialog.dart';
import 'template_grid_card.dart';

/// Tab body for the "Templates Rutinas" tab of [BibliotecaWebScreen].
///
/// Watches [trainerTemplatesStreamProvider] (filtered to trainer-templates).
/// Layout: loading spinner / error text / GridView of [TemplateGridCard].
/// Empty-list → centered empty-state text.
///
/// REQ-BIBW-09, REQ-BIBW-11.
/// SCENARIO-BIBW-09a, SCENARIO-BIBW-09b, SCENARIO-BIBW-09c, SCENARIO-BIBW-11b.
class TemplatesTab extends ConsumerWidget {
  const TemplatesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final uid = ref.watch(currentUidProvider) ?? '';

    final templatesAsync = uid.isEmpty
        ? const AsyncValue<List<Routine>>.data([])
        : ref.watch(trainerTemplatesStreamProvider(uid));

    return templatesAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
      error: (e, _) => Center(
        child: Text(
          'Error al cargar plantillas.', // i18n
          style: GoogleFonts.barlow(
            color: palette.textMuted,
            fontSize: 14,
          ),
        ),
      ),
      data: (templates) {
        if (templates.isEmpty) {
          return Center(
            child: Text(
              'Todavía no creaste plantillas.', // i18n
              style: GoogleFonts.barlow(
                color: palette.textMuted,
                fontSize: 14,
              ),
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 360,
            childAspectRatio: 1.6,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: templates.length,
          itemBuilder: (context, index) {
            final routine = templates[index];
            return TemplateGridCard(
              routine: routine,
              onTap: () => showTemplateDetailDialog(context, routine),
            );
          },
        );
      },
    );
  }
}
