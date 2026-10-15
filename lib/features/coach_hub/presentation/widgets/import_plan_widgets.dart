import 'package:flutter/material.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../app/theme/tokens/tokens.dart';
import '../../domain/periodized_plan.dart';

/// Piezas compartidas de las dos pantallas del import de Excel (subir y vista
/// previa). Todo sale de tokens: nada de colores, tamaños ni espacios crudos.

/// Estilo de texto del import: familia Barlow del tema, tamaño de la escala.
TextStyle importText(
  Color color, {
  double size = AppTextSize.body,
  FontWeight weight = AppFonts.w400,
  double? height,
}) =>
    TextStyle(
      fontFamily: AppFonts.barlow,
      color: color,
      fontSize: size,
      fontWeight: weight,
      height: height,
    );

/// Tarjeta con el fondo y el borde del kit.
class ImportCard extends StatelessWidget {
  const ImportCard({
    super.key,
    required this.child,
    this.padding = AppSpacing.s18,
    this.borderColor,
    this.background,
  });

  final Widget child;
  final double padding;
  final Color? borderColor;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: background ?? TreinoCardTokens.background(context),
        borderRadius: BorderRadius.circular(TreinoCardTokens.borderRadius),
        border:
            Border.all(color: borderColor ?? TreinoCardTokens.border(context)),
      ),
      child: child,
    );
  }
}

/// Chip chico de información (CALENTAMIENTO, AL FALLO, 8 min, 20 m…).
class ImportChip extends StatelessWidget {
  const ImportChip({super.key, required this.label, this.color});

  final String label;

  /// Color de borde y texto; por defecto el muted de la paleta.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppPalette.of(context).textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.hairline,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: c),
      ),
      child: Text(
        label,
        style: importText(c, size: AppTextSize.caption, weight: AppFonts.w600),
      ),
    );
  }
}

/// Título del grupo de cada código de diagnóstico.
String importDiagnosticGroupTitle(ImportDiagnosticCode code) => switch (code) {
      ImportDiagnosticCode.unreadableFile => 'No pudimos leer el archivo',
      ImportDiagnosticCode.notTemplate => 'No es la plantilla nueva',
      ImportDiagnosticCode.oldFormat => 'Formato viejo',
      ImportDiagnosticCode.noDayHeader => 'Falta el encabezado de día',
      ImportDiagnosticCode.weekColumnsNotContiguous =>
        'Semanas que no son contiguas',
      ImportDiagnosticCode.weekColumnsDuplicated => 'Semanas duplicadas',
      ImportDiagnosticCode.tooManyWeeks => 'Demasiadas semanas',
      ImportDiagnosticCode.tooManyDays => 'Demasiados días',
      ImportDiagnosticCode.duplicatedDay => 'Días repetidos',
      ImportDiagnosticCode.invalidDayNumber => 'Número de día inválido',
      ImportDiagnosticCode.exerciseOutsideBlock =>
        'Ejercicios fuera de un bloque DÍA',
      ImportDiagnosticCode.emptyExerciseComponent =>
        'Superseries con un "+" vacío',
      ImportDiagnosticCode.unreadableCell => 'Celdas que no se entienden',
      ImportDiagnosticCode.atomCountMismatch =>
        'Valores que no coinciden con los ejercicios del renglón',
      ImportDiagnosticCode.invalidRest => 'Descansos inválidos',
      ImportDiagnosticCode.invalidNumber => 'N° inválidos',
      ImportDiagnosticCode.noExercises => 'El plan no tiene ejercicios',
      ImportDiagnosticCode.numberingGap => 'Numeración salteada o repetida',
      ImportDiagnosticCode.missingReps => 'Falta cargar reps',
      ImportDiagnosticCode.qualifierSavedAsNote =>
        'Calificadores guardados como nota',
      ImportDiagnosticCode.mixedSetKinds => 'Modos mezclados entre semanas',
    };

/// Todos los diagnósticos, agrupados por código, cada uno con su celda
/// (`Programa!F12`) y el valor recibido.
class ImportDiagnosticsList extends StatelessWidget {
  const ImportDiagnosticsList({super.key, required this.diagnostics});

  final List<ImportDiagnostic> diagnostics;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final groups = <ImportDiagnosticCode, List<ImportDiagnostic>>{};
    for (final d in diagnostics) {
      groups.putIfAbsent(d.code, () => []).add(d);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in groups.entries) ...[
          Text(
            '${importDiagnosticGroupTitle(entry.key)} (${entry.value.length})',
            style: importText(
              entry.value.first.isError ? palette.danger : palette.warning,
              size: AppTextSize.bodyDense,
              weight: AppFonts.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.hairline),
          for (final d in entry.value)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.hairline),
              child: Text(
                _line(d),
                style: importText(
                  palette.textPrimary,
                  size: AppTextSize.bodyDense,
                  height: 1.4,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.s8),
        ],
      ],
    );
  }

  static String _line(ImportDiagnostic d) {
    final cell = d.cellRef;
    final raw = d.rawValue;
    final value = (raw == null || raw.isEmpty) ? '' : '`$raw`: ';
    return cell == null ? d.message : '$cell — $value${d.message}';
  }
}
