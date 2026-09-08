import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../core/widgets/motion/treino_tappable.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../application/custom_exercise_providers.dart';
import '../application/session_providers.dart' show currentUidProvider;
import '../domain/custom_exercise.dart';
import '../domain/muscle_group.dart';

/// Trainer's personal exercise library — list + entry point to create more.
///
/// ## Modo selección
///
/// Borrar de a uno obligaba a entrar al editor, borrar, volver, y repetir. Con
/// una biblioteca de decenas de ejercicios propios eso son cuatro toques por
/// ejercicio. El modo selección lo baja a uno por ejercicio más una
/// confirmación para todo el lote.
///
/// Se entra por el botón SELECCIONAR del header o con un long-press sobre
/// cualquier tarjeta —el gesto que ya espera cualquiera que use un teléfono— y
/// se sale con CANCELAR, con el back del sistema, o cuando el lote se borra.
class MyExercisesScreen extends ConsumerStatefulWidget {
  const MyExercisesScreen({super.key});

  @override
  ConsumerState<MyExercisesScreen> createState() => _MyExercisesScreenState();
}

class _MyExercisesScreenState extends ConsumerState<MyExercisesScreen> {
  /// Ids seleccionados. `null` = no estamos en modo selección.
  ///
  /// Un `Set?` y no un `Set` + `bool`: dos variables para un solo estado se
  /// desincronizan (modo prendido con set vacío ≠ modo apagado, y nada obliga
  /// a mantenerlos coherentes). Acá el modo ES la existencia del set.
  Set<String>? _selected;

  bool _deleting = false;

  bool get _selecting => _selected != null;

  void _enterSelection([String? firstId]) {
    setState(() => _selected = {if (firstId != null) firstId});
  }

  void _exitSelection() => setState(() => _selected = null);

  void _toggle(String id) {
    setState(() {
      final sel = _selected!;
      sel.contains(id) ? sel.remove(id) : sel.add(id);
    });
  }

  void _toggleAll(List<CustomExercise> items) {
    setState(() {
      final all = items.map((e) => e.id).toSet();
      // Si ya están todos, el botón deselecciona: un "seleccionar todos" que
      // no sabe volver atrás obliga a destildar de a uno.
      _selected = _selected!.length == all.length ? <String>{} : all;
    });
  }

  Future<void> _deleteSelected(List<CustomExercise> items) async {
    final ids = _selected!;
    if (ids.isEmpty || _deleting) return;

    final palette = AppPalette.of(context);
    final n = ids.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: Text(
          n == 1 ? 'Borrar ejercicio' : 'Borrar $n ejercicios', // i18n
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: palette.textPrimary,
          ),
        ),
        // Mismo texto que el borrado de a uno del editor: la consecuencia es
        // idéntica y contarla distinto sembraría la duda de si lo es.
        content: Text(
          'Esta acción no se puede deshacer. Los planes que ya tienen '
          '${n == 1 ? 'este ejercicio asignado no se ve' : 'estos ejercicios asignados no se ven'} '
          'afectados (guardan el nombre por separado).', // i18n
          style: GoogleFonts.barlow(fontSize: 14, color: palette.textPrimary),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancelar', // i18n
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: palette.textPrimary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.highlight,
              foregroundColor: palette.bg,
            ),
            child: Text(
              'Borrar', // i18n
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    final uid = ref.read(currentUidProvider) ?? '';
    final repo = ref.read(customExerciseRepositoryProvider);

    // Uno por uno y contando los que fallan: el repo no tiene borrado en lote,
    // y un `Future.wait` que explota en el primer error deja el resto en un
    // estado que nadie sabe cuál es. Así el mensaje puede decir la verdad.
    final failed = <String>[];
    for (final id in ids) {
      try {
        await repo.delete(trainerId: uid, id: id);
      } catch (_) {
        failed.add(id);
      }
    }

    if (!mounted) return;
    setState(() {
      _deleting = false;
      // Los que fallaron quedan seleccionados para poder reintentar sin
      // volver a buscarlos en la lista.
      _selected = failed.isEmpty ? null : failed.toSet();
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      content: Text(
        failed.isEmpty
            ? (n == 1 ? 'Ejercicio borrado' : '$n ejercicios borrados') // i18n
            : 'No pudimos borrar ${failed.length} de $n. Quedaron '
                'seleccionados.', // i18n
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final uid = ref.watch(currentUidProvider) ?? '';
    final exercisesAsync = uid.isEmpty
        ? const AsyncValue<List<CustomExercise>>.data(<CustomExercise>[])
        : ref.watch(customExercisesForTrainerStreamProvider(uid));
    final items = exercisesAsync.valueOrNull ?? const <CustomExercise>[];

    return PopScope(
      // El back del sistema sale del modo selección antes que de la pantalla:
      // salirse de la pantalla entera por querer cancelar una selección es la
      // clase de sorpresa que hace desconfiar del back.
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) _exitSelection();
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                IconButton(
                  tooltip: _selecting ? 'Cancelar selección' : l10n.commonBack,
                  icon: Icon(
                    _selecting ? TreinoIcon.close : TreinoIcon.back,
                    size: 20,
                    color: palette.textPrimary,
                  ),
                  onPressed: _deleting
                      ? null
                      : () {
                          if (_selecting) {
                            _exitSelection();
                          } else {
                            context.canPop()
                                ? context.pop()
                                : context.go('/profile');
                          }
                        },
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      _selecting
                          ? '${_selected!.length} SELECCIONADOS' // i18n
                          : 'MIS EJERCICIOS', // i18n
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        letterSpacing: 1.0,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                ),
                // La acción del header cambia con el modo: entrar a seleccionar,
                // o marcar/desmarcar todo. Sólo aparece si hay algo que
                // seleccionar — un "SELECCIONAR" sobre una lista vacía es un
                // botón que no puede hacer nada.
                if (items.isNotEmpty)
                  TextButton(
                    onPressed: _deleting
                        ? null
                        : () =>
                            _selecting ? _toggleAll(items) : _enterSelection(),
                    child: Text(
                      _selecting
                          ? (_selected!.length == items.length
                              ? 'NINGUNO' // i18n
                              : 'TODOS') // i18n
                          : 'SELECCIONAR', // i18n
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0.8,
                        color: palette.accentText,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: TreinoStateSwitcher(
              childKey: ValueKey(exercisesAsync.when(
                loading: () => 'loading',
                error: (_, __) => 'error',
                data: (items) => items.isEmpty ? 'empty' : 'data',
              )),
              child: exercisesAsync.when(
                loading: () => Center(
                    child: CircularProgressIndicator(color: palette.accent)),
                error: (_, __) => Center(
                  child: Text(
                    'No pudimos cargar tus ejercicios.',
                    style: GoogleFonts.barlow(
                        fontSize: 14, color: palette.textMuted),
                  ),
                ),
                data: (items) => items.isEmpty
                    ? _EmptyState(palette: palette)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (_, i) {
                          final ex = items[i];
                          return _ExerciseCard(
                            exercise: ex,
                            palette: palette,
                            selecting: _selecting,
                            selected: _selected?.contains(ex.id) ?? false,
                            onToggle: () => _toggle(ex.id),
                            onEnterSelection: () => _enterSelection(ex.id),
                          );
                        },
                      ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
              child: SizedBox(
                width: double.infinity,
                // El CTA del pie es UNO y cambia de trabajo con el modo: crear
                // cuando se navega, borrar cuando se selecciona. Dos botones
                // simultáneos —uno para crear y otro para borrar— ponen la
                // acción destructiva al lado de la constructiva, que es
                // exactamente donde no tiene que estar.
                child: _selecting
                    ? _DeleteSelectedButton(
                        palette: palette,
                        count: _selected!.length,
                        busy: _deleting,
                        onPressed: () => _deleteSelected(items),
                      )
                    : ElevatedButton(
                        onPressed: () =>
                            context.push('/profile/my-exercises/new'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: palette.accent,
                          foregroundColor:
                              TreinoButtonTokens.foreground(context),
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.full),
                          ),
                        ),
                        child: Text(
                          '+ NUEVO EJERCICIO', // i18n
                          style: GoogleFonts.barlowCondensed(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            letterSpacing: 0.8,
                          ),
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

/// CTA destructivo del pie en modo selección.
///
/// Deshabilitado con cero seleccionados en vez de oculto: si apareciera y
/// desapareciera, el pie saltaría de alto con cada tilde.
class _DeleteSelectedButton extends StatelessWidget {
  const _DeleteSelectedButton({
    required this.palette,
    required this.count,
    required this.busy,
    required this.onPressed,
  });

  final AppPalette palette;
  final int count;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = count > 0 && !busy;
    return ElevatedButton(
      key: const Key('my_exercises_delete_selected'),
      onPressed: enabled ? onPressed : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: palette.danger,
        foregroundColor: palette.onDanger,
        disabledBackgroundColor: palette.danger.withValues(alpha: 0.35),
        disabledForegroundColor: palette.onDanger.withValues(alpha: 0.6),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.full),
        ),
      ),
      child: busy
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: palette.onDanger,
              ),
            )
          : Text(
              count == 0
                  ? 'BORRAR' // i18n
                  : 'BORRAR ($count)', // i18n
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 0.8,
              ),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ExcludeSemantics(
              child:
                  Icon(TreinoIcon.sparkle, size: 48, color: palette.textMuted),
            ),
            const SizedBox(height: 18),
            Text(
              'Tu biblioteca está vacía.',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: palette.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Creá ejercicios con el nombre que vos usás y un video de referencia. Quedan guardados solo para vos.',
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w400,
                fontSize: 13,
                color: palette.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    required this.exercise,
    required this.palette,
    required this.selecting,
    required this.selected,
    required this.onToggle,
    required this.onEnterSelection,
  });

  final CustomExercise exercise;
  final AppPalette palette;

  /// La pantalla está en modo selección.
  final bool selecting;

  /// Este ejercicio está tildado. Sólo significa algo si [selecting].
  final bool selected;

  final VoidCallback onToggle;

  /// Long-press: entra al modo selección con ESTE ejercicio ya tildado. El
  /// gesto que ya espera cualquiera que use un teléfono.
  final VoidCallback onEnterSelection;

  @override
  Widget build(BuildContext context) {
    final hasVideo = exercise.videoUrl != null && exercise.videoUrl!.isNotEmpty;
    final label = [
      exercise.name,
      if (exercise.muscleGroup.isNotEmpty)
        muscleGroupLabel(exercise.muscleGroup),
    ].join(', ');

    return Material(
      color: palette.bgCard,
      borderRadius: BorderRadius.circular(14),
      child: Semantics(
        button: true,
        label: label,
        // En modo selección la tarjeta deja de ser un enlace y pasa a ser una
        // casilla: el lector de pantalla tiene que anunciar eso, no "botón".
        checked: selecting ? selected : null,
        child: TreinoTappable(
          // El tap ALTERNA en modo selección en vez de navegar. Que navegara
          // sacaría al usuario de la pantalla en medio de armar un lote.
          onTap: selecting
              ? onToggle
              : () => context.push('/profile/my-exercises/${exercise.id}'),
          onLongPress: selecting ? null : onEnterSelection,
          child: ExcludeSemantics(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  // El tilde ya dice cuál está elegido; el borde en acento lo
                  // dice de reojo, sin tener que leer cada casilla.
                  color:
                      selecting && selected ? palette.accent : palette.border,
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  if (selecting) ...[
                    Icon(
                      selected
                          ? TreinoIcon.checkCircleFill
                          : TreinoIcon.checkCircleEmpty,
                      size: 20,
                      color: selected ? palette.accent : palette.textMuted,
                    ),
                    const SizedBox(width: AppSpacing.s12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          exercise.name,
                          style: GoogleFonts.barlow(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: palette.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (exercise.muscleGroup.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            muscleGroupLabel(exercise.muscleGroup),
                            style: GoogleFonts.barlow(
                              fontWeight: FontWeight.w400,
                              fontSize: 12,
                              color: palette.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (hasVideo)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(TreinoIcon.play,
                          size: 16, color: palette.accent),
                    ),
                  // El chevron promete "te llevo a otra pantalla". En modo
                  // selección el tap no lleva a ningún lado, así que se va.
                  if (!selecting)
                    Icon(TreinoIcon.forward,
                        size: 16, color: palette.textMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
