import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';

/// Lo que la celda enfocada le cuenta a la barra de accesorio.
///
/// La barra es tonta a propósito: no sabe si está editando kilos o
/// repeticiones, ni cómo llegar al modelo. La celda que toma el foco publica
/// acá su contexto y sus acciones, y la barra sólo las pinta. Es lo que evita
/// que la pantalla tenga que enterarse de la estructura de la tabla de series
/// para poder ofrecer un atajo.
@immutable
class FocusedSetCell {
  const FocusedSetCell({
    required this.cellId,
    required this.contextLabel,
    required this.stepAmount,
    required this.stepLabel,
    required this.canDecrease,
    required this.onStep,
    this.onFillColumn,
  });

  /// Identidad de la celda. La barra la usa para saber si el foco se movió a
  /// otra celda o si es la misma reconstruida.
  final Object cellId;

  /// `Press de banca con barra · set 3 · kg`. Es lo que dice sobre QUÉ actúan
  /// los botones: con el teclado abierto, la celda enfocada suele quedar a
  /// pocos píxeles del borde y no siempre se ve qué fila es.
  final String contextLabel;

  /// Cuánto suma o resta cada paso. 2,5 en kilos —un par de discos de 1,25—,
  /// 1 en repeticiones.
  final double stepAmount;

  /// El mismo número ya formateado para el botón, para que `+2,5` y el valor
  /// que produce no puedan renderizar su decimal distinto.
  final String stepLabel;

  /// False cuando no queda nada que restar: los botones de menos se apagan en
  /// vez de fingir que el tap hace algo.
  final bool canDecrease;

  final void Function(double delta) onStep;

  /// Replica el valor de esta celda en toda su columna. Null cuando no aplica
  /// —un ejercicio de un solo set no tiene dónde replicar—, y entonces el
  /// botón no se dibuja.
  final VoidCallback? onFillColumn;
}

/// Propaga la celda enfocada desde la fila que la tiene hasta la pantalla que
/// monta la barra.
///
/// Entre una y otra hay cinco niveles de árbol —día, ejercicio, tabla, fila,
/// celda—. Pasar un callback por cada nivel obligaría a que cada widget del
/// camino conozca un atajo que no le incumbe; un `InheritedNotifier` deja que
/// sólo hablen las dos puntas.
class RoutineEditorFocusScope extends InheritedNotifier<FocusedCellNotifier> {
  const RoutineEditorFocusScope({
    required FocusedCellNotifier super.notifier,
    required super.child,
    super.key,
  });

  /// El notifier del scope, o null si no hay uno arriba.
  ///
  /// Devuelve null en vez de tirar a propósito: la tabla de series se monta
  /// también desde el editor web del Coach Hub, donde no hay teclado del
  /// sistema ni barra que mostrar. Una fila sin scope simplemente no publica.
  static FocusedCellNotifier? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<RoutineEditorFocusScope>()
      ?.notifier;
}

/// Qué celda de set tiene el foco, o null si ninguna.
class FocusedCellNotifier extends ValueNotifier<FocusedSetCell?> {
  FocusedCellNotifier() : super(null);

  /// Las filas sueltan el foco en un callback de post-frame —no se puede
  /// notificar durante un build—, y para cuando ese callback corre la pantalla
  /// puede haberse ido del árbol con el notifier ya dispuesto. Salir del
  /// editor con una celda enfocada es justamente ese caso, y sin esta guarda
  /// tira "used after being disposed".
  bool _dispuesto = false;

  @override
  void dispose() {
    _dispuesto = true;
    super.dispose();
  }

  /// Publica [cell] como la celda enfocada.
  void focus(FocusedSetCell cell) {
    if (_dispuesto) return;
    value = cell;
  }

  /// Saca el foco si la celda que lo tenía es [cellId].
  ///
  /// El chequeo de identidad no es defensivo de más: al saltar de una celda a
  /// otra, la que gana el foco publica ANTES de que la que lo pierde avise, y
  /// sin este chequeo el blur de la vieja borraría a la nueva y la barra
  /// parpadearía en cada salto.
  void blur(Object cellId) {
    if (_dispuesto) return;
    if (value?.cellId == cellId) value = null;
  }
}

/// Barra anclada arriba del teclado del sistema, con los atajos de la celda
/// que se está editando.
///
/// Unifica dos atajos que existían y nadie encontraba: los steppers de kilos,
/// que sólo aparecían con foco en KG y sólo en esa fila, y el bulk-fill de
/// columna, que era un tap sobre un header de 10,5 px con un ícono de 11.
class KeyboardAccessoryBar extends StatelessWidget {
  const KeyboardAccessoryBar({required this.cell, super.key});

  final FocusedSetCell cell;

  /// Alto de cada botón. Los steppers de antes ya eran 44 y la regla adoptada
  /// en el slice 1 es que ningún target se achica.
  static const double _kAltoBoton = 44;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return TextFieldTapRegion(
      // Marca la barra como parte de la región de tap del campo. Sin esto el
      // tap cuenta como "afuera", el campo pierde el foco y la barra se va —
      // justo cuando el usuario la estaba tocando.
      child: Material(
        color: palette.bgElevated,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: palette.border)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.s8,
                horizontal: AppSpacing.s12,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _BotonPaso(
                          claveGesto: const Key('accessory_step_minus'),
                          label: '−${cell.stepLabel}',
                          enabled: cell.canDecrease,
                          onTap: () => cell.onStep(-cell.stepAmount),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s8),
                      Expanded(
                        child: _BotonPaso(
                          claveGesto: const Key('accessory_step_plus'),
                          label: '+${cell.stepLabel}',
                          enabled: true,
                          onTap: () => cell.onStep(cell.stepAmount),
                        ),
                      ),
                      if (cell.onFillColumn != null) ...[
                        const SizedBox(width: AppSpacing.s8),
                        Expanded(
                          child: _BotonReplicar(onTap: cell.onFillColumn!),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.hairline),
                  Text(
                    cell.contextLabel,
                    key: const Key('accessory_context'),
                    style: GoogleFonts.barlow(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w400,
                      color: palette.textFaint,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

/// Un stepper. `GestureDetector` y no un botón de Material a propósito: los
/// widgets de botón son enfocables y al tocarlos se llevarían el foco del
/// campo — que es lo único que mantiene esta barra en pantalla.
class _BotonPaso extends StatelessWidget {
  const _BotonPaso({
    required this.claveGesto,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  /// Va en el `GestureDetector`, no en este widget: es su `onTap` el que dice
  /// si el paso está habilitado, y los tests lo leen desde ahí desde que los
  /// steppers existen.
  final Key claveGesto;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        key: claveGesto,
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Container(
          height: KeyboardAccessoryBar._kAltoBoton,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled
                ? palette.accent.withAlpha(_kRellenoPaso)
                : palette.surfaceSubtle,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            label,
            style: GoogleFonts.barlowCondensed(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: enabled ? palette.accentText : palette.textFaint,
            ),
          ),
        ),
      ),
    );
  }
}

/// "A TODAS" — el bulk-fill de columna, ahora con un target de verdad.
class _BotonReplicar extends StatelessWidget {
  const _BotonReplicar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Semantics(
      button: true,
      label: l10n.routineEditorFillColumnA11y,
      child: GestureDetector(
        key: const Key('accessory_fill_column'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: KeyboardAccessoryBar._kAltoBoton,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.surfaceSubtle,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // El handoff pedía `arrowLineDown`, que el kit no tiene. Va
              // `copy`, que es el ícono con el que esta misma acción ya vivía
              // en el header — sumar uno al kit para un solo caso es peor que
              // reusar el que el usuario ya asoció con replicar.
              Icon(TreinoIcon.copy, size: 14, color: palette.textPrimary),
              const SizedBox(width: AppSpacing.hairline),
              Flexible(
                child: Text(
                  l10n.routineEditorFillColumnLabel,
                  style: GoogleFonts.barlowCondensed(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Relleno de los steppers, sobre 255. Mismo token que el botón primario de
/// las acciones del día, para que "sumar" se lea igual en toda la pantalla.
const int _kRellenoPaso = 30;

/// La barra en su lugar: `Scaffold.bottomSheet`.
///
/// Es la ranura que Flutter ya ancla arriba del teclado cuando el Scaffold
/// tiene `resizeToAvoidBottomInset` (el default). Calcular
/// `viewInsets.bottom` a mano dentro del body no funciona: el Scaffold ya lo
/// consumió para achicar el contenido, así que el valor que se lee ahí es
/// cero y la barra quedaría abajo del teclado.
///
/// Devuelve null cuando no hay celda enfocada — un `bottomSheet` nulo no
/// ocupa lugar, que es lo que hace que la barra exista SOLO mientras se está
/// editando.
class KeyboardAccessorySlot extends StatelessWidget {
  const KeyboardAccessorySlot({required this.cell, super.key});

  final FocusedSetCell? cell;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: AppMotion.resolve(context, AppMotion.fast),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: cell == null
          ? const SizedBox(width: double.infinity)
          : KeyboardAccessoryBar(cell: cell!),
    );
  }
}
