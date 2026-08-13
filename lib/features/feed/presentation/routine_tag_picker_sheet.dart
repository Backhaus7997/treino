import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../workout/application/user_routines_providers.dart';
import '../../workout/domain/routine.dart';
import '../domain/routine_tag.dart';

/// Opens the routine picker as a modal bottom sheet and resolves with the
/// [RoutineTag] the user chose, or `null` if they dismissed it without
/// choosing.
///
/// [uid] is the author's uid — feeds [userCreatedRoutinesProvider]. An empty
/// uid yields an empty list (the provider short-circuits), so the sheet just
/// shows the empty state instead of hitting Firestore.
Future<RoutineTag?> showRoutineTagPickerSheet({
  required BuildContext context,
  required String uid,
}) {
  final palette = AppPalette.of(context);
  return showModalBottomSheet<RoutineTag>(
    context: context,
    isScrollControlled: true,
    backgroundColor: palette.bgCard,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => RoutineTagPickerSheet(uid: uid),
  );
}

/// Bottom-sheet body that lists the athlete's own routines so they can tag one
/// on a manual post. Tapping a routine pops the sheet with the chosen
/// [RoutineTag].
class RoutineTagPickerSheet extends ConsumerWidget {
  const RoutineTagPickerSheet({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final routinesAsync = ref.watch(userCreatedRoutinesProvider(uid));

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Semantics(
              header: true,
              child: Text(
                'ELEGÍ UNA RUTINA',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  letterSpacing: 1.2,
                  color: palette.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 18),
            routinesAsync.when(
              loading: () => _SheetStatus(
                child: CircularProgressIndicator(color: palette.accent),
              ),
              error: (_, __) => _SheetMessage(
                message: 'No pudimos cargar tus rutinas. Intentá de nuevo.',
                palette: palette,
              ),
              data: (routines) => routines.isEmpty
                  ? _SheetMessage(
                      message:
                          'Todavía no tenés rutinas propias para etiquetar.',
                      palette: palette,
                    )
                  : Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: routines.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: palette.border,
                        ),
                        itemBuilder: (_, i) => _RoutineTile(
                          routine: routines[i],
                          palette: palette,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoutineTile extends StatelessWidget {
  const _RoutineTile({required this.routine, required this.palette});

  final Routine routine;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: routine.name,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(
          RoutineTag(routineId: routine.id, routineName: routine.name),
        ),
        behavior: HitTestBehavior.opaque,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Icon(
                    TreinoIcon.tabWorkout,
                    size: 18,
                    color: palette.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ExcludeSemantics(
                    child: Text(
                      routine.name,
                      style: GoogleFonts.barlow(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                ),
                ExcludeSemantics(
                  child: Icon(
                    TreinoIcon.chevronRight,
                    size: 18,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetStatus extends StatelessWidget {
  const _SheetStatus({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Center(child: child),
    );
  }
}

class _SheetMessage extends StatelessWidget {
  const _SheetMessage({required this.message, required this.palette});

  final String message;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Text(
        message,
        style: GoogleFonts.barlow(
          fontWeight: FontWeight.w400,
          fontSize: 14,
          color: palette.textMuted,
        ),
      ),
    );
  }
}
