import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_motion.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/tokens/tokens.dart';
import '../../l10n/app_l10n.dart';
import 'treino_icon.dart';

/// Medidas de la barra superior de las pantallas de detalle.
///
/// Fuente única (#1559): el botón, la barra y el alto que el contenido reserva
/// debajo salen de las MISMAS constantes, así que no pueden desincronizarse.
abstract final class TreinoTopBarMetrics {
  /// Separación entre el borde superior del área segura y el botón.
  static const double topInset = 8;

  /// Separación horizontal contra el borde de la pantalla.
  static const double sideInset = 12;

  /// Lado del botón (≥ 44 pt). Lo impone [buttonStyle]: sin él, el
  /// `IconButton` mide 48 en móvil pero 40 en escritorio
  /// (`MaterialTapTargetSize.shrinkWrap`).
  static const double buttonSize = 48;

  /// Aire entre el botón y el contenido que arranca debajo.
  static const double clearance = 8;

  /// Alto de la barra por debajo del inset superior del sistema.
  static const double barHeight = topInset + buttonSize + clearance;

  /// Alto que el contenido debe reservar ARRIBA para no quedar bajo los
  /// botones: la barra más el inset superior que la pantalla todavía no
  /// consumió (0 cuando ya está dentro de un `SafeArea`).
  static double reservedHeightOf(BuildContext context) =>
      MediaQuery.paddingOf(context).top + barHeight;

  /// Estilo de todo `IconButton` de la barra: fija el tamaño en [buttonSize].
  static final ButtonStyle buttonStyle = IconButton.styleFrom(
    fixedSize: const Size.square(buttonSize),
  );

  /// Sigma del desenfoque del fondo cuando la barra aparece.
  static const double blurSigma = 12;

  /// Opacidad del color de superficie de la barra (translúcida: se insinúa
  /// el contenido que pasa por debajo).
  static const double surfaceAlpha = 0.78;

  /// Lado de la burbuja de la flecha con la barra oculta (el mismo círculo
  /// que AuthCircleBackButton). Más chica que [buttonSize]: el blanco táctil
  /// sigue siendo de 48.
  static const double bubbleSize = 44;

  /// Opacidad del relleno de la burbuja: lo justo para despegarla de una foto.
  static const double bubbleAlpha = 0.55;

  /// Cuántos px de scroll dura la aparición, terminando en `collapseOffset`.
  /// Aprox. el alto de la barra: la barra entra mientras el contenido avanza
  /// lo que ella mide, así se siente arrastrada por el dedo.
  static const double revealDistance = 72;

  /// Fracción de su propio alto desde la que baja el fondo al aparecer.
  static const double enterSlide = 0.35;

  /// Fracción de su propio alto desde la que sube el título al aparecer.
  static const double titleEnterSlide = 0.4;
}

/// Acción de la barra superior (editar, seguir, menú…): un [IconButton] de
/// [TreinoTopBarMetrics.buttonSize] SIN círculo ni fondo. El color del ícono
/// lo pone la barra (blanco con sombra sobre una foto, `textPrimary` sobre
/// superficie) salvo que [color] lo fije.
class TreinoTopBarAction extends StatelessWidget {
  const TreinoTopBarAction({
    super.key,
    this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  /// Key del `IconButton` interno (los tests lo toman por acá).
  final Key? buttonKey;

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Color propio (estado bloqueado, "ya la seguís"…). Null = el de la barra.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      onTap: onPressed,
      child: IconButton(
        key: buttonKey,
        style: TreinoTopBarMetrics.buttonStyle,
        tooltip: tooltip,
        icon: Icon(icon, color: color),
        onPressed: onPressed,
      ),
    );
  }
}

/// Barra superior que aparece al scrollear (#1559).
///
/// En offset 0 NO hay barra: la flecha «atrás» (izquierda, dentro de una
/// burbuja que se desvanece al entrar la barra) y las [actions] (derecha)
/// flotan arriba, y el [body] arranca debajo
/// (reservando [TreinoTopBarMetrics.reservedHeightOf]) o, si [overHero], bajo
/// la foto. Al acercarse a [collapseOffset] aparece una barra translúcida con
/// desenfoque, borde inferior fino y el [title] chico centrado.
///
/// La aparición SIGUE AL SCROLL, no es una animación con duración: en los
/// [TreinoTopBarMetrics.revealDistance] px previos a [collapseOffset] el fondo
/// baja y se funde, y el título sube y se funde, en proporción a lo
/// scrolleado. Scrollear despacio la muestra despacio, frenar a mitad la deja
/// a mitad, y al volver arriba se va al mismo ritmo.
///
/// Escucha el `ScrollNotification` vertical del [body], así que sirve con
/// `CustomScrollView`, `ListView` o `SingleChildScrollView` sin controller.
///
/// El [body] debe empezar a [TreinoTopBarMetrics.reservedHeightOf] del borde
/// superior (padding o hero que lo cubra): la barra no empuja el contenido.
class TreinoCollapsingTopBar extends StatefulWidget {
  const TreinoCollapsingTopBar({
    super.key,
    required this.body,
    required this.onBack,
    this.title,
    this.actions = const [],
    this.overHero = false,
    this.collapseOffset = 96,
  });

  final Widget body;

  /// Navegación de la flecha (típicamente `pop` con ruta de rescate).
  final VoidCallback onBack;

  /// Título chico de la barra colapsada. Null = barra sin título.
  final String? title;

  /// Acciones a la derecha, normalmente [TreinoTopBarAction].
  final List<Widget> actions;

  /// El tope del [body] es una foto/video: en offset 0 los íconos van blancos
  /// con sombra para que se lean, en vez de `textPrimary`.
  final bool overHero;

  /// Offset de scroll desde el que aparece la barra: aprox. cuando el título
  /// grande ya salió de la pantalla.
  final double collapseOffset;

  @override
  State<TreinoCollapsingTopBar> createState() => _TreinoCollapsingTopBarState();
}

class _TreinoCollapsingTopBarState extends State<TreinoCollapsingTopBar> {
  /// 0 = barra invisible (arriba del todo), 1 = barra entera. Un notifier y
  /// no `setState`: cambia en cada frame del scroll y sólo tiene que
  /// redibujar la barra, nunca el [TreinoCollapsingTopBar.body].
  final _progress = ValueNotifier<double>(0);

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    const distance = TreinoTopBarMetrics.revealDistance;
    final start = widget.collapseOffset - distance;
    _progress.value =
        ((n.metrics.pixels - start) / distance).clamp(0.0, 1.0).toDouble();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final title = widget.title;
    // Con «reducir movimiento» no hay deslizamiento: sólo el fundido, que
    // igual acompaña al scroll.
    final reduce = AppMotion.reduceMotion(context);

    return Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: widget.body,
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: top + TreinoTopBarMetrics.barHeight,
          child: ValueListenableBuilder<double>(
            valueListenable: _progress,
            builder: (context, t, _) =>
                _buildBar(context, palette, l10n, top, title, t, reduce),
          ),
        ),
      ],
    );
  }

  Widget _buildBar(
    BuildContext context,
    AppPalette palette,
    AppL10n l10n,
    double top,
    String? title,
    double t,
    bool reduce,
  ) {
    // Curva sobre el progreso lineal del scroll: arranca suave y asienta, en
    // vez de un movimiento a velocidad constante que se ve mecánico.
    final eased = AppMotion.standard.transform(t);
    // El fondo y el título sólo existen en el árbol mientras se ven: en
    // offset 0 no hay nada que pintar (ni un `BackdropFilter` que
    // re-muestree) ni un segundo texto con el título.
    final visible = t > 0;
    final collapsed = t >= 0.5;

    // Sobre foto: el ícono pasa de blanco con sombra a `textPrimary` en
    // proporción al scroll, así no hay un salto blanco → oscuro.
    // intentional: media surface (el ícono vive sobre una foto/video).
    final iconColor = widget.overHero
        ? Color.lerp(Colors.white, palette.textPrimary, eased)!
        : palette.textPrimary;
    final shadowAlpha = widget.overHero ? 0.6 * (1 - eased) : 0.0;
    final shadows = shadowAlpha > 0
        ? [
            Shadow(
              color: palette.scrimDark.withValues(alpha: shadowAlpha),
              blurRadius: 8,
            ),
          ]
        : const <Shadow>[];

    return Stack(
      children: [
        // Fondo: translúcido + desenfoque + borde inferior. Baja desde arriba
        // mientras aparece: se lee como una barra que entra, no como un fondo
        // que se enciende en el lugar.
        if (visible)
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                key: const Key('treino-top-bar-surface'),
                opacity: eased,
                child: FractionalTranslation(
                  key: const Key('treino-top-bar-surface-slide'),
                  translation: reduce
                      ? Offset.zero
                      : Offset(
                          0,
                          -TreinoTopBarMetrics.enterSlide * (1 - eased),
                        ),
                  child: ClipRect(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: TreinoTopBarMetrics.blurSigma,
                        sigmaY: TreinoTopBarMetrics.blurSigma,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: palette.bgCard.withValues(
                            alpha: TreinoTopBarMetrics.surfaceAlpha,
                          ),
                          border: Border(
                            bottom: BorderSide(color: palette.border),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          top: top + TreinoTopBarMetrics.topInset,
          left: 0,
          right: 0,
          height: TreinoTopBarMetrics.buttonSize,
          child: IconTheme(
            data: IconThemeData(color: iconColor, shadows: shadows),
            child: IconButtonTheme(
              data: IconButtonThemeData(
                style: IconButton.styleFrom(foregroundColor: iconColor),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: TreinoTopBarMetrics.sideInset,
                ),
                // NavigationToolbar (el layout del AppBar de Flutter) centra
                // el título según lo que MIDEN de verdad la flecha y las
                // acciones. Contar las entradas de [actions] reservaba lugar
                // para las que son `SizedBox.shrink()` y cortaba el título
                // (Codex, #1596).
                child: NavigationToolbar(
                  middleSpacing: TreinoTopBarMetrics.clearance,
                  // Con la barra oculta la flecha lleva la burbuja del resto
                  // de la app (círculo de 44 con borde fino, como
                  // AuthCircleBackButton) más un relleno suave para que se
                  // lea sobre una foto. Se desvanece a medida que entra la
                  // barra: con fondo detrás ya no hace falta.
                  leading: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (eased < 1)
                        IgnorePointer(
                          child: Opacity(
                            key: const Key('treino-top-bar-back-bubble'),
                            opacity: 1 - eased,
                            child: Container(
                              width: TreinoTopBarMetrics.bubbleSize,
                              height: TreinoTopBarMetrics.bubbleSize,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: palette.bgCard.withValues(
                                  alpha: TreinoTopBarMetrics.bubbleAlpha,
                                ),
                                border: Border.all(color: palette.border),
                              ),
                            ),
                          ),
                        ),
                      TreinoTopBarAction(
                        buttonKey: const Key('treino-top-bar-back'),
                        icon: TreinoIcon.back,
                        tooltip: l10n.commonBack,
                        onPressed: widget.onBack,
                      ),
                    ],
                  ),
                  middle: visible && title != null && title.isNotEmpty
                      ? IgnorePointer(
                          child: ExcludeSemantics(
                            excluding: !collapsed,
                            child: Opacity(
                              key: const Key('treino-top-bar-title'),
                              opacity: eased,
                              // El título sube un poco al entrar: acompaña al
                              // grande que está saliendo por arriba.
                              child: FractionalTranslation(
                                translation: reduce
                                    ? Offset.zero
                                    : Offset(
                                        0,
                                        TreinoTopBarMetrics.titleEnterSlide *
                                            (1 - eased),
                                      ),
                                child: Center(
                                  child: Text(
                                    title.toUpperCase(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.barlowCondensed(
                                      fontWeight: FontWeight.w700,
                                      fontSize: AppTextSize.title,
                                      letterSpacing: 0.5,
                                      color: palette.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: widget.actions,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
