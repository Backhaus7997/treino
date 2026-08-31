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
    required this.focusNode,
    required this.entry,
    required this.results,
    required this.onSelect,
    required this.onConfirm,
    this.selected,
    super.key,
  });

  final TextEditingController controller;

  /// El foco del campo. Lo maneja el llamador porque elegir un resultado tiene
  /// que DEVOLVERLO con el cursor al final: el tap sobre la lista lo suelta, y
  /// sin recuperarlo el teclado se cierra justo cuando el usuario va a
  /// escribir la prescripción.
  final FocusNode focusNode;

  /// Lo que se entendió del texto actual. Alimenta el hint del pie y la
  /// prescripción que se muestra a la derecha de cada resultado.
  final QuickEntry entry;

  /// Los candidatos del catálogo. Se muestran SOLO mientras no hay uno
  /// elegido: una vez elegido, la lista estorba.
  final List<QuickEntryResult> results;

  /// El ejercicio ya elegido, o null si todavía se está buscando.
  final QuickEntryResult? selected;

  /// Elegir un candidato. **NO agrega nada**: autocompleta el nombre en el
  /// campo para que se siga escribiendo la prescripción.
  ///
  /// Hasta la revisión en device del 31/08 el tap agregaba el ejercicio en el
  /// acto, con lo que hubiera escrito hasta ese momento. Como el nombre se
  /// escribe primero, eso significaba que el atajo se cerraba justo antes de
  /// poder decir `4x10 55` — el usuario perdía el paso que venía a dar.
  final void Function(QuickEntryResult) onSelect;

  /// Agrega el ejercicio elegido con la prescripción tipeada.
  final VoidCallback onConfirm;

  /// Cuántos candidatos se muestran. Los que no entran se alcanzan con scroll:
  /// buscar "sentadilla" en un catálogo real devuelve más de tres variantes, y
  /// cortar en tres escondía justo la que se busca.
  static const int kMaxResultados = 8;

  /// Alto máximo de la lista. Tres filas y media: se ve que hay más abajo.
  static const double _kAltoLista = 170;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final visibles = results.take(kMaxResultados).toList();
    final yaElegido = selected != null;

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
              Icon(
                yaElegido ? TreinoIcon.dumbbell : TreinoIcon.search,
                size: 17,
                color: palette.accentText,
              ),
              const SizedBox(width: AppSpacing.s8),
              Expanded(
                child: TextField(
                  key: const Key('quick_entry_field'),
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    if (yaElegido) onConfirm();
                  },
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
              if (yaElegido) ...[
                const SizedBox(width: AppSpacing.s8),
                _BotonAgregar(onTap: onConfirm),
              ],
            ],
          ),
          // La lista desaparece una vez elegido: a partir de ahí lo que se
          // escribe es la prescripción, no una búsqueda.
          if (!yaElegido && visibles.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: _kAltoLista),
              // TapRegion para que tocar un resultado NO cuente como "afuera"
              // del campo: sin esto el tap cierra el teclado que el usuario
              // necesita abierto para seguir escribiendo la prescripción.
              child: TextFieldTapRegion(
                child: ListView.separated(
                  key: const Key('quick_entry_results'),
                  shrinkWrap: true,
                  // Scrollear la lista SÍ baja el teclado, que es lo que deja
                  // ver más opciones sin que estorbe.
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.zero,
                  itemCount: visibles.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.hairline),
                  itemBuilder: (context, i) => _FilaResultado(
                    indice: i,
                    result: visibles[i],
                    prescripcion: _prescripcion(entry, l10n),
                    onTap: () => onSelect(visibles[i]),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s8),
          Text(
            _hint(entry, yaElegido, l10n),
            key: const Key('quick_entry_hint'),
            style: GoogleFonts.barlow(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: palette.textFaint,
            ),
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  /// Qué decirle al usuario según dónde está parado.
  static String _hint(QuickEntry e, bool yaElegido, AppL10n l10n) {
    if (!yaElegido) return l10n.routineEditorQuickEntryEmptyHint;
    if (!e.tienePrescripcion) return l10n.routineEditorQuickEntryPickedHint;
    return l10n.routineEditorQuickEntryWillAdd(
      e.sets,
      _listaTexto(e.sets, e.repsDeSet, (v) => '$v'),
      _pesoTexto(e, l10n),
    );
  }

  /// `10` cuando todos los sets comparten valor, `10 · 8 · 6 · 4` cuando no.
  /// Repetir cuatro veces el mismo número no informa; la pirámide sí.
  static String _listaTexto<T>(
    int sets,
    T? Function(int) valorDe,
    String Function(T) formatear,
  ) {
    final valores = [for (var i = 0; i < sets; i++) valorDe(i)];
    if (valores.isEmpty || valores.first == null) return '—';
    final todosIguales = valores.every((v) => v == valores.first);
    if (todosIguales) return formatear(valores.first as T);
    return valores.map((v) => v == null ? '—' : formatear(v)).join(' · ');
  }

  /// `4×10 · 60kg`, o `4×10` cuando no hay peso, o vacío si no se prescribió
  /// nada — un nombre solo no tiene qué mostrar a la derecha.
  static String _prescripcion(QuickEntry e, AppL10n l10n) {
    if (!e.tienePrescripcion) return '';
    final reps = _listaTexto(e.sets, e.repsDeSet, (v) => '$v');
    final base = '${e.sets}×$reps';
    if (e.weights.isEmpty) return base;
    final pesos = _listaTexto(e.sets, e.pesoDeSet, _kg);
    return '$base · $pesos${l10n.monthlyReportVolumeUnit}';
  }

  static String _pesoTexto(QuickEntry e, AppL10n l10n) => e.weights.isEmpty
      ? l10n.routineEditorQuickEntryNoWeight
      : '${_listaTexto(e.sets, e.pesoDeSet, _kg)} '
          '${l10n.monthlyReportVolumeUnit}';

  /// Sin decimal cuando es entero: `60`, no `60.0`.
  static String _kg(double v) => v == v.roundToDouble() ? '${v.round()}' : '$v';
}

/// El botón que confirma. Existe porque elegir el ejercicio dejó de agregarlo:
/// hace falta un lugar donde decir "ya está, sumalo".
class _BotonAgregar extends StatelessWidget {
  const _BotonAgregar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Semantics(
      button: true,
      label: l10n.routineEditorQuickEntryAdd,
      excludeSemantics: true,
      child: Material(
        color: palette.accent,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: InkWell(
          key: const Key('quick_entry_confirm'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.full),
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s14),
              child: Center(
                child: Text(
                  l10n.routineEditorQuickEntryAdd,
                  style: GoogleFonts.barlowCondensed(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: TreinoButtonTokens.foreground(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
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

    // `GestureDetector` y no un `InkWell`: los widgets de botón de Material son
    // ENFOCABLES, y al tocar un resultado se llevaban el foco del campo. El
    // teclado se cerraba, y al volver a tocar el cursor quedaba donde cayó el
    // dedo en vez de al final del texto. Mismo motivo por el que los steppers
    // de la barra de accesorio tampoco son botones.
    return Semantics(
      button: true,
      label: result.name,
      excludeSemantics: true,
      child: GestureDetector(
        key: Key('quick_entry_result_$indice'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s8,
            vertical: AppSpacing.hairline,
          ),
          decoration: BoxDecoration(
            color: palette.surfaceSubtle,
            borderRadius: BorderRadius.circular(AppRadius.sm),
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
