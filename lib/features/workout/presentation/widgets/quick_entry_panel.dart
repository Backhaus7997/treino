import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import 'quick_entry_parser.dart';

/// Un ejercicio del catálogo, listo para mostrar en la lista de resultados.
///
/// El panel no conoce el modelo de dominio: recibe lo que tiene que pintar y
/// devuelve cuál se eligió. Así se prueba sin providers ni repositorios.
@immutable
class QuickEntryResult {
  const QuickEntryResult({
    required this.id,
    required this.name,
    required this.muscleGroup,
  });

  final String id;
  final String name;
  final String muscleGroup;
}

/// Panel de entrada rápida: escribir `banca 4x10 60` en vez de cuatro pasos.
///
/// Agregar un ejercicio son hoy varios taps —abrir el picker, buscar, elegir, y
/// después cargar sets, reps y peso a mano—. Para quien ya sabe lo que quiere,
/// eso es fricción pura.
///
/// **Nunca es el único camino**: el picker completo sigue donde estaba. Por eso
/// este atajo puede permitirse ser tolerante y adivinar.
class QuickEntryPanel extends StatelessWidget {
  const QuickEntryPanel({
    required this.controller,
    required this.entry,
    required this.results,
    required this.onPick,
    super.key,
  });

  final TextEditingController controller;

  /// Lo que se entendió del texto actual. Alimenta el hint del pie y la
  /// prescripción que se muestra a la derecha de cada resultado.
  final QuickEntry entry;

  /// Hasta tres. Más que eso deja de ser un atajo y empieza a ser un picker.
  final List<QuickEntryResult> results;

  final void Function(QuickEntryResult) onPick;

  /// Cuántos resultados se muestran como máximo.
  static const int kMaxResultados = 3;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final visibles = results.take(kMaxResultados).toList();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s12),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        // `accentText` y no `accent`: el mint pleno como LÍNEA sobre papel mide
        // 1,64:1 y el borde de este panel es lo que lo separa de la cabecera
        // del día. Con accentText da 11,29:1 en dark y 5,34:1 en light.
        border: Border.all(color: palette.accentText, width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(TreinoIcon.search, size: 17, color: palette.accentText),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: TextField(
                  key: const Key('quick_entry_field'),
                  controller: controller,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  style: GoogleFonts.barlow(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: l10n.routineEditorQuickEntryHint,
                    hintStyle: GoogleFonts.barlow(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: palette.textMuted,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (visibles.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s8),
            for (var i = 0; i < visibles.length; i++) ...[
              _FilaResultado(
                indice: i,
                result: visibles[i],
                prescripcion: _prescripcion(entry, l10n),
                onTap: () => onPick(visibles[i]),
              ),
              if (i < visibles.length - 1)
                const SizedBox(height: AppSpacing.hairline),
            ],
          ],
          const SizedBox(height: AppSpacing.s8),
          Text(
            entry.tienePrescripcion
                ? l10n.routineEditorQuickEntryWillAdd(
                    entry.sets,
                    entry.reps ?? 0,
                    _pesoTexto(entry, l10n),
                  )
                : l10n.routineEditorQuickEntryEmptyHint,
            key: const Key('quick_entry_hint'),
            style: GoogleFonts.barlow(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: palette.textFaint,
            ),
          ),
        ],
      ),
    );
  }

  /// `4×10 · 60kg`, o `4×10` cuando no hay peso, o vacío si no se prescribió
  /// nada — un nombre solo no tiene qué mostrar a la derecha.
  static String _prescripcion(QuickEntry e, AppL10n l10n) {
    if (!e.tienePrescripcion) return '';
    final base = '${e.sets}×${e.reps ?? ''}';
    if (e.weightKg == null) return base;
    return '$base · ${_kg(e.weightKg!)}${l10n.monthlyReportVolumeUnit}';
  }

  static String _pesoTexto(QuickEntry e, AppL10n l10n) => e.weightKg == null
      ? l10n.routineEditorQuickEntryNoWeight
      : '${_kg(e.weightKg!)} ${l10n.monthlyReportVolumeUnit}';

  /// Sin decimal cuando es entero: `60`, no `60.0`.
  static String _kg(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';
}

/// Una fila de resultado. Toda la fila es el target — el nombre solo sería un
/// blanco de 14 px de alto.
class _FilaResultado extends StatelessWidget {
  const _FilaResultado({
    required this.indice,
    required this.result,
    required this.prescripcion,
    required this.onTap,
  });

  final int indice;
  final QuickEntryResult result;
  final String prescripcion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Material(
      color: palette.surfaceSubtle,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        key: Key('quick_entry_result_$indice'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: ConstrainedBox(
          // El piso va acá y no en un `ConstrainedBox` suelto alrededor del
          // contenido: con `minHeight` el hijo crece si el texto lo pide, que
          // es lo que hace falta con Dynamic Type grande.
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s8,
              vertical: AppSpacing.hairline,
            ),
            child: Row(
              children: [
                Icon(TreinoIcon.dumbbell, size: 17, color: palette.accentText),
                const SizedBox(width: AppSpacing.s8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.name,
                        style: GoogleFonts.barlow(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: palette.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        result.muscleGroup,
                        style: GoogleFonts.barlow(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: palette.textMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (prescripcion.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.s8),
                  Text(
                    prescripcion,
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: palette.accentText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// El botón que abre y cierra el panel, en la cabecera del día.
class QuickEntryToggle extends StatelessWidget {
  const QuickEntryToggle({
    required this.active,
    required this.onTap,
    super.key,
  });

  final bool active;
  final VoidCallback onTap;

  /// Alto del pill. El handoff pedía 36; va 48 por el criterio de la épica —
  /// ningún target interactivo queda por debajo.
  static const double _kAlto = 48;

  /// Relleno cuando está activo, sobre 255.
  static const int _kRellenoActivo = 40;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Semantics(
      button: true,
      toggled: active,
      label: l10n.routineEditorQuickEntryToggleA11y,
      excludeSemantics: true,
      child: Material(
        color: active
            ? palette.accent.withAlpha(_kRellenoActivo)
            : palette.surfaceSubtle,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: InkWell(
          key: const Key('quick_entry_toggle'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: SizedBox(
            height: _kAlto,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    TreinoIcon.specialty,
                    size: 14,
                    // Apagado va `textMuted`, que sobre `surfaceSubtle` mide
                    // 5,77:1 en dark y 6,15:1 en light. Lo que distingue los
                    // dos estados es sobre todo el RELLENO: delta 33 por canal
                    // encendido contra 14 apagado.
                    color: active ? palette.accentText : palette.textMuted,
                  ),
                  const SizedBox(width: AppSpacing.hairline),
                  Text(
                    l10n.routineEditorQuickEntryToggle,
                    style: GoogleFonts.barlowCondensed(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: active ? palette.accentText : palette.textMuted,
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
