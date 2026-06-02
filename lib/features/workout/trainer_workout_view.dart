import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_palette.dart';
import 'presentation/workout_strings.dart';
import '../../core/widgets/treino_icon.dart';
import '../coach/presentation/widgets/athlete_picker_sheet.dart';
import '../profile/application/user_public_profile_providers.dart';
import 'application/routine_providers.dart';
import 'application/session_providers.dart' show currentUidProvider;
import 'domain/routine.dart';

/// Trainer-specific workout tab — replaces the athlete WORKOUT body (rutina /
/// plantillas / historial) with a "Crear planes" surface. The trainer should
/// not see athlete-mode controls (no EMPEZAR, no historial propio); their
/// workout tab is dedicated to building and assigning routines.
///
/// Two side-by-side surfaces:
///   * **Asignar a un alumno** — quick jump to ALUMNOS to build a plan
///     directly inside an athlete's profile.
///   * **Tu biblioteca de plantillas** — reusable plans the PF saves
///     without assigning to anyone. Each card has an "Asignar a alumno"
///     CTA that copies the template into a fresh trainer-assigned plan.
class TrainerWorkoutView extends ConsumerWidget {
  const TrainerWorkoutView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final uid = ref.watch(currentUidProvider) ?? '';
    final templatesAsync = uid.isEmpty
        ? const AsyncValue<List<Routine>>.data(<Routine>[])
        : ref.watch(trainerTemplatesStreamProvider(uid));
    final sharedFlag = uid.isEmpty
        ? false
        : (ref.watch(userPublicProfileProvider(uid)).valueOrNull
                ?.sharedTemplatesWithAthletes ??
            false);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 20),
        physics: const ClampingScrollPhysics(),
        children: [
          Text(
            'CREAR PLANES',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 28,
              letterSpacing: 0.5,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tu espacio para armar plantillas de rutina y asignarlas a tus alumnos.',
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w400,
              fontSize: 14,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 20),
          _AssignFromAlumnoCard(palette: palette),
          const SizedBox(height: 12),
          _TemplateLibrarySection(
            palette: palette,
            templatesAsync: templatesAsync,
            uid: uid,
            sharedWithAthletes: sharedFlag,
          ),
        ],
      ),
    );
  }
}

class _AssignFromAlumnoCard extends StatelessWidget {
  const _AssignFromAlumnoCard({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.accent, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(TreinoIcon.users, size: 20, color: palette.accent),
              const SizedBox(width: 8),
              Text(
                'ASIGNAR A UN ALUMNO',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: palette.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Elegí un alumno y armale el plan en su perfil. La plantilla queda guardada y la podés reutilizar.',
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w400,
              fontSize: 13,
              height: 1.4,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => context.go('/coach?tab=alumnos'),
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: palette.bg,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9999),
                ),
              ),
              child: Text(
                'VER ALUMNOS',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplateLibrarySection extends ConsumerWidget {
  const _TemplateLibrarySection({
    required this.palette,
    required this.templatesAsync,
    required this.uid,
    required this.sharedWithAthletes,
  });

  final AppPalette palette;
  final AsyncValue<List<Routine>> templatesAsync;
  final String uid;
  final bool sharedWithAthletes;

  Future<void> _onToggleShared(
      BuildContext context, WidgetRef ref, bool value) async {
    if (uid.isEmpty) return;
    try {
      await ref
          .read(userPublicProfileRepositoryProvider)
          .setSharedTemplatesWithAthletes(uid, value);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value
                ? 'Tus alumnos ya pueden ver todas tus plantillas.'
                : 'Tus plantillas vuelven a ser privadas.',
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pudimos actualizar la configuración.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(18),
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
                  'TU BIBLIOTECA DE PLANTILLAS',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 1.2,
                    color: palette.textMuted,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: () => context.push('/workout/template-editor'),
                icon: Icon(TreinoIcon.plus,
                    size: 14, color: palette.accent),
                label: Text(
                  'NUEVA',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 1.0,
                    color: palette.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _SharedToggleRow(
            palette: palette,
            value: sharedWithAthletes,
            enabled: uid.isNotEmpty,
            onChanged: (v) => _onToggleShared(context, ref, v),
          ),
          const SizedBox(height: 8),
          templatesAsync.when(
            loading: () => Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.2, color: palette.accent),
                ),
              ),
            ),
            error: (_, __) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No pudimos cargar tus plantillas.',
                style: GoogleFonts.barlow(
                    color: palette.textMuted, fontSize: 13),
              ),
            ),
            data: (templates) {
              if (templates.isEmpty) {
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Todavía no creaste ninguna plantilla. Pegale a NUEVA para armar la primera.',
                    style: GoogleFonts.barlow(
                      fontWeight: FontWeight.w400,
                      fontSize: 13,
                      height: 1.4,
                      color: palette.textPrimary,
                    ),
                  ),
                );
              }
              return Column(
                children: [
                  for (final t in templates) ...[
                    _TemplateCard(template: t, palette: palette),
                    const SizedBox(height: 8),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Inline row with a short label + Cupertino-style Switch driving the
/// trainer's `sharedTemplatesWithAthletes` flag. Lives inside the template
/// library card so the trainer sees the toggle right next to the templates
/// it affects.
class _SharedToggleRow extends StatelessWidget {
  const _SharedToggleRow({
    required this.palette,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final AppPalette palette;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Visible para tus alumnos',
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value
                    ? 'Tus alumnos ven todas tus plantillas en su Workout.'
                    : 'Solo vos ves estas plantillas.',
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w400,
                  fontSize: 11,
                  height: 1.3,
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: enabled ? onChanged : null,
          activeThumbColor: palette.accent,
        ),
      ],
    );
  }
}

class _TemplateCard extends ConsumerStatefulWidget {
  const _TemplateCard({required this.template, required this.palette});

  final Routine template;
  final AppPalette palette;

  @override
  ConsumerState<_TemplateCard> createState() => _TemplateCardState();
}

class _TemplateCardState extends ConsumerState<_TemplateCard> {
  bool _assigning = false;

  Future<void> _onAssign(BuildContext context) async {
    final athleteId = await showAthletePickerSheet(context);
    if (athleteId == null || !mounted) return;
    setState(() => _assigning = true);
    try {
      await ref
          .read(routineRepositoryProvider)
          .assignTemplateToAthlete(
            template: widget.template,
            athleteId: athleteId,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plantilla asignada al alumno.')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos asignar la plantilla.')),
      );
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final t = widget.template;
    final daysCount = t.days.length;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.barlow(
                    color: palette.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${t.split ?? WorkoutStrings.splitFallback} · $daysCount día${daysCount == 1 ? '' : 's'}',
                  style: GoogleFonts.barlow(
                    color: palette.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _assigning ? null : () => _onAssign(context),
            style: TextButton.styleFrom(
              foregroundColor: palette.accent,
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
            ),
            child: _assigning
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: palette.accent),
                  )
                : Text(
                    'ASIGNAR',
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      letterSpacing: 0.8,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
