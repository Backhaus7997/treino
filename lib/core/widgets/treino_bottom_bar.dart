import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_motion.dart';
import '../../app/theme/app_palette.dart';
import 'treino_icon.dart';

/// Cuánto se separa el pill activo del borde de su tab, en los cuatro lados.
///
/// Cada punto de inset son DOS puntos menos de caja para el label. Con 8 —el
/// valor original— "ENTRENAR" no entraba en un Android de 360dp, el ancho más
/// común del parque, y la barra caía al modo sin labels. Con 6 entra.
const double _kPillInset = 6;

/// Redondeo del pill activo.
///
/// Era 28, que sobre un pill de 60 de alto lo vuelve una cápsula perfecta — y a
/// la altura del label la curva entra 7,4pt por lado cuando el label sólo tiene
/// 6 de margen, así que le recorta la primera y la última letra (el clásico
/// "ENTRENAR → ENTRENR"). Con 20 la curva entra 2,14pt y la palabra entra
/// entera sin perder el aire de cápsula.
const double _kPillRadius = 20;

/// Cuánto se mete el redondeo hacia adentro, a `dy` de distancia del centro
/// vertical de una caja de media altura [halfHeight] y radio [radius].
///
/// Mientras `dy` no pase de la parte recta del costado, el redondeo no come
/// nada. Después el borde es un arco de circunferencia y se calcula así.
double _cornerInsetAt({
  required double dy,
  required double halfHeight,
  required double radius,
}) {
  final straight = halfHeight - radius;
  if (dy <= straight) return 0;
  final d = dy - straight;
  if (d >= radius) return radius;
  return radius - math.sqrt(radius * radius - d * d);
}

/// Bottom bar de TREINO: pill flotante translúcida (fill de alta opacidad,
/// SIN blur — ver nota en el build), pill de gradient que se desliza al tab
/// activo, íconos `TreinoIcon` + labels Barlow Condensed.
///
/// **Los cinco destinos se ven SIEMPRE, repartidos en partes iguales.** Cuando
/// los labels no entran a lo ancho —pantalla muy chica, o el usuario agrandó la
/// tipografía del sistema— la barra se queda con los íconos. Antes había acá un
/// camino aparte que la volvía una tira scrolleable horizontal con tabs de
/// ancho fijo: eso dejaba PERFIL FUERA DE PANTALLA y corría el resto de los
/// destinos hacia la derecha (issue #634). Una barra de navegación que hay que
/// scrollear para llegar a una pestaña no es una barra de navegación.
class TreinoBottomBar extends StatefulWidget {
  const TreinoBottomBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.coachUnreadCount = 0,
    this.feedUnreadCount = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Count of unread chats with the athlete's coach — shown as a badge on
  /// the COACH tab (index 3). Pass 0 (default) to hide the badge.
  final int coachUnreadCount;

  /// Count of unread chats with friends (user↔user, social) — shown as a
  /// badge on the FEED tab (index 1) so the user sees the alert without
  /// having to open the tab first. Pass 0 (default) to hide the badge.
  final int feedUnreadCount;

  @override
  State<TreinoBottomBar> createState() => _TreinoBottomBarState();

  static const List<_TabSpec> _items = [
    _TabSpec(
      label: 'ENTRENAR',
      icon: TreinoIcon.tabWorkout,
      iconActive: TreinoIcon.tabWorkoutFill,
    ),
    _TabSpec(
      label: 'FEED',
      icon: TreinoIcon.tabFeed,
      iconActive: TreinoIcon.tabFeedFill,
    ),
    _TabSpec(
      label: 'INICIO',
      icon: TreinoIcon.tabHome,
      iconActive: TreinoIcon.tabHomeFill,
    ),
    _TabSpec(
      label: 'COACH',
      icon: TreinoIcon.tabCoach,
      iconActive: TreinoIcon.tabCoachFill,
    ),
    _TabSpec(
      label: 'PERFIL',
      icon: TreinoIcon.tabProfile,
      iconActive: TreinoIcon.tabProfileFill,
    ),
  ];

  int _badgeCountFor(int index) => switch (index) {
        1 => feedUnreadCount,
        3 => coachUnreadCount,
        _ => 0,
      };
}

class _TreinoBottomBarState extends State<TreinoBottomBar> {
  @override
  void initState() {
    super.initState();
    // La barra MIDE el texto para decidir si los labels entran, y esa medición
    // corre una sola vez adentro del `LayoutBuilder`: no se rehace cuando
    // cambian las fuentes, porque las constraints no cambian.
    //
    // `google_fonts` registra Barlow Condensed de forma ASÍNCRONA, así que el
    // primer frame se mide con la fallback del sistema — SF Pro en iOS, Roboto
    // en Android— que no es condensada y es bastante más ancha ("ENTRENAR" pasa
    // de 44,36pt a ~62). Con esa medida la barra tomaba la decisión equivocada
    // y se quedaba con ella PARA SIEMPRE.
    //
    // `PaintingBinding.systemFonts` notifica justo cuando el engine termina de
    // registrar una fuente nueva. Un `setState` acá hace que el `LayoutBuilder`
    // vuelva a correr y re-mida con la tipografía real.
    PaintingBinding.instance.systemFonts.addListener(_onSystemFontsChanged);
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_onSystemFontsChanged);
    super.dispose();
  }

  void _onSystemFontsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final labelStyle = GoogleFonts.barlowCondensed(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    );

    return SafeArea(
      top: false,
      child: Padding(
        // Generous side/bottom margins lift the pill off the edges
        // (WhatsApp-style floating bar) — content scrolls visibly around it.
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            var maxLabelWidth = 0.0;
            var maxLabelHeight = 0.0;
            for (final item in TreinoBottomBar._items) {
              final painter = TextPainter(
                text: TextSpan(text: item.label, style: labelStyle),
                maxLines: 1,
                textDirection: Directionality.of(context),
                textScaler: textScaler,
              )..layout();
              if (painter.width > maxLabelWidth) {
                maxLabelWidth = painter.width;
              }
              if (painter.height > maxLabelHeight) {
                maxLabelHeight = painter.height;
              }
              // Cada TextPainter retiene un ui.Paragraph nativo. Este loop
              // corre en cada pasada de layout (rotación, teclado, split view),
              // así que sin esto se acumulan hasta que pase el GC.
              painter.dispose();
            }

            final desiredHeight = 22 + 8 + maxLabelHeight + 20;
            final barHeight = desiredHeight > 72 ? desiredHeight : 72.0;

            // El ancho disponible repartido en partes IGUALES entre los cinco
            // destinos: es lo que mantiene la barra centrada y a INICIO en el
            // medio exacto de la pantalla.
            final tabWidth =
                constraints.maxWidth / TreinoBottomBar._items.length;
            final pillWidth = tabWidth - 2 * _kPillInset;

            // El label es lo último de la columna (ícono 22 + separación 4 +
            // label), así que su borde inferior es el punto que más se acerca
            // al redondeo del pill. Medir sólo contra el ancho del pill daba
            // por bueno un label que la curva igual recortaba.
            final pillHalfHeight = (barHeight - 2 * _kPillInset) / 2;
            final contentHeight = 22 + 4 + maxLabelHeight;
            final labelBottomFromPillCenter =
                (barHeight + contentHeight) / 2 - _kPillInset - pillHalfHeight;
            final cornerInset = _cornerInsetAt(
              dy: labelBottomFromPillCenter,
              halfHeight: pillHalfHeight,
              radius: _kPillRadius,
            );
            final showLabels = maxLabelWidth <= pillWidth - 2 * cornerInset;

            return DecoratedBox(
              // Shadow lives OUTSIDE the ClipRRect — inside it gets clipped.
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(36),
                boxShadow: [
                  BoxShadow(
                    color: palette.bg.withValues(alpha: 0.45),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(36),
                // NO BackdropFilter: blur re-samples on every frame content
                // moves behind the bar (extendBody) and dropped frames on
                // device even at sigma 8 (2026-06-11).
                child: Container(
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: palette.bgCard.withValues(alpha: 0.93),
                    borderRadius: BorderRadius.circular(36),
                    border: Border.all(color: palette.border),
                  ),
                  child: Stack(
                    children: [
                      AnimatedPositioned(
                        duration: AppMotion.slow,
                        curve: AppMotion.standard,
                        // Mismo inset que usa la cuenta de `showLabels` para
                        // decidir si el label entra. Si acá hubiera un número
                        // suelto, medir y pintar podrían separarse sin que
                        // nadie lo note.
                        left: tabWidth * widget.currentIndex + _kPillInset,
                        top: _kPillInset,
                        bottom: _kPillInset,
                        width: pillWidth,
                        child: _PillHighlight(palette: palette),
                      ),
                      Row(
                        children: List.generate(
                          TreinoBottomBar._items.length,
                          (i) {
                            final item = TreinoBottomBar._items[i];
                            final active = i == widget.currentIndex;
                            return Expanded(
                              child: Semantics(
                                button: true,
                                selected: active,
                                label: item.label,
                                excludeSemantics: true,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => widget.onTap(i),
                                  child: _TabContent(
                                    spec: item,
                                    active: active,
                                    palette: palette,
                                    badgeCount: widget._badgeCountFor(i),
                                    showLabel: showLabels,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TabSpec {
  const _TabSpec({
    required this.label,
    required this.icon,
    required this.iconActive,
  });

  final String label;
  final IconData icon;
  final IconData iconActive;
}

class _PillHighlight extends StatelessWidget {
  const _PillHighlight({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            palette.accent,
            Color.lerp(palette.accent, palette.highlight, 0.25)!,
          ],
        ),
        borderRadius: BorderRadius.circular(_kPillRadius),
        boxShadow: [
          BoxShadow(
            color: palette.accent.withValues(alpha: 0.35),
            blurRadius: 18,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
    );
  }
}

class _TabContent extends StatelessWidget {
  const _TabContent({
    required this.spec,
    required this.active,
    required this.palette,
    required this.showLabel,
    this.badgeCount = 0,
  });

  final _TabSpec spec;
  final bool active;
  final AppPalette palette;

  /// `false` cuando el label más largo no entra en el pill — pantalla muy
  /// chica o textScale grande. Se sacrifica el texto, NO el destino: el tab
  /// sigue ahí y el lector de pantalla lo sigue anunciando por el `Semantics`
  /// que lo envuelve.
  ///
  /// Achicar el texto con `FittedBox` se descartó: si el usuario agrandó la
  /// tipografía del sistema, devolvérsela a 10px le desarma justo lo que pidió.
  final bool showLabel;

  /// When > 0, renders a count badge over the tab icon.
  /// Values above 99 are shown as '99+'.
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final color = active ? palette.bg : palette.textMuted;
    return AnimatedDefaultTextStyle(
      duration: AppMotion.base,
      style: GoogleFonts.barlowCondensed(
        color: color,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
      // El padding horizontal es EXACTAMENTE el inset del pill, y sale de la
      // misma constante que usa el `AnimatedPositioned`. Sin esto la caja del
      // label mide `tabWidth` y el pill `tabWidth - 2*inset`: en el tab activo,
      // las letras que se pasan del pill se pintan en `palette.bg` (casi negro)
      // sobre el fondo de la barra y se leen como recortadas (ENTRENAR →
      // ENTRENR).
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _kPillInset),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedSwitcher(
                  duration: AppMotion.base,
                  switchInCurve: AppMotion.standard,
                  switchOutCurve: AppMotion.exit,
                  child: Icon(
                    active ? spec.iconActive : spec.icon,
                    key: ValueKey<bool>(active),
                    color: color,
                    size: 22,
                  ),
                ),
                if (badgeCount > 0)
                  Positioned(
                    top: -4,
                    right: -5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      constraints: const BoxConstraints(minWidth: 16),
                      decoration: BoxDecoration(
                        color: palette.accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        badgeCount > 99 ? '99+' : '$badgeCount',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.barlow(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          color: palette.bg,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            if (showLabel) ...[
              const SizedBox(height: 4),
              Text(
                spec.label,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
