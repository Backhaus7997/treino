import 'package:flutter/material.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/widgets/treino_icon.dart';

/// Selector tokenizado del kit del Coach Hub.
///
/// Mantiene la semántica y validación de `DropdownButtonFormField`, pero hace
/// que el campo y su overlay pertenezcan al mismo sistema visual que cards e
/// inputs TREINO en ambos temas.
class TreinoDropdown<T> extends StatelessWidget {
  const TreinoDropdown({
    super.key,
    required this.items,
    required this.onChanged,
    this.initialValue,
    this.hint,
    this.decoration,
    this.isExpanded = true,
    this.validator,
  });

  final T? initialValue;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final Widget? hint;
  final InputDecoration? decoration;
  final bool isExpanded;
  final FormFieldValidator<T>? validator;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final baseDecoration = decoration ?? const InputDecoration();
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: BorderSide(color: palette.border),
    );

    return DropdownButtonFormField<T>(
      initialValue: initialValue,
      isExpanded: isExpanded,
      hint: hint,
      validator: validator,
      dropdownColor: TreinoCardTokens.background(context),
      borderRadius: BorderRadius.circular(TreinoCardTokens.borderRadius),
      icon: Icon(
        TreinoIcon.chevronDown,
        size: 16,
        color: palette.textMuted,
      ),
      style: TextStyle(
        fontFamily: AppFonts.barlow,
        fontWeight: AppFonts.w400,
        fontSize: AppTextSize.body,
        color: palette.textPrimary,
      ),
      decoration: baseDecoration.copyWith(
        filled: true,
        fillColor: baseDecoration.fillColor ?? palette.bgCard,
        contentPadding: baseDecoration.contentPadding ??
            const EdgeInsets.symmetric(
              horizontal: AppSpacing.s14,
              vertical: AppSpacing.s14,
            ),
        border: border,
        enabledBorder: border,
        disabledBorder: border,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: palette.accent, width: 1.5),
        ),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}

/// Menú contextual tokenizado para reemplazar `PopupMenuButton` crudo.
class TreinoPopupMenuButton<T> extends StatelessWidget {
  const TreinoPopupMenuButton({
    super.key,
    required this.itemBuilder,
    required this.onSelected,
    this.tooltip,
    this.icon,
    this.child,
    this.initialValue,
    this.padding = const EdgeInsets.all(AppSpacing.s8),
    this.iconSize,
    this.style,
  }) : assert(icon == null || child == null);

  final PopupMenuItemBuilder<T> itemBuilder;
  final PopupMenuItemSelected<T> onSelected;
  final String? tooltip;
  final Widget? icon;
  final Widget? child;
  final T? initialValue;
  final EdgeInsetsGeometry padding;

  /// Tamaño del ícono. En null usa el default de `PopupMenuButton`, que es
  /// **24**: al lado de una fila de íconos de 18 el ⋮ mide de más.
  final double? iconSize;

  /// Estilo del `IconButton` interno.
  ///
  /// Es la ÚNICA forma de controlar su caja. `PopupMenuButton` le reenvía
  /// `padding`, `iconSize` y `style`, pero **no `constraints`** — ese
  /// parámetro suyo es para el MENÚ, no para el botón (ver `popup_menu.dart`,
  /// donde arma el `IconButton`). Quien necesite que el ⋮ mida igual que sus
  /// hermanos de un `Row` pasa un `IconButton.styleFrom(...)` con
  /// `minimumSize`, `padding` y `tapTargetSize`.
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final textStyle = TextStyle(
      fontFamily: AppFonts.barlow,
      fontWeight: AppFonts.w400,
      fontSize: AppTextSize.body,
      color: palette.textPrimary,
    );

    return Theme(
      data: Theme.of(context).copyWith(
        popupMenuTheme: PopupMenuThemeData(
          color: TreinoCardTokens.background(context),
          surfaceTintColor: Colors.transparent,
          textStyle: textStyle,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: TreinoCardTokens.border(context)),
            borderRadius: BorderRadius.circular(TreinoCardTokens.borderRadius),
          ),
        ),
      ),
      child: PopupMenuButton<T>(
        tooltip: tooltip,
        initialValue: initialValue,
        padding: padding,
        iconSize: iconSize,
        style: style,
        color: TreinoCardTokens.background(context),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: TreinoCardTokens.border(context)),
          borderRadius: BorderRadius.circular(TreinoCardTokens.borderRadius),
        ),
        icon: icon,
        onSelected: onSelected,
        itemBuilder: itemBuilder,
        child: child,
      ),
    );
  }
}
