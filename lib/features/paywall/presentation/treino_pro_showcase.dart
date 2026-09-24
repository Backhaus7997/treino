import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../domain/athlete_entitlement.dart';

/// Lo que TREINO Pro le suma al plan gratis: un valor por cada eje que el plan
/// gratis topea.
///
/// El par con `FreePlanLimit` vive en `free_plan_limit_sheet.dart`, que es la
/// que conoce los topes, y es un `switch` exhaustivo: un tope nuevo no compila
/// hasta que alguien decide qué beneficio le responde. Son seis y no ocho
/// porque `shapeDays`/`shapeWeeks` hablan del mismo eje que `days`/`weeks`.
enum TreinoProBenefit { days, weeks, templates, customize, routines, charts }

/// La tarjeta de TREINO Pro que muestra la hoja de límite.
///
/// ⚠️ **DESCRIBE EL PLAN Y NADA MÁS.** No tiene botón, ni precio, ni dice
/// dónde se consigue, ni anuncia que algo va a llegar por otro canal. Cada una
/// de esas cosas es un *"call to action for purchase outside of the app"* bajo
/// la Guideline 3.1.3(f), y esa exención es la que sostiene el cobro del
/// ENTRENADOR. Contar qué incluye un plan no es un llamado a comprarlo; decir
/// por dónde se compra, sí. `superficie_de_cobro_alumno_test.dart` escanea
/// este archivo con los mismos guards que la hoja.
///
/// **Siempre oscura, en los dos temas.** El nombre va con el degradé de la
/// marca, y el mint sobre el fondo claro da 1.57:1 (AGENTS.md §2): ilegible.
/// Sobre `ink` el tramo más flojo del degradé —el magenta— da 4.3:1, que
/// alcanza para un título de este tamaño. Por eso la tarjeta se pinta adentro
/// de un `Theme` con [AppPalette.mintMagenta], en vez de elegir colores a mano:
/// todos los tokens de adentro resuelven solos a la paleta oscura.
///
/// **La coreografía es de UNA vez y termina.** Un solo controller con
/// `Interval`s mueve todo —borde, halo, nombre, filas— y se apaga a los
/// [_duracion]. Nada queda en loop: un brillo infinito quema batería mientras
/// el alumno lee, y además colgaría el `pumpAndSettle` de cada test que abre
/// la hoja. Con reduce-motion arranca directo en el cuadro final.
class TreinoProShowcase extends StatefulWidget {
  const TreinoProShowcase({
    super.key,
    this.highlight,
    this.delay = Duration.zero,
  });

  /// El beneficio que responde al tope que el alumno acaba de tocar: va
  /// primero y resaltado. `null` → los seis en su orden, sin resaltar ninguno.
  final TreinoProBenefit? highlight;

  /// Espera antes de arrancar, para entrar después del encabezado de la hoja.
  /// Con reduce-motion se ignora.
  final Duration delay;

  @override
  State<TreinoProShowcase> createState() => _TreinoProShowcaseState();
}

class _TreinoProShowcaseState extends State<TreinoProShowcase>
    with SingleTickerProviderStateMixin {
  /// Cuánto dura la coreografía, sin contar [TreinoProShowcase.delay].
  ///
  /// Cinco tiempos de página y no un token propio: es una secuencia de
  /// transiciones de la escala del sistema —entrar, girar, brillar,
  /// asentar—, no un loop ambiental como el de `TreinoShimmer`. Derivarla de
  /// [AppMotion.slow] la deja atada a esa escala si algún día cambia.
  static final Duration _duracion = AppMotion.slow * 5;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.delay + _duracion,
  );

  // Los tramos, en fracciones de [_duracion]. Ver [_tramoDe].
  late final Animation<double> _entrada = _tramo(0, 0.2);
  late final Animation<double> _giro = _tramo(0, 0.75, AppMotion.emphasized);
  late final Animation<double> _halo = _tramo(0.1, 1).drive(_subeYAsienta);
  late final List<Animation<double>> _barridos = [
    _tramo(0.28, 0.55, AppMotion.emphasized),
    _tramo(0.62, 0.92, AppMotion.emphasized),
  ];
  late final Animation<double> _destello = _tramo(0.35, 0.8);
  late final Animation<double> _match = _tramo(0.6, 0.9);
  late final List<Animation<double>> _filas = [
    for (var i = 0; i < TreinoProBenefit.values.length; i++)
      _tramo(0.16 + i * 0.07, 0.46 + i * 0.07),
  ];

  /// El halo sube hasta pleno y se queda en un resto: tiene que notarse al
  /// entrar y no competir con el texto cuando el alumno ya está leyendo.
  static final Animatable<double> _subeYAsienta = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 55),
    TweenSequenceItem(
      tween: Tween<double>(begin: 1, end: 0.55)
          .chain(CurveTween(curve: AppMotion.emphasized)),
      weight: 45,
    ),
  ]);

  bool _arranco = false;

  Animation<double> _tramo(
    double desde,
    double hasta, [
    Curve curva = AppMotion.standard,
  ]) =>
      _tramoDe(_controller, widget.delay, desde, hasta, curva);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _arranco = _arrancarOSaltar(_controller, context, yaArranco: _arranco);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        extensions: [
          for (final e in base.extensions.values)
            if (e is! AppPalette) e,
          AppPalette.mintMagenta,
        ],
      ),
      // El Builder es para que `AppPalette.of` de adentro ya lea la oscura.
      child: Builder(builder: _tarjeta),
    );
  }

  Widget _tarjeta(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final highlight = widget.highlight;
    final orden = [
      if (highlight != null) highlight,
      for (final b in TreinoProBenefit.values)
        if (b != highlight) b,
    ];
    final degradeBorde = [palette.accent, palette.highlight, palette.accent];

    return FadeTransition(
      key: const Key('treino_pro_showcase'),
      opacity: _entrada,
      alwaysIncludeSemantics: true,
      child: _Deslizar(
        animacion: _entrada,
        distancia: AppMotion.slideLg,
        child: CustomPaint(
          painter: _BordePainter(
            giro: _giro,
            halo: _halo,
            colores: degradeBorde,
            difuso: true,
          ),
          foregroundPainter: _BordePainter(
            giro: _giro,
            halo: _halo,
            colores: degradeBorde,
            difuso: false,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.bg,
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s12,
                AppSpacing.s20,
                AppSpacing.s12,
                AppSpacing.s12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Nombre(
                          nombre:
                              l10n.paywallFreePlanLimitProName.toUpperCase(),
                          barridos: _barridos,
                          destello: _destello,
                        ),
                        const SizedBox(height: AppSpacing.s8),
                        Text(
                          l10n.paywallFreePlanLimitProTagline,
                          style: TextStyle(
                            fontFamily: AppFonts.barlow,
                            fontSize: AppTextSize.body,
                            height: 1.4,
                            color: palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s12),
                  for (var i = 0; i < orden.length; i++)
                    _Fila(
                      key: Key('treino_pro_benefit_${orden[i].name}'),
                      icono: _iconoDe(orden[i]),
                      texto: _textoDe(l10n, orden[i]),
                      entrada: _filas[i],
                      match: orden[i] == highlight ? _match : null,
                      etiqueta: l10n.paywallFreePlanLimitProMatchTag,
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

/// El texto de cada beneficio. Los números salen de las constantes de
/// `athlete_entitlement.dart` y no de la cadena: un tope escrito a mano en el
/// `.arb` ya quedó mintiendo una vez, el día que el de días pasó de 2 a 3.
String _textoDe(AppL10n l10n, TreinoProBenefit beneficio) =>
    switch (beneficio) {
      TreinoProBenefit.days =>
        l10n.paywallFreePlanLimitProBenefitDays(kMaxRoutineDays),
      TreinoProBenefit.weeks =>
        l10n.paywallFreePlanLimitProBenefitWeeks(kMaxRoutineWeeks),
      TreinoProBenefit.templates =>
        l10n.paywallFreePlanLimitProBenefitTemplates,
      TreinoProBenefit.customize =>
        l10n.paywallFreePlanLimitProBenefitCustomize,
      TreinoProBenefit.routines =>
        l10n.paywallFreePlanLimitProBenefitRoutines(kMaxOwnRoutines),
      TreinoProBenefit.charts => l10n.paywallFreePlanLimitProBenefitCharts,
    };

IconData _iconoDe(TreinoProBenefit beneficio) => switch (beneficio) {
      TreinoProBenefit.days => TreinoIcon.calendar,
      TreinoProBenefit.weeks => TreinoIcon.trendUp,
      TreinoProBenefit.templates => TreinoIcon.viewCards,
      TreinoProBenefit.customize => TreinoIcon.edit,
      TreinoProBenefit.routines => TreinoIcon.dumbbell,
      TreinoProBenefit.charts => TreinoIcon.chartBar,
    };

/// El candado del encabezado de la hoja: un aro con el degradé de la marca que
/// se dibuja, el candado que aparece con un rebote, y un latido que se abre
/// una sola vez.
///
/// **El candado NO se abre**, y es a propósito: nada se desbloquea en esta
/// hoja. Una animación de «abrirse» prometería una salida que la app no puede
/// dar — ver el encabezado de [TreinoProShowcase].
class FreePlanLimitLockBadge extends StatefulWidget {
  const FreePlanLimitLockBadge({super.key, this.delay = Duration.zero});

  /// Espera antes de arrancar. Con reduce-motion se ignora.
  final Duration delay;

  @override
  State<FreePlanLimitLockBadge> createState() => _FreePlanLimitLockBadgeState();
}

class _FreePlanLimitLockBadgeState extends State<FreePlanLimitLockBadge>
    with SingleTickerProviderStateMixin {
  /// Tres tiempos de página: dibujar el aro, asentar el candado, latir.
  static final Duration _duracion = AppMotion.slow * 3;

  static const double _diametro = 44;
  static const double _tamIcono = 20;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.delay + _duracion,
  );
  late final Animation<double> _aro =
      _tramoDe(_controller, widget.delay, 0, 0.55, AppMotion.standard);
  late final Animation<double> _rebote =
      _tramoDe(_controller, widget.delay, 0.1, 0.6, AppMotion.standard)
          .drive(_pasaYVuelve(desde: 0.4, pico: 1.15));
  late final Animation<double> _latido =
      _tramoDe(_controller, widget.delay, 0.55, 1, AppMotion.standard);

  bool _arranco = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _arranco = _arrancarOSaltar(_controller, context, yaArranco: _arranco);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizedBox.square(
      dimension: _diametro,
      child: CustomPaint(
        painter: _AroPainter(
          aro: _aro,
          latido: _latido,
          colores: [palette.accent, palette.highlight, palette.accent],
          fondo: palette.highlight.withValues(alpha: 0.14),
        ),
        child: Center(
          child: ScaleTransition(
            scale: _rebote,
            child: Icon(
              TreinoIcon.lock,
              size: _tamIcono,
              color: palette.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Coreografía compartida ────────────────────────────────────────────────

/// Un tramo de la coreografía de [controller], en fracciones de la parte VIVA
/// de su duración.
///
/// Los primeros [retardo] del controller son tiempo muerto —mismo recurso que
/// `TreinoFadeSlideIn`: el retardo es la porción inicial de un [Interval], no
/// un `Future.delayed`—, así que no hay timers sueltos que carreren con el
/// desmonte. `drive` y no `CurvedAnimation`: no registra listeners propios y
/// no hay nada que liberar.
Animation<double> _tramoDe(
  AnimationController controller,
  Duration retardo,
  double desde,
  double hasta,
  Curve curva,
) {
  final muerto = retardo.inMicroseconds / controller.duration!.inMicroseconds;
  return controller.drive(
    CurveTween(
      curve: Interval(
        muerto + desde * (1 - muerto),
        muerto + hasta * (1 - muerto),
        curve: curva,
      ),
    ),
  );
}

/// Arranca la coreografía en el primer `didChangeDependencies`, o la deja en
/// el cuadro final si el sistema pide reducir movimiento. Devuelve el nuevo
/// valor de `yaArranco`.
///
/// Va en `didChangeDependencies` y no en `initState` porque reduce-motion
/// necesita `MediaQuery` — mismo patrón que `TreinoFadeSlideIn`. Y si la
/// preferencia se activa a mitad de camino, salta al final.
bool _arrancarOSaltar(
  AnimationController controller,
  BuildContext context, {
  required bool yaArranco,
}) {
  final reducir = AppMotion.reduceMotion(context);
  if (!yaArranco) {
    if (reducir) {
      controller.value = 1;
    } else {
      controller.forward();
    }
  } else if (reducir && !controller.isCompleted) {
    controller
      ..stop()
      ..value = 1;
  }
  return true;
}

/// De [desde] a [pico] y de vuelta a 1: el rebote de algo que aparece.
Animatable<double> _pasaYVuelve(
        {required double desde, required double pico}) =>
    TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: desde, end: pico), weight: 60),
      TweenSequenceItem(
        tween: Tween<double>(begin: pico, end: 1)
            .chain(CurveTween(curve: AppMotion.emphasized)),
        weight: 40,
      ),
    ]);

// ── Piezas ────────────────────────────────────────────────────────────────

/// Sube [distancia] px exactos hasta su lugar. `Transform.translate` y no
/// `SlideTransition` por lo mismo que `TreinoFadeSlideIn`: el slide del
/// sistema se mide en px, no en fracciones del alto del hijo.
class _Deslizar extends AnimatedWidget {
  const _Deslizar({
    required Animation<double> animacion,
    required this.distancia,
    required this.child,
  }) : super(listenable: animacion);

  final double distancia;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value;
    return Transform.translate(
      offset: Offset(0, (1 - t) * distancia),
      child: child,
    );
  }
}

/// «TREINO PRO» con el degradé de la marca, dos barridos de brillo y un
/// destello al lado.
class _Nombre extends StatelessWidget {
  const _Nombre({
    required this.nombre,
    required this.barridos,
    required this.destello,
  });

  final String nombre;
  final List<Animation<double>> barridos;
  final Animation<double> destello;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final texto = Text(
      nombre,
      style: TextStyle(
        fontFamily: AppFonts.barlowCondensed,
        fontSize: AppTextSize.displayLarge,
        fontWeight: AppFonts.w700,
        letterSpacing: AppFonts.headingTracking,
        height: 1,
        // El color real lo pone el ShaderMask; éste sólo aporta el alfa.
        color: palette.textPrimary,
      ),
    );

    return Row(
      children: [
        Flexible(
          child: Stack(
            children: [
              ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (r) => LinearGradient(
                  colors: [palette.accent, palette.highlight],
                ).createShader(r),
                child: texto,
              ),
              for (final barrido in barridos)
                _Barrido(animacion: barrido, child: texto),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.s8),
        _Destello(animacion: destello),
      ],
    );
  }
}

/// Una franja de luz que cruza el nombre de izquierda a derecha.
class _Barrido extends AnimatedWidget {
  const _Barrido({required Animation<double> animacion, required this.child})
      : super(listenable: animacion);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value;
    // Fuera de su tramo el barrido no existe: ni capa ni shader.
    if (t <= 0 || t >= 1) return const SizedBox.shrink();
    final luz = AppPalette.of(context).textPrimary;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => LinearGradient(
        colors: [
          luz.withValues(alpha: 0),
          luz.withValues(alpha: 0.85),
          luz.withValues(alpha: 0),
        ],
        stops: const [0.38, 0.5, 0.62],
        transform: _Corrimiento(t),
      ).createShader(r),
      child: child,
    );
  }
}

/// Corre el degradé de [_Barrido] de afuera a la izquierda (t=0) a afuera a
/// la derecha (t=1).
class _Corrimiento extends GradientTransform {
  const _Corrimiento(this.t);

  final double t;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (t * 2 - 1), 0, 0);
}

/// Dos destellos que aparecen girando, uno magenta y uno mint.
class _Destello extends AnimatedWidget {
  const _Destello({required Animation<double> animacion})
      : super(listenable: animacion);

  static const double _grande = 22;
  static const double _chico = 12;
  static final Animatable<double> _guino = _pasaYVuelve(desde: 0, pico: 1.3);

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value;
    final palette = AppPalette.of(context);
    // El chico entra con un poco de atraso: dos destellos a la vez se leen
    // como uno solo.
    final tChico = ((t - 0.3) / 0.7).clamp(0.0, 1.0);

    return SizedBox.square(
      dimension: _grande + _chico,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            bottom: 0,
            child: Transform.rotate(
              angle: (1 - t) * -math.pi / 2,
              child: Transform.scale(
                scale: _guino.transform(t),
                child: Icon(
                  TreinoIcon.sparkle,
                  size: _grande,
                  color: palette.highlight,
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: Transform.scale(
              scale: _guino.transform(tChico),
              child: Icon(
                TreinoIcon.sparkle,
                size: _chico,
                color: palette.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Un beneficio. La fila que responde al tope tocado ([match] no nulo) se
/// tiñe, gana una etiqueta y su insignia pasa al degradé con un rebote.
class _Fila extends StatelessWidget {
  const _Fila({
    super.key,
    required this.icono,
    required this.texto,
    required this.entrada,
    required this.match,
    required this.etiqueta,
  });

  final IconData icono;
  final String texto;
  final Animation<double> entrada;
  final Animation<double>? match;
  final String etiqueta;

  static const double _insignia = 32;
  static const double _tamIcono = 16;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final match = this.match;

    final textoFila = Text(
      texto,
      style: TextStyle(
        fontFamily: AppFonts.barlow,
        fontSize: AppTextSize.body,
        fontWeight: AppFonts.w600,
        height: 1.3,
        color: palette.textPrimary,
      ),
    );

    final Widget fila;
    if (match == null) {
      fila = Padding(
        padding: const EdgeInsets.all(AppSpacing.s8),
        child: Row(
          children: [
            _Insignia(icono: icono, resaltada: false),
            const SizedBox(width: AppSpacing.s12),
            Expanded(child: textoFila),
            ScaleTransition(
              scale: entrada.drive(_pasaYVuelve(desde: 0, pico: 1.25)),
              child: Icon(
                TreinoIcon.checkBare,
                size: _tamIcono,
                color: palette.accent,
              ),
            ),
          ],
        ),
      );
    } else {
      fila = AnimatedBuilder(
        animation: match,
        builder: (context, child) => DecoratedBox(
          decoration: BoxDecoration(
            color: palette.accent.withValues(alpha: 0.1 * match.value),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: palette.accent.withValues(alpha: 0.45 * match.value),
            ),
          ),
          child: child,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s8),
          child: Row(
            children: [
              ScaleTransition(
                scale: match.drive(_pasaYVuelve(desde: 1, pico: 1.2)),
                child: _Insignia(icono: icono, resaltada: true),
              ),
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FadeTransition(
                      opacity: match,
                      alwaysIncludeSemantics: true,
                      child: Text(
                        etiqueta.toUpperCase(),
                        key: const Key('treino_pro_match_tag'),
                        style: TextStyle(
                          fontFamily: AppFonts.barlowCondensed,
                          fontSize: AppTextSize.caption,
                          fontWeight: AppFonts.w700,
                          letterSpacing: 1,
                          color: palette.accent,
                        ),
                      ),
                    ),
                    textoFila,
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return FadeTransition(
      opacity: entrada,
      alwaysIncludeSemantics: true,
      child: _Deslizar(
        animacion: entrada,
        distancia: AppMotion.slideMd,
        child: fila,
      ),
    );
  }
}

/// El círculo con el ícono de cada beneficio. El resaltado va con el degradé
/// y el ícono en `ink`, que sobre el tramo magenta da 4.3:1.
class _Insignia extends StatelessWidget {
  const _Insignia({required this.icono, required this.resaltada});

  final IconData icono;
  final bool resaltada;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: _Fila._insignia,
      height: _Fila._insignia,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: resaltada ? null : palette.surfaceSubtle,
        gradient: resaltada
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [palette.accent, palette.highlight],
              )
            : null,
      ),
      child: Icon(
        icono,
        size: _Fila._tamIcono,
        color:
            resaltada ? TreinoButtonTokens.foreground(context) : palette.accent,
      ),
    );
  }
}

/// El borde de la tarjeta: un degradé de barrido que da una vuelta entera y
/// se queda quieto.
///
/// Se pinta dos veces: [difuso] `true` va DETRÁS de la tarjeta y hace el halo
/// —el fondo opaco tapa la mitad de adentro, así que sólo se ve el resplandor
/// de afuera—; `false` va ENCIMA y es el trazo nítido.
class _BordePainter extends CustomPainter {
  _BordePainter({
    required this.giro,
    required this.halo,
    required this.colores,
    required this.difuso,
  }) : super(repaint: Listenable.merge([giro, halo]));

  final Animation<double> giro;
  final Animation<double> halo;
  final List<Color> colores;
  final bool difuso;

  static const double _trazo = 1.5;

  /// Sigma del halo a pleno. Con el padding lateral de la hoja (18 px) el
  /// resplandor entra entero antes de que lo corte el scroll.
  static const double _difuminado = 6;

  @override
  void paint(Canvas canvas, Size size) {
    final intensidad = difuso ? halo.value : 1.0;
    if (intensidad <= 0) return;

    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(_trazo / 2),
      const Radius.circular(AppRadius.lg),
    );
    final pincel = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = difuso ? _trazo * 4 : _trazo
      ..shader = SweepGradient(
        colors: [
          for (final c in colores) c.withValues(alpha: c.a * intensidad),
        ],
        transform: GradientRotation(2 * math.pi * giro.value),
      ).createShader(rect);
    if (difuso) {
      pincel.maskFilter = const MaskFilter.blur(BlurStyle.normal, _difuminado);
    }
    canvas.drawRRect(rrect, pincel);
  }

  @override
  bool shouldRepaint(_BordePainter old) =>
      old.difuso != difuso || !_mismosColores(old.colores, colores);
}

/// El aro del candado: un fondo teñido, el arco que se dibuja y el latido.
class _AroPainter extends CustomPainter {
  _AroPainter({
    required this.aro,
    required this.latido,
    required this.colores,
    required this.fondo,
  }) : super(repaint: Listenable.merge([aro, latido]));

  final Animation<double> aro;
  final Animation<double> latido;
  final List<Color> colores;
  final Color fondo;

  static const double _trazo = 2;

  /// Cuánto crece el latido respecto del aro: un 40% más de radio.
  static const double _alcanceLatido = 0.4;

  @override
  void paint(Canvas canvas, Size size) {
    final centro = size.center(Offset.zero);
    final radio = size.shortestSide / 2 - _trazo / 2;
    final rect = Rect.fromCircle(center: centro, radius: radio);

    canvas.drawCircle(centro, radio, Paint()..color = fondo);

    final shader = SweepGradient(
      colors: colores,
      transform: const GradientRotation(-math.pi / 2),
    ).createShader(rect);

    if (aro.value > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * aro.value,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _trazo
          ..strokeCap = StrokeCap.round
          ..shader = shader,
      );
    }

    final l = latido.value;
    if (l > 0 && l < 1) {
      canvas.drawCircle(
        centro,
        radio * (1 + _alcanceLatido * l),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = _trazo
          ..color = colores[1].withValues(alpha: 0.6 * (1 - l)),
      );
    }
  }

  @override
  bool shouldRepaint(_AroPainter old) =>
      old.fondo != fondo || !_mismosColores(old.colores, colores);
}

bool _mismosColores(List<Color> a, List<Color> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
