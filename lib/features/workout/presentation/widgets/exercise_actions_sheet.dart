import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';

/// Una acción del menú de un ejercicio.
///
/// La hoja no sabe qué hace ninguna: recibe la lista y devuelve cuál se tocó.
/// Las acciones y su lógica siguen viviendo donde vivían — lo que cambia acá
/// es la presentación.
@immutable
class ExerciseAction {
  const ExerciseAction({
    required this.id,
    required this.label,
    required this.icon,
    this.enabled = true,
    this.danger = false,
  });

  /// Identifica la acción para el llamador. No se muestra.
  final Object id;
  final String label;
  final IconData icon;

  /// Cuando es false se pinta apagada y NO responde al tap. Un ítem que
  /// responde y no hace nada es peor que uno que se ve claramente inerte.
  final bool enabled;

  /// Acciones destructivas. Se pintan en `danger` y van últimas.
  final bool danger;
}

/// El menú de acciones de un ejercicio, como hoja.
///
/// Era un `PopupMenuButton`: un menú flotante de ítems de ~40 dp colgado de un
/// ícono de 20. La hoja usa el mismo chrome que "DATOS DEL PLAN" —fondo
/// `bgElevated`, radio superior, handle, título en Barlow Condensed— para que
/// las dos superficies modales del editor se lean como la misma cosa.
class ExerciseActionsSheet extends StatelessWidget {
  const ExerciseActionsSheet({
    required this.title,
    required this.actions,
    required this.onPick,
    super.key,
  });

  /// El nombre del ejercicio. Con la hoja abierta la card queda tapada, así
  /// que sin esto no se ve sobre cuál se está actuando.
  final String title;

  final List<ExerciseAction> actions;
  final void Function(Object id) onPick;

  /// Alto de cada ítem. El menú anterior daba ~40; la épica fija 48 para todo
  /// target interactivo.
  static const double kAltoItem = 48;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.s12),
          Center(
            child: Container(
              width: 40,
              height: AppSpacing.hairline,
              decoration: BoxDecoration(
                color: palette.borderStrong,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s18,
              AppSpacing.s14,
              AppSpacing.s18,
              AppSpacing.s8,
            ),
            child: Text(
              title,
              key: const Key('exercise_sheet_title'),
              style: GoogleFonts.barlowCondensed(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: palette.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          for (final action in actions)
            _Item(action: action, onTap: () => onPick(action.id)),
          const SizedBox(height: AppSpacing.s12),
        ],
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({required this.action, required this.onTap});

  final ExerciseAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = !action.enabled
        ? palette.textFaint
        : action.danger
        ? palette.danger
        : palette.textPrimary;

    return Semantics(
      button: true,
      enabled: action.enabled,
      label: action.label,
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: Key('exercise_sheet_action_${action.id}'),
          // Null y no un callback que no hace nada: es lo que hace que el
          // ripple tampoco aparezca, y que la acción se sienta inerte además
          // de verse inerte.
          onTap: action.enabled ? onTap : null,
          child: SizedBox(
            height: ExerciseActionsSheet.kAltoItem,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s18),
              child: Row(
                children: [
                  Icon(action.icon, size: 18, color: color),
                  const SizedBox(width: AppSpacing.s14),
                  Expanded(
                    child: Text(
                      action.label,
                      style: GoogleFonts.barlow(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Abre el menú de acciones de un ejercicio y devuelve la elegida, o null si
/// se cerró sin elegir.
///
/// El chrome —fondo, radio, `isScrollControlled`— replica el de "DATOS DEL
/// PLAN" a propósito: son las dos hojas del editor y tienen que leerse igual.
Future<Object?> showExerciseActionsSheet(
  BuildContext context, {
  required String title,
  required List<ExerciseAction> actions,
}) {
  final palette = AppPalette.of(context);
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    backgroundColor: palette.bgElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (ctx) => ExerciseActionsSheet(
      title: title,
      actions: actions,
      onPick: (id) => Navigator.of(ctx).pop(id),
    ),
  );
}
