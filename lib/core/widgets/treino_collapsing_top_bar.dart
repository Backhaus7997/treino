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
/// En offset 0 NO hay fondo ni círculo: sólo la flecha «atrás» (izquierda) y
/// las [actions] (derecha) flotando arriba, y el [body] arranca debajo
/// (reservando [TreinoTopBarMetrics.reservedHeightOf]) o, si [overHero], bajo
/// la foto. Al scrollear más allá de [collapseOffset] aparece una barra
/// translúcida con desenfoque, borde inferior fino y el [title] chico
/// centrado; al volver arriba se desvanece.
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
  bool _collapsed = false;

  /// El fondo y el título sólo existen en el árbol mientras se ven o se están
  /// desvaneciendo: en offset 0 no hay nada que pintar (ni un
  /// `BackdropFilter` que re-muestree) ni un segundo texto con el título.
  bool _mounted = false;

  /// Opacidad objetivo. Se enciende un frame DESPUÉS de montar, para que el
  /// `AnimatedOpacity` parta de 0 y el aparecer sea un fade y no un corte.
  bool _shown = false;

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    final collapsed = n.metrics.pixels > widget.collapseOffset;
    if (collapsed != _collapsed) {
      setState(() {
        _collapsed = collapsed;
        if (collapsed) {
          _mounted = true;
        } else {
          // Si nunca llegó a mostrarse no hay fade que esperar.
          if (!_shown) _mounted = false;
          _shown = false;
        }
      });
      if (collapsed) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _collapsed) setState(() => _shown = true);
        });
      }
    }
    return false;
  }

  void _onFadeEnd() {
    if (!_collapsed && _mounted) setState(() => _mounted = false);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final title = widget.title;

    // Entrar y salir no pesan lo mismo: aparece con [AppMotion.base] y curva
    // de entrada, y se va más rápido con la de salida, para que al volver
    // arriba no quede colgando. Con «reducir movimiento» no hay deslizamiento,
    // sólo el fundido.
    final reduce = AppMotion.reduceMotion(context);
    final fadeDuration = _shown ? AppMotion.base : AppMotion.fast;
    final fadeCurve = _shown ? AppMotion.standard : AppMotion.exit;
    final slideDuration = reduce ? Duration.zero : fadeDuration;

    // Sobre foto y sin colapsar: blanco con sombra. Si no, color del tema.
    final onMedia = widget.overHero && !_collapsed;
    // intentional: media surface (el ícono vive sobre una foto/video).
    final iconColor = onMedia ? Colors.white : palette.textPrimary;
    final shadows = onMedia
        ? [
            Shadow(
              color: palette.scrimDark.withValues(alpha: 0.6),
              blurRadius: 8,
            ),
          ]
        : const <Shadow>[];

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
          child: Stack(
            children: [
              // Fondo: translúcido + desenfoque + borde inferior.
              if (_mounted)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      key: const Key('treino-top-bar-surface'),
                      opacity: _shown ? 1 : 0,
                      duration: fadeDuration,
                      curve: fadeCurve,
                      onEnd: _onFadeEnd,
                      // Baja desde arriba mientras aparece (y sube al irse):
                      // se lee como una barra que entra, no como un fondo que
                      // se enciende en el lugar.
                      child: AnimatedSlide(
                        key: const Key('treino-top-bar-surface-slide'),
                        offset: _shown || reduce
                            ? Offset.zero
                            : const Offset(0, -TreinoTopBarMetrics.enterSlide),
                        duration: slideDuration,
                        curve: fadeCurve,
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
              // Flecha + acciones. El color cambia con la misma curva que la
              // barra, así no hay un salto blanco → oscuro.
              Positioned(
                top: top + TreinoTopBarMetrics.topInset,
                left: 0,
                right: 0,
                height: TreinoTopBarMetrics.buttonSize,
                child: TweenAnimationBuilder<Color?>(
                  tween: ColorTween(end: iconColor),
                  duration: AppMotion.fast,
                  curve: AppMotion.standard,
                  builder: (context, color, child) => IconTheme(
                    data: IconThemeData(color: color, shadows: shadows),
                    child: IconButtonTheme(
                      data: IconButtonThemeData(
                        style: IconButton.styleFrom(foregroundColor: color),
                      ),
                      child: child!,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: TreinoTopBarMetrics.sideInset,
                    ),
                    // NavigationToolbar (el layout del AppBar de Flutter)
                    // centra el título según lo que MIDEN de verdad la
                    // flecha y las acciones. Contar las entradas de
                    // [actions] reservaba lugar para las que son
                    // `SizedBox.shrink()` y cortaba el título (Codex, #1596).
                    child: NavigationToolbar(
                      middleSpacing: TreinoTopBarMetrics.clearance,
                      leading: TreinoTopBarAction(
                        buttonKey: const Key('treino-top-bar-back'),
                        icon: TreinoIcon.back,
                        tooltip: l10n.commonBack,
                        onPressed: widget.onBack,
                      ),
                      middle: _mounted && title != null && title.isNotEmpty
                          ? IgnorePointer(
                              child: ExcludeSemantics(
                                excluding: !_collapsed,
                                child: AnimatedOpacity(
                                  key: const Key('treino-top-bar-title'),
                                  opacity: _shown ? 1 : 0,
                                  duration: fadeDuration,
                                  curve: fadeCurve,
                                  // El título sube un poco al entrar: acompaña
                                  // al grande que acaba de salir por arriba.
                                  child: AnimatedSlide(
                                    offset: _shown || reduce
                                        ? Offset.zero
                                        : const Offset(
                                            0,
                                            TreinoTopBarMetrics.titleEnterSlide,
                                          ),
                                    duration: slideDuration,
                                    curve: fadeCurve,
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
            ],
          ),
        ),
      ],
    );
  }
}
