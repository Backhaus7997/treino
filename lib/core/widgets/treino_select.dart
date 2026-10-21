import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_motion.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/tokens/tokens.dart';
import 'treino_icon.dart';

/// Una opción de [showTreinoSelect] / [TreinoSelectField].
///
/// [value] puede ser `null` —un «Ninguno» o «Sin especificar»—: por eso el
/// selector devuelve la OPCIÓN elegida y no el valor, y `null` queda libre
/// para decir «se cerró sin elegir».
@immutable
class TreinoSelectOption<T> {
  const TreinoSelectOption({
    required this.value,
    required this.label,
    this.trailingIcon,
    this.muted = false,
    this.key,
  });

  final T value;
  final String label;

  /// Ícono a la derecha del label, antes del check (p. ej. un candado).
  final IconData? trailingIcon;

  /// Pinta el label en `textMuted`: opciones «vacías» (Ninguno) o
  /// bloqueadas. NO la deshabilita — un período con candado tiene que seguir
  /// respondiendo al tap para poder explicar por qué está bloqueado.
  final bool muted;

  /// Key de la fila, para que los tests la encuentren sin depender del texto.
  final Key? key;
}

/// Ancho a partir del cual el selector deja de ser una hoja y pasa a ser un
/// menú anclado al campo. Por debajo es un teléfono: la hoja deja el pulgar
/// cerca de las opciones y aguanta listas largas. Por encima —el Coach Hub
/// web— una hoja que sube desde el borde de un monitor queda a medio metro
/// del campo que la abrió.
const double kTreinoSelectWideBreakpoint = 600;

/// Abre el selector de Treino y devuelve la opción elegida, o `null` si se
/// cerró sin elegir.
///
/// Es EL selector de la app: reemplaza al menú de `DropdownButton`
/// —una hoja blanca, rectangular, sin la tipografía ni los tokens del kit—.
/// [context] tiene que ser el del disparador: en pantallas anchas el menú se
/// ancla a su caja.
///
/// - Angosto: hoja con el chrome de `ExerciseActionsSheet` (`bgElevated`,
///   radio `lg` arriba, handle, título en Barlow Condensed), scrolleable y
///   abierta ya mostrando la opción elegida.
/// - Ancho: menú anclado debajo del campo (o arriba si no entra), con su
///   mismo ancho y las mismas filas.
///
/// En los dos la opción elegida se marca con fondo de acento suave, label en
/// 700 y un check en `accentText` — nunca sólo por color.
Future<TreinoSelectOption<T>?> showTreinoSelect<T>(
  BuildContext context, {
  required String title,
  required List<TreinoSelectOption<T>> options,
  T? selected,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  // -1 si [selected] no es ninguna opción: no se marca nada.
  final selectedIndex = options.indexWhere((o) => o.value == selected);
  final wide = MediaQuery.sizeOf(context).width >= kTreinoSelectWideBreakpoint;
  final box = context.findRenderObject() as RenderBox?;

  if (wide && box != null && box.hasSize) {
    final navigator = Navigator.of(context);
    final overlayBox =
        navigator.overlay!.context.findRenderObject()! as RenderBox;
    final anchor = MatrixUtils.transformRect(
      box.getTransformTo(overlayBox),
      Offset.zero & box.size,
    );
    return navigator.push(
      _TreinoSelectMenuRoute<T>(
        anchor: anchor,
        options: options,
        selectedIndex: selectedIndex,
        title: title,
        reduceMotion: AppMotion.reduceMotion(context),
        barrierLabel:
            MaterialLocalizations.of(context).modalBarrierDismissLabel,
      ),
    );
  }

  final palette = AppPalette.of(context);
  return showModalBottomSheet<TreinoSelectOption<T>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: palette.bgElevated,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    sheetAnimationStyle: AnimationStyle(
      duration: AppMotion.resolve(context, AppMotion.base),
      reverseDuration: AppMotion.resolve(context, AppMotion.fast),
      curve: AppMotion.standard,
    ),
    builder: (ctx) => _TreinoSelectSheet<T>(
      title: title,
      options: options,
      selectedIndex: selectedIndex,
    ),
  );
}

/// Campo de selección de Treino: se ve como cualquier input del kit y abre
/// [showTreinoSelect].
///
/// Reemplaza a `DropdownButton` / `DropdownButtonFormField`, que el guard
/// `no_raw_dropdown_scan_test.dart` prohíbe fuera de este archivo.
class TreinoSelectField<T> extends StatefulWidget {
  const TreinoSelectField({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.sheetTitle,
    this.hint,
    this.decoration,
    this.textStyle,
  });

  /// Valor actual. Si no coincide con ninguna opción se muestra [hint].
  final T? value;
  final List<TreinoSelectOption<T>> options;

  /// `null` deshabilita el campo.
  final ValueChanged<T>? onChanged;

  /// Título de la hoja. Con la hoja abierta el label del campo queda tapado,
  /// así que sin esto no se sabe qué se está eligiendo.
  final String sheetTitle;

  final String? hint;

  /// Se mezcla SOBRE la decoración del kit: sólo pisa lo que trae.
  final InputDecoration? decoration;

  final TextStyle? textStyle;

  @override
  State<TreinoSelectField<T>> createState() => _TreinoSelectFieldState<T>();
}

class _TreinoSelectFieldState<T> extends State<TreinoSelectField<T>> {
  bool _open = false;

  /// Foco de teclado (Tab en el Coach Hub). El `bgCard` del campo tapa el
  /// highlight del InkWell, así que sin esto un campo enfocado se ve igual
  /// que uno que no lo está: el foco se dibuja con el mismo borde de «abierto».
  bool _focused = false;

  TreinoSelectOption<T>? get _current {
    for (final o in widget.options) {
      if (o.value == widget.value) return o;
    }
    return null;
  }

  Future<void> _abrir(BuildContext anchorContext) async {
    setState(() => _open = true);
    final picked = await showTreinoSelect<T>(
      anchorContext,
      title: widget.sheetTitle,
      options: widget.options,
      selected: widget.value,
    );
    if (!mounted) return;
    setState(() => _open = false);
    if (picked != null) widget.onChanged?.call(picked.value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final enabled = widget.onChanged != null;
    final current = _current;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: BorderSide(color: palette.border),
    );
    final base = widget.decoration ?? const InputDecoration();
    final decoration = base.copyWith(
      enabled: enabled,
      hintText: base.hintText ?? widget.hint,
      hintStyle: base.hintStyle ??
          GoogleFonts.barlow(
            fontWeight: AppFonts.w400,
            fontSize: AppTextSize.body,
            color: palette.textMuted,
          ),
      filled: true,
      fillColor: base.fillColor ?? palette.bgCard,
      contentPadding: base.contentPadding ??
          const EdgeInsets.symmetric(
            horizontal: AppSpacing.s14,
            vertical: AppSpacing.s14,
          ),
      suffixIcon: Icon(
        TreinoIcon.chevronDown,
        size: 16,
        color: enabled ? palette.textMuted : palette.textFaint,
      ),
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        // `accentText` y no `accent`: es el único indicador de «abierto» del
        // campo, y en claro el mint pleno da 1,57:1 contra el fondo.
        borderSide: BorderSide(color: palette.accentText, width: 1.5),
      ),
    );

    return Builder(
      builder: (anchorContext) => Semantics(
        button: true,
        enabled: enabled,
        label: base.labelText ?? widget.sheetTitle,
        value: current?.label ?? widget.hint,
        excludeSemantics: true,
        // `excludeSemantics` se lleva la acción del InkWell: sin este onTap
        // el lector de pantalla anuncia un botón que no hace nada.
        onTap: enabled ? () => _abrir(anchorContext) : null,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: enabled ? () => _abrir(anchorContext) : null,
            onFocusChange: (f) => setState(() => _focused = f),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: InputDecorator(
              decoration: decoration,
              isEmpty: current == null,
              isFocused: _open || _focused,
              child: current == null
                  ? null
                  : Text(
                      current.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: widget.textStyle ??
                          GoogleFonts.barlow(
                            fontWeight: AppFonts.w400,
                            fontSize: AppTextSize.body,
                            color: current.muted
                                ? palette.textMuted
                                : palette.textPrimary,
                          ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Fila ─────────────────────────────────────────────────────────────────────

/// Alto de cada fila: el target interactivo de 48 de toda la app.
const double _kAltoFila = 48;

class _Fila<T> extends StatelessWidget {
  const _Fila({required this.option, required this.selected});

  final TreinoSelectOption<T> option;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final color = option.muted ? palette.textMuted : palette.textPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
      child: Semantics(
        button: true,
        selected: selected,
        label: option.label,
        excludeSemantics: true,
        onTap: () => Navigator.of(context).pop(option),
        child: Material(
          color: selected
              ? palette.accent.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: InkWell(
            key: option.key,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: () => Navigator.of(context).pop(option),
            child: SizedBox(
              height: _kAltoFila,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.barlow(
                          fontSize: AppTextSize.bodyLarge,
                          fontWeight:
                              selected ? FontWeight.w700 : AppFonts.w400,
                          color: color,
                        ),
                      ),
                    ),
                    if (option.trailingIcon != null) ...[
                      const SizedBox(width: AppSpacing.s8),
                      Icon(option.trailingIcon, size: 16, color: color),
                    ],
                    const SizedBox(width: AppSpacing.s8),
                    // El check ocupa su lugar aunque no se vea: así el label
                    // no se corre al cambiar de opción.
                    Opacity(
                      opacity: selected ? 1 : 0,
                      child: Icon(
                        TreinoIcon.checkBare,
                        size: 18,
                        color: palette.accentText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lista de filas. Abre ya scrolleada para que la elegida quede a la vista
/// con dos filas de contexto arriba.
class _Lista<T> extends StatefulWidget {
  const _Lista({required this.options, required this.selectedIndex});

  final List<TreinoSelectOption<T>> options;
  final int selectedIndex;

  @override
  State<_Lista<T>> createState() => _ListaState<T>();
}

class _ListaState<T> extends State<_Lista<T>> {
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: math.max(0, (widget.selectedIndex - 2) * _kAltoFila),
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _scroll,
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.hairline),
      itemExtent: _kAltoFila,
      itemCount: widget.options.length,
      itemBuilder: (context, i) => _Fila<T>(
        option: widget.options[i],
        selected: i == widget.selectedIndex,
      ),
    );
  }
}

// ── Hoja (angosto) ───────────────────────────────────────────────────────────

class _TreinoSelectSheet<T> extends StatelessWidget {
  const _TreinoSelectSheet({
    required this.title,
    required this.options,
    required this.selectedIndex,
  });

  final String title;
  final List<TreinoSelectOption<T>> options;
  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final maxAlto = MediaQuery.sizeOf(context).height * 0.7;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxAlto),
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
                AppSpacing.s20,
                AppSpacing.s14,
                AppSpacing.s20,
                AppSpacing.s8,
              ),
              child: Text(
                title.toUpperCase(),
                key: const Key('treino_select_title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.barlowCondensed(
                  fontSize: AppTextSize.title,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: palette.textPrimary,
                ),
              ),
            ),
            Flexible(
              child: _Lista<T>(options: options, selectedIndex: selectedIndex),
            ),
            const SizedBox(height: AppSpacing.s12),
          ],
        ),
      ),
    );
  }
}

// ── Menú anclado (ancho) ─────────────────────────────────────────────────────

class _TreinoSelectMenuRoute<T> extends PopupRoute<TreinoSelectOption<T>> {
  _TreinoSelectMenuRoute({
    required this.anchor,
    required this.options,
    required this.selectedIndex,
    required this.title,
    required this.reduceMotion,
    required this.barrierLabel,
  });

  final Rect anchor;
  final List<TreinoSelectOption<T>> options;
  final int selectedIndex;
  final String title;
  final bool reduceMotion;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : AppMotion.fast;

  @override
  Duration get reverseTransitionDuration =>
      reduceMotion ? Duration.zero : AppMotion.micro;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final palette = AppPalette.of(context);
    return CustomSingleChildLayout(
      delegate: _MenuLayout(anchor: anchor),
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        label: title,
        child: Material(
          color: palette.bgCard,
          elevation: 6,
          shadowColor: Colors.black.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: BorderSide(color: palette.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: _Lista<T>(options: options, selectedIndex: selectedIndex),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.standard,
      reverseCurve: AppMotion.exit,
    );
    return FadeTransition(
      opacity: curved,
      child: AnimatedBuilder(
        animation: curved,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, -AppMotion.slideSm * (1 - curved.value)),
          child: child,
        ),
        child: child,
      ),
    );
  }
}

class _MenuLayout extends SingleChildLayoutDelegate {
  _MenuLayout({required this.anchor});

  final Rect anchor;

  static const double _maxAlto = 360;
  static const double _anchoMin = 220;
  static const double _margen = AppSpacing.s8;

  double _alto(Size size) => math.min(
        _maxAlto,
        math.max(size.height - anchor.bottom, anchor.top) - _margen * 2,
      );

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final ancho = math.min(
      math.max(anchor.width, _anchoMin),
      constraints.maxWidth - _margen * 2,
    );
    return BoxConstraints(
      minWidth: ancho,
      maxWidth: ancho,
      maxHeight: math.max(_kAltoFila, _alto(constraints.biggest)),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final x = anchor.left
        .clamp(
            _margen, math.max(_margen, size.width - childSize.width - _margen))
        .toDouble();
    final abajo = anchor.bottom + AppSpacing.hairline;
    final entraAbajo = abajo + childSize.height <= size.height - _margen;
    final y = entraAbajo
        ? abajo
        : math.max(
            _margen, anchor.top - AppSpacing.hairline - childSize.height);
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_MenuLayout oldDelegate) => anchor != oldDelegate.anchor;
}
