// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n. No AppL10n (constraint C-6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/sections/routine_editor/routine_web_editability.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_status.dart';

/// Rutinas ya asignadas a UN alumno (Coach Hub web).
///
/// Punto intermedio del flujo del sidebar «Rutinas»: elegís un alumno y acá ves
/// sus rutinas activas. Desde acá podés crear una nueva (`/routine-editor/:id`)
/// o editar una existente (`/routine-editor/:id/:routineId`, solo las
/// "web-editables" — las periodizadas se editan en mobile, ver
/// [isRoutineWebEditable]).
class AthleteRoutinesScreen extends ConsumerWidget {
  const AthleteRoutinesScreen({super.key, required this.athleteId});

  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final profileAsync = ref.watch(userPublicProfileProvider(athleteId));
    final rawName = profileAsync.valueOrNull?.displayName ?? '';
    final name = rawName.isEmpty ? 'el alumno' : rawName; // i18n
    final routinesAsync = ref.watch(assignedRoutinesProvider(athleteId));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header: back + título + "Nueva rutina" ──────────────────────
          Row(
            children: [
              IconButton(
                icon: Icon(TreinoIcon.arrowLeft, color: palette.textMuted),
                onPressed: () => context.pop(),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Rutinas de $name', // i18n
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    letterSpacing: 0.8,
                    color: palette.textPrimary,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => context.push('/routine-editor/$athleteId'),
                icon: Icon(TreinoIcon.plus, size: 18, color: palette.bg),
                label: Text('Nueva rutina', // i18n
                    style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.bg,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          routinesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) =>
                _muted(palette, 'No pudimos cargar las rutinas.'), // i18n
            data: (routines) {
              final active = routines
                  .where((r) => r.status == RoutineStatus.active)
                  .toList();
              if (active.isEmpty) {
                return _muted(
                    palette, 'Todavía no le cargaste ninguna rutina.'); // i18n
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final routine in active)
                    _RoutineRow(routine: routine, athleteId: athleteId),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

Widget _muted(AppPalette palette, String text) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(text,
          style: GoogleFonts.barlow(color: palette.textMuted, fontSize: 14)),
    );

/// A single assigned routine — tap to edit (web-editable ones), or a muted
/// "editá en la app" hint for periodized / superset plans authored on mobile.
class _RoutineRow extends StatefulWidget {
  const _RoutineRow({required this.routine, required this.athleteId});

  final Routine routine;
  final String athleteId;

  @override
  State<_RoutineRow> createState() => _RoutineRowState();
}

class _RoutineRowState extends State<_RoutineRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final routine = widget.routine;
    final editable = isRoutineWebEditable(routine);
    final weeks = routine.numWeeks == 1 ? 'semana' : 'semanas'; // i18n

    final card = Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: _hovered && editable ? palette.borderHover : palette.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  routine.name,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.barlow(
                      color: palette.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${routine.days.length} días · ${routine.numWeeks} $weeks', // i18n
                  style: GoogleFonts.barlow(
                      color: palette.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          if (editable)
            Icon(TreinoIcon.edit, size: 18, color: palette.textMuted)
          else
            Text('Editá en la app', // i18n
                style:
                    GoogleFonts.barlow(color: palette.textMuted, fontSize: 12)),
        ],
      ),
    );

    // Periodized routines are view-only on web (no tap → no truncation risk).
    if (!editable) return card;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () =>
            context.push('/routine-editor/${widget.athleteId}/${routine.id}'),
        child: card,
      ),
    );
  }
}
