// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/presentation/widgets/athlete_picker_sheet.dart';
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.centerRight,
            child: _NuevaPlantillaButton(palette: palette),
          ),
        ),
        Expanded(
          child: templatesAsync.when(
            loading: () =>
                Center(child: CircularProgressIndicator(color: palette.accent)),
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
                    'Todavía no creaste plantillas.\n'
                    'Tocá "Nueva plantilla" para armar una.', // i18n
                    textAlign: TextAlign.center,
                    style: GoogleFonts.barlow(
                      color: palette.textMuted,
                      fontSize: 14,
                    ),
                  ),
                );
              }

              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
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
                    onTap: () => showTemplateDetailDialog(
                      context,
                      routine,
                      onEdit: () =>
                          context.push('/template-editor/${routine.id}'),
                      onUse: () =>
                          _assignTemplateToAthlete(context, ref, routine),
                      onDelete: () => _deleteTemplate(context, ref, routine),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Opens the athlete picker and, on a pick, copies [template] into a
/// trainer-assigned routine for that athlete via the repository's
/// assignTemplateToAthlete. Mirrors mobile's template-card "Asignar"
/// (trainer_workout_view.dart _onAssign): same picker, same repo call, same
/// success/error copy. The template is left untouched, so it can be assigned to
/// other athletes later.
Future<void> _assignTemplateToAthlete(
  BuildContext context,
  WidgetRef ref,
  Routine template,
) async {
  final athleteId = await showAthletePickerSheet(context);
  if (athleteId == null || !context.mounted) return;
  // Capture the messenger before the async gap — context may unmount.
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref
        .read(routineRepositoryProvider)
        .assignTemplateToAthlete(template: template, athleteId: athleteId);
    messenger.showSnackBar(
      const SnackBar(content: Text('Plantilla asignada al alumno.')), // i18n
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('No pudimos asignar la plantilla.')), // i18n
    );
  }
}

/// Confirms, then deletes [template] via the repository's `deleteRoutine`.
/// Mirrors mobile's template-card delete (trainer_workout_view.dart _onDelete):
/// same confirmation, same repo call, same success/error copy. Routines already
/// assigned from this template keep working (slots denormalize name/group).
Future<void> _deleteTemplate(
  BuildContext context,
  WidgetRef ref,
  Routine template,
) async {
  final palette = AppPalette.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: palette.bgCard,
      title: Text(
        'Eliminar plantilla', // i18n
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: palette.textPrimary,
        ),
      ),
      content: Text(
        '¿Eliminar "${template.name}"? No se puede deshacer. Las rutinas ya '
        'asignadas a partir de ella no se tocan.', // i18n
        style: GoogleFonts.barlow(color: palette.textMuted, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(
            'Cancelar', // i18n
            style: GoogleFonts.barlow(color: palette.textMuted),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(
            'Eliminar', // i18n
            style: GoogleFonts.barlow(
              color: palette.danger,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  // Capture the messenger before the async gap — context may unmount.
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(routineRepositoryProvider).deleteRoutine(template.id);
    messenger.showSnackBar(
      const SnackBar(content: Text('Plantilla eliminada.')), // i18n
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('No pudimos eliminar la plantilla.')), // i18n
    );
  }
}

/// "Nueva plantilla" → opens the routine editor in template mode (no athlete).
class _NuevaPlantillaButton extends StatelessWidget {
  const _NuevaPlantillaButton({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      key: const Key('nueva_plantilla_button'),
      onPressed: () => context.push('/template-editor'),
      icon: Icon(TreinoIcon.plus, size: 16, color: palette.accent),
      label: Text(
        'Nueva plantilla', // i18n
        style: GoogleFonts.barlow(
          color: palette.accent,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: palette.accent.withValues(alpha: 0.5)),
        ),
      ),
    );
  }
}
