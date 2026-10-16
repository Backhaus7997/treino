import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import 'app_palette.dart';

class AppTheme {
  // ---------------------------------------------------------------------------
  // Private helpers shared by both factories (ADR-LM-010)
  // ---------------------------------------------------------------------------

  static TextTheme _buildTextTheme(AppPalette palette, TextTheme base) {
    final condensed = GoogleFonts.barlowCondensedTextTheme(base);
    return base.copyWith(
      displayLarge: condensed.displayLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: palette.textPrimary,
      ),
      displayMedium: condensed.displayMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: palette.textPrimary,
      ),
      headlineLarge: condensed.headlineLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: palette.textPrimary,
      ),
      headlineMedium: condensed.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: palette.textPrimary,
      ),
      headlineSmall: condensed.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: palette.textPrimary,
      ),
      titleLarge: condensed.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
        color: palette.textPrimary,
      ),
    );
  }

  static InputDecorationTheme _buildInputDecoration(
    AppPalette palette,
    Color errorColor,
  ) {
    return InputDecorationTheme(
      filled: true,
      fillColor: palette.bgCard,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 18,
      ),
      labelStyle: GoogleFonts.barlow(
        color: palette.textMuted,
        fontWeight: FontWeight.w400,
      ),
      hintStyle: GoogleFonts.barlow(color: palette.textMuted),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: palette.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: errorColor),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        borderSide: BorderSide(color: errorColor, width: 1.5),
      ),
      errorStyle: GoogleFonts.barlow(
        color: errorColor,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  // ---------------------------------------------------------------------------

  /// Estilo de la barra de estado (el color de los íconos de hora, wifi y
  /// batería) para un tema de [brightness]: íconos CLAROS sobre el tema oscuro,
  /// OSCUROS sobre el claro.
  ///
  /// Lo comparten dos consumidores y tienen que coincidir siempre:
  /// [ThemeWatcher], que lo aplica a toda la app, y el `AppBarTheme` de las dos
  /// fábricas de abajo. Si cada uno tuviera su propia copia del `if`, el día que
  /// cambie uno el otro se queda atrás y la barra de estado vuelve a bailar
  /// según haya o no un `AppBar` en pantalla.
  ///
  /// ## Por qué el `AppBarTheme` lo necesita (#1463)
  ///
  /// Un `AppBar` sin `systemOverlayStyle` NO hereda el de [ThemeWatcher]:
  /// envuelve su contenido en su propio `AnnotatedRegion`, que está más abajo en
  /// el árbol y por eso gana, y lo calcula estimando el brillo de su
  /// `backgroundColor`. Con `Colors.transparent` (`0x00000000`) la luminancia da
  /// negro, o sea «fondo oscuro» → íconos blancos, aunque detrás haya un fondo
  /// claro. En el tema claro eso dejaba hora, wifi y batería casi invisibles en
  /// el chat, las notificaciones y los perfiles.
  ///
  /// Poniéndolo en el tema, todo `AppBar` del árbol resuelve el estilo correcto
  /// sin que cada pantalla lo repita. Una pantalla con una superficie de color
  /// fijo (el visor de fotos) lo sigue pudiendo pisar con su propio
  /// `AppBar.systemOverlayStyle` o con un `Theme` propio.
  static SystemUiOverlayStyle systemOverlayStyleFor(Brightness brightness) =>
      brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark;

  // ---------------------------------------------------------------------------
  // Estados de interacción — los defaults de Material, tapados
  // ---------------------------------------------------------------------------

  /// Colores de hover / foco / pressed / splash derivados de la paleta.
  ///
  /// Sin esto rige el default de Material 3, que pinta el overlay con
  /// `colorScheme.onSurface` al 8%. Acá `onSurface` es `palette.textPrimary`,
  /// que **en el tema claro es casi negro**: pasar el mouse por un `ListTile`
  /// o un `TextButton` dibujaba un bloque gris que no pertenece a ninguna
  /// paleta del sistema. El PF lo reportó como «sale ese cuadrado negro de la
  /// nada» y como que el hover está mal «no sólo en esa pantalla, en general».
  ///
  /// Era general de verdad: `rg 'hoverColor|splashColor|highlightColor'` sobre
  /// `app_theme.dart` daba CERO. Los componentes del kit ya resuelven su
  /// propio hover con [TreinoInteractiveState]; esto cubre a todos los demás
  /// —`ListTile`, `InkWell`, `IconButton`, `TextButton`, `PopupMenuItem`—,
  /// que son la mayoría de los que el PF toca.
  ///
  /// El tinte es `accent` y no un gris: un hover tiene que decir «esto
  /// responde», y el acento es el color con el que el sistema ya dice eso en
  /// todos lados. Las alfas son bajas a propósito — es una insinuación de
  /// superficie, no un relleno.
  static ThemeData _conEstadosDeInteraccion(ThemeData t, AppPalette palette) =>
      t.copyWith(
        hoverColor: palette.accent.withValues(alpha: 0.08),
        focusColor: palette.accent.withValues(alpha: 0.12),
        highlightColor: palette.accent.withValues(alpha: 0.10),
        splashColor: palette.accent.withValues(alpha: 0.12),
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: _ThumbDelScrollbar(palette.textMuted),
        ),
      );

  // Public factories
  // ---------------------------------------------------------------------------

  static ThemeData dark({AppPalette palette = AppPalette.mintMagenta}) {
    final base = GoogleFonts.barlowTextTheme(ThemeData.dark().textTheme);
    final textTheme = _buildTextTheme(palette, base);
    final errorColor = const ColorScheme.dark().error;

    final tema = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: palette.bg,
      colorScheme: ColorScheme.dark(
        primary: palette.accent,
        onPrimary: palette.bg,
        secondary: palette.highlight,
        onSecondary: palette.textPrimary,
        surface: palette.bgCard,
        onSurface: palette.textPrimary,
      ),
      inputDecorationTheme: _buildInputDecoration(palette, errorColor),
      appBarTheme: AppBarTheme(
        systemOverlayStyle: systemOverlayStyleFor(Brightness.dark),
      ),
      textTheme: textTheme,
      extensions: [palette],
    );
    return _conEstadosDeInteraccion(tema, palette);
  }

  static ThemeData light({AppPalette palette = AppPalette.mintMagentaLight}) {
    final base = GoogleFonts.barlowTextTheme(ThemeData.light().textTheme);
    final textTheme = _buildTextTheme(palette, base);

    final tema = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: palette.bg,
      colorScheme: ColorScheme.light(
        primary: palette.accent,
        onPrimary: palette.bg,
        secondary: palette.highlight,
        onSecondary: palette.textPrimary,
        surface: palette.bgCard,
        onSurface: palette.textPrimary,
        error: palette.danger,
        onError: palette.onDanger,
      ),
      inputDecorationTheme: _buildInputDecoration(palette, palette.danger),
      appBarTheme: AppBarTheme(
        systemOverlayStyle: systemOverlayStyleFor(Brightness.light),
      ),
      textTheme: textTheme,
      extensions: [palette],
    );
    return _conEstadosDeInteraccion(tema, palette);
  }
}

/// Color del thumb del scrollbar, con igualdad de VALOR.
///
/// Existe por una razón muy concreta y muy cara. La forma natural de escribir
/// esto es:
///
/// ```dart
/// thumbColor: WidgetStateProperty.resolveWith((states) => ...)
/// ```
///
/// y eso deja la app rebuildeando para siempre. `resolveWith` devuelve un
/// `_WidgetStatePropertyWith` que **no define `==`**, así que cada
/// construcción del tema produce una instancia nueva, el `ThemeData` nunca
/// compara igual con el anterior, y todo lo que depende del tema se
/// reconstruye en cada frame. Los controllers de animación se reinician con
/// él: cuatro tests de `core/widgets/motion` pasaron a rojo con
/// `hasRunningAnimations` en `true` para siempre. El test rojo fue el síntoma
/// barato; el caro es la regla 6 de AGENTS.md —cero rebuilds innecesarios—
/// rota en TODA la app desde el tema.
///
/// Con `==` y `hashCode` sobre el color base, dos temas construidos con la
/// misma paleta vuelven a compararse iguales.
@immutable
class _ThumbDelScrollbar implements WidgetStateProperty<Color> {
  const _ThumbDelScrollbar(this.base);

  final Color base;

  /// Se marca al pasar el mouse: un thumb que no reacciona no dice que se
  /// puede agarrar.
  @override
  Color resolve(Set<WidgetState> states) => base.withValues(
        alpha: states.contains(WidgetState.hovered) ? 0.5 : 0.28,
      );

  @override
  bool operator ==(Object other) =>
      other is _ThumbDelScrollbar && other.base == base;

  @override
  int get hashCode => base.hashCode;
}
