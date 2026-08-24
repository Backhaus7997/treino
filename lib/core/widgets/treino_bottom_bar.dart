import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_motion.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/tokens/components/treino_button_tokens.dart';
import 'treino_glass_surface.dart';
import 'treino_icon.dart';

/// Medidas de layout de [TreinoBottomBar], resueltas a partir del ancho
/// disponible y del texto ya medido.
///
/// Existe como tipo aparte, y [resolveBarMetrics] como función pura, por una
/// razón concreta: **el álgebra de esta barra no se puede testear con un widget
/// test**. El proyecto usa `google_fonts` sin bundlear las tipografías (no hay
/// sección `fonts:` en el pubspec ni ningún `.ttf` en el repo), así que se
/// bajan por red en runtime; y `flutter_test` mockea HTTP devolviendo 400 a
/// todo. Resultado: en test Barlow Condensed NUNCA carga y todo se mide con una
/// fuente fallback bastante más ancha que la real. Cualquier aserción sobre
/// "¿entra ENTRENAR?" hecha en un widget test mide la fuente equivocada.
///
/// Tomando `maxLabelWidth` como ENTRADA, la decisión queda testeable con
/// aritmética exacta y sin fuentes de por medio.
@immutable
class TreinoBarMetrics {
  const TreinoBarMetrics({
    required this.tabWidth,
    required this.labelBoxWidth,
    required this.labelsFit,
    required this.barHeight,
  });

  /// Ancho de cada tab: el ancho disponible repartido en partes iguales.
  final double tabWidth;

  /// Ancho útil REAL para el label adentro del pill.
  ///
  /// No es simplemente el ancho del pill: el label se apoya abajo del ícono,
  /// justo donde el pill se curva y se angosta. Este valor ya tiene descontado
  /// lo que se come el redondeo a esa altura (ver [resolveBarMetrics]).
  final double labelBoxWidth;

  /// Si el label más largo entra en [labelBoxWidth].
  final bool labelsFit;

  /// Alto de la barra expandida.
  final double barHeight;
}

/// Cuánto se mete el redondeo hacia adentro, a `dy` de distancia del centro
/// vertical de una caja de media altura `halfHeight` y radio `radius`.
///
/// Mientras `dy` no pase de la parte recta del costado, el redondeo no come
/// nada. Después, el borde es un arco de circunferencia y se calcula así.
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

/// Resuelve las medidas de la barra. Ver [TreinoBarMetrics] para por qué esto
/// es una función pura y no lógica adentro del `build`.
TreinoBarMetrics resolveBarMetrics({
  required double availableWidth,
  required int itemCount,
  required double maxLabelWidth,
  required double maxLabelHeight,
}) {
  final tabWidth = availableWidth / itemCount;
  // Los dos insets con los que el pill se separa del borde del tab. Sale de
  // la constante y NO de un 16 escrito a mano: el `AnimatedPositioned` del
  // build usa la misma, así que lo que se mide acá es lo que se pinta allá.
  final pillWidth = tabWidth - 2 * _kPillInset;
  final desiredHeight = 22 + 8 + maxLabelHeight + 20;
  final barHeight = desiredHeight > TreinoBottomBar.minHeight
      ? desiredHeight
      : TreinoBottomBar.minHeight;

  // El label es lo último de la columna (ícono 22 + separación 4 + label), y su
  // borde inferior es el punto que más se acerca al redondeo del pill. Medir
  // solo contra el ancho del pill —su caja— daba por bueno un label que la
  // curva igual recortaba: la tinta de la primera y la última letra caía
  // AFUERA del pill, pintada en `palette.bg` sobre el fondo de la barra, y en
  // modo oscuro eso es negro sobre negro. Era el "ENTRENAR → ENTRENR".
  final pillHalfHeight = (barHeight - 2 * _kPillInset) / 2;
  final contentHeight = 22 + 4 + maxLabelHeight;
  final labelBottomFromPillCenter =
      (barHeight + contentHeight) / 2 - _kPillInset - pillHalfHeight;
  final cornerInset = _cornerInsetAt(
    dy: labelBottomFromPillCenter,
    halfHeight: pillHalfHeight,
    radius: _kPillRadius,
  );
  final labelBoxWidth = pillWidth - 2 * cornerInset;

  return TreinoBarMetrics(
    tabWidth: tabWidth,
    labelBoxWidth: labelBoxWidth,
    labelsFit: maxLabelWidth <= labelBoxWidth,
    barHeight: barHeight,
  );
}

/// Cuánto se separa el pill del borde de su tab, en los cuatro lados.
///
/// Era 8, y esos 2px de más por lado eran 4px menos de caja para el label —
/// justo los que faltaban. Medido con la fuente real (Barlow Condensed 10/w700,
/// letterSpacing 0.8), "ENTRENAR" ocupa 44,36pt; en un Android de 360dp, el
/// ancho más común del parque, la caja del label daba 41,41 y la barra se
/// quedaba en íconos PARA SIEMPRE. Con 6 la caja pasa a 47,72 y entra.
const double _kPillInset = 6;

/// Margen lateral con el que la barra se despega de los bordes de la pantalla.
/// Es la separación que le da el aire de "pill flotante" estilo WhatsApp.
const double _kSideMarginIdeal = 20;

/// Margen lateral al que la barra recurre SOLO si con [_kSideMarginIdeal] los
/// labels no entrarían. Ver [resolveBarLayout].
const double _kSideMarginTight = 12;

/// Margen inferior MÍNIMO con el que la barra se despega del borde de abajo.
///
/// Antes el único aire de abajo era el safe area del dispositivo, y en Android
/// eso no alcanza: con navegación por gestos el inset es chico, y en los
/// equipos que dejan esconder la barra de gestos es directamente 0. La barra
/// quedaba apoyada contra el borde físico de la pantalla — dejaba de leerse
/// como el pill flotante que pide el diseño y pasaba a leerse como una barra
/// anclada, con los labels casi tocando el borde.
///
/// Se toma el MAYOR entre este valor y el safe area, NO la suma: donde el
/// sistema ya reserva espacio (home indicator de iOS, botones de Android) ese
/// espacio ES el margen, y sumarle otros 16 dejaría la barra flotando de más.
///
/// Ninguna pantalla tiene que sumarlo a su padding inferior: el margen forma
/// parte del alto de la barra, y el `Scaffold` del shell (`extendBody: true`)
/// publica ese alto entero en el `MediaQuery.padding.bottom` del body, que es
/// de donde los scrollables ya lo leen.
const double _kBottomMarginMin = 16;

/// Margen lateral + medidas de la barra, resueltos juntos.
///
/// Van juntos porque se determinan entre sí: cuánto margen se puede dar
/// depende de si los labels entran, y si entran depende del margen.
@immutable
class TreinoBarLayout {
  const TreinoBarLayout({required this.sideMargin, required this.metrics});

  /// Separación lateral de la barra respecto de los bordes de la pantalla.
  final double sideMargin;

  /// Medidas resueltas con [sideMargin] ya descontado.
  final TreinoBarMetrics metrics;
}

/// Elige el margen lateral más generoso con el que los labels TODAVÍA entren.
///
/// Primero prueba [_kSideMarginIdeal], que es el que respeta el diseño. Si con
/// ese los labels no entran, aprieta a [_kSideMarginTight] y recalcula: ceder
/// 8pt de aire a cada lado es mucho más barato que perder los cinco labels de
/// la barra de navegación. Si ni apretando entran, vuelve al margen ideal y
/// deja que la barra se quede con los íconos — a esa altura el problema es el
/// textScale del usuario, y achicar el margen ya no lo arregla.
///
/// Deliberadamente NO mira `collapsed`: si el margen dependiera del estado
/// colapsado, la barra cambiaría de ANCHO al scrollear, no solo de alto.
TreinoBarLayout resolveBarLayout({
  required double totalWidth,
  required int itemCount,
  required double maxLabelWidth,
  required double maxLabelHeight,
}) {
  TreinoBarMetrics metricsFor(double margin) => resolveBarMetrics(
        availableWidth: totalWidth - 2 * margin,
        itemCount: itemCount,
        maxLabelWidth: maxLabelWidth,
        maxLabelHeight: maxLabelHeight,
      );

  final ideal = metricsFor(_kSideMarginIdeal);
  if (ideal.labelsFit) {
    return TreinoBarLayout(sideMargin: _kSideMarginIdeal, metrics: ideal);
  }

  final tight = metricsFor(_kSideMarginTight);
  if (tight.labelsFit) {
    return TreinoBarLayout(sideMargin: _kSideMarginTight, metrics: tight);
  }

  return TreinoBarLayout(sideMargin: _kSideMarginIdeal, metrics: ideal);
}

/// Redondeo del pill activo.
///
/// Era 28, que sobre el pill de entonces lo volvía un círculo perfecto — y a
/// la altura del label la curva entraba 7,4px por lado cuando el label solo
/// tenía 6px de margen, así que lo recortaba. Con 20, y con el pill de 60 de
/// alto que deja [_kPillInset], la curva entra 2,14px por lado: la palabra
/// entra entera y el pill se sigue viendo bien redondeado.
const double _kPillRadius = 20;

/// Bottom bar de TREINO: pill flotante de vidrio (fill translúcido + reflejo
/// especular, SIN blur — ver [TreinoGlassSurface]), pill de gradient que se
/// desliza al tab activo, íconos `TreinoIcon` + labels Barlow Condensed.
///
/// **Los cinco destinos se ven SIEMPRE.** Cuando los labels no entran a lo
/// ancho —pantalla chica, o el usuario agrandó la tipografía del sistema— la
/// barra se queda con los íconos, que es el mismo estado compacto que produce
/// [collapsed] y no un tercer modo. Antes había acá un camino aparte que la
/// volvía una tira scrolleable horizontal: en un iPhone 17 Pro a textScale 1.0
/// eso dejaba PERFIL fuera de pantalla. Una barra de navegación que hay que
/// scrollear para llegar a una pestaña no es una barra de navegación, y
/// `docs/design-decisions.md` pide explícitamente que la barra esté siempre
/// visible.
///
/// Achicar el texto con `FittedBox` se descartó: si el usuario agrandó la
/// tipografía del sistema, devolvérsela a 10px le desarma justo lo que pidió.
/// Se sacrifica el label —que el lector de pantalla sigue anunciando por el
/// `Semantics` de cada tab— y no la legibilidad ni el acceso a los destinos.
class TreinoBottomBar extends StatelessWidget {
  const TreinoBottomBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.coachUnreadCount = 0,
    this.feedUnreadCount = 0,
    this.collapsed = false,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  /// Cuando es `true` la barra se compacta: pierde alto y esconde los labels,
  /// dejando solo los íconos. La dispara el shell al detectar scroll hacia
  /// abajo en cualquier pantalla (ver `_ShellScaffold` en `app/router.dart`).
  ///
  /// **No es el único disparador del estado compacto**: la barra también se
  /// queda con los íconos cuando los labels no entran a lo ancho (ver
  /// [resolveBarMetrics]). Este flag es "el usuario está leyendo"; el otro es
  /// "el texto no entra". Cualquiera de los dos alcanza.
  ///
  /// El `minHeight` que usan los scrollables para su padding inferior NO
  /// cambia, así que el contenido no salta cuando la barra se achica. El área
  /// tapeable de cada tab SÍ se achica con la barra (de [minHeight] a
  /// [collapsedHeight]), porque el `GestureDetector` vive adentro de la caja
  /// animada; a 52px sigue holgadamente por encima del mínimo de 44 de la HIG.
  final bool collapsed;

  /// Count of unread chats with the athlete's coach — shown as a badge on
  /// the COACH tab (index 3). Pass 0 (default) to hide the badge.
  final int coachUnreadCount;

  /// Count of unread chats with friends (user↔user, social) — shown as a
  /// badge on the FEED tab (index 1) so the user sees the alert without
  /// having to open the tab first. Pass 0 (default) to hide the badge.
  final int feedUnreadCount;

  /// Altura mínima de la barra, sin contar el safe area.
  ///
  /// Las pantallas del shell corren con `extendBody: true`, así que su
  /// contenido pasa POR DEBAJO de la barra: cualquier lista scrolleable tiene
  /// que sumar esto (más `MediaQuery.paddingOf(context).bottom`) a su padding
  /// inferior, o el último item queda tapado y el scroll rebota antes de
  /// dejarlo ver.
  ///
  /// Es el piso, no la altura exacta: con textScale grande la barra crece
  /// (`22 + 8 + altoDelLabel + 20`) y el padding queda algo justo, pero el
  /// contenido sigue siendo alcanzable.
  static const double minHeight = 72;

  /// Alto de la barra compactada ([collapsed] en `true`): solo íconos.
  ///
  /// Deliberadamente NO afecta a [minHeight]: si el padding inferior de los
  /// scrollables siguiera al alto real de la barra, colapsar la barra
  /// reacomodaría toda la lista y el scroll saltaría bajo el dedo. El padding
  /// se queda en el caso expandido (el peor caso) y punto.
  static const double collapsedHeight = 52;

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

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final labelStyle = GoogleFonts.barlowCondensed(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    );

    // El inset horizontal del dispositivo se SIMETRIZA antes de aplicarlo.
    //
    // Los insets izquierdo y derecho NO son iguales en landscape sobre un
    // iPhone con notch: 44 del lado del recorte y 0 del otro. Aplicados tal
    // como vienen, el margen lateral que resuelve `resolveBarLayout` —que sí
    // es simétrico— cae adentro de una caja ya corrida, y la barra entera
    // termina desplazada medio inset (22pt) hacia el lado sin notch. Es un
    // pill flotante centrado: que se corra del centro se ve.
    //
    // Tomando el mayor de los dos para ambos lados, la barra sigue esquivando
    // el recorte (nunca se mete debajo) y vuelve a quedar centrada en
    // pantalla. En portrait los dos insets son 0 y esto no hace absolutamente
    // nada, que es por qué NO puede ser la causa de un reporte en portrait.
    final devicePadding = MediaQuery.paddingOf(context);
    final horizontalInset = math.max(devicePadding.left, devicePadding.right);

    // Acá abajo iba un `SafeArea(bottom: true)`, y por eso la barra terminaba
    // pegada al borde en Android: el safe area es TODO el margen que la barra
    // tenía, y con navegación por gestos ese número es chico o cero. Ahora el
    // margen es propio de la barra y el safe area es apenas su piso — ver
    // [_kBottomMarginMin].
    return Padding(
      padding: EdgeInsets.only(
        left: horizontalInset,
        right: horizontalInset,
        bottom: math.max(devicePadding.bottom, _kBottomMarginMin),
      ),
      // El LayoutBuilder va AFUERA del Padding interno a propósito: el margen
      // lateral ya no es una constante, lo elige `resolveBarLayout` a partir
      // del ancho total de la pantalla. Adentro de ese Padding sólo se ve el
      // ancho ya recortado, que es justamente el dato que hay que decidir.
      child: LayoutBuilder(
        builder: (context, constraints) {
          var maxLabelWidth = 0.0;
          var maxLabelHeight = 0.0;
          for (final item in _items) {
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

          final layout = resolveBarLayout(
            totalWidth: constraints.maxWidth,
            itemCount: _items.length,
            maxLabelWidth: maxLabelWidth,
            maxLabelHeight: maxLabelHeight,
          );
          final metrics = layout.metrics;
          final barHeight = metrics.barHeight;
          final expanded = !collapsed && metrics.labelsFit;

          // Una sola animación gobierna alto Y labels. Si fueran dos
          // (AnimatedContainer + AnimatedOpacity) podrían desincronizarse
          // un frame y el contenido desbordaría la caja mientras se achica.
          return Padding(
            padding: EdgeInsets.fromLTRB(
              layout.sideMargin,
              8,
              layout.sideMargin,
              0,
            ),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: expanded ? 1 : 0),
              duration: AppMotion.base,
              curve: AppMotion.standard,
              builder: (context, expansion, _) {
                return DecoratedBox(
                  // Shadow lives OUTSIDE the ClipRRect — inside it gets
                  // clipped.
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
                    child: SizedBox(
                      height: lerpDouble(collapsedHeight, barHeight, expansion),
                      child: TreinoGlassSurface(
                        borderRadius: BorderRadius.circular(36),
                        child: LayoutBuilder(
                          builder: (context, innerConstraints) {
                            final tabWidth =
                                innerConstraints.maxWidth / _items.length;
                            return Stack(
                              children: [
                                AnimatedPositioned(
                                  duration: AppMotion.slow,
                                  curve: AppMotion.standard,
                                  // Mismo inset que usa `resolveBarMetrics`
                                  // para decidir si el label entra. Si acá
                                  // hubiera un número suelto, medir y pintar
                                  // podrían separarse sin que nadie lo note.
                                  left: tabWidth * currentIndex + _kPillInset,
                                  top: _kPillInset,
                                  bottom: _kPillInset,
                                  width: tabWidth - 2 * _kPillInset,
                                  child: _PillHighlight(palette: palette),
                                ),
                                Row(
                                  children: List.generate(_items.length, (i) {
                                    final item = _items[i];
                                    final active = i == currentIndex;
                                    return Expanded(
                                      child: Semantics(
                                        button: true,
                                        selected: active,
                                        label: item.label,
                                        excludeSemantics: true,
                                        child: GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () => onTap(i),
                                          child: _TabContent(
                                            spec: item,
                                            active: active,
                                            palette: palette,
                                            badgeCount: _badgeCountFor(i),
                                            expansion: expansion,
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  int _badgeCountFor(int index) => switch (index) {
        1 => feedUnreadCount,
        3 => coachUnreadCount,
        _ => 0,
      };
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
    required this.expansion,
    this.badgeCount = 0,
  });

  final _TabSpec spec;
  final bool active;
  final AppPalette palette;

  /// `1` = barra expandida, `0` = compactada. Gobierna el label: se desvanece
  /// y colapsa su alto al mismo ritmo con el que se achica la barra, así que
  /// el contenido nunca desborda la caja durante la transición.
  final double expansion;

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
      // misma constante que usan el `AnimatedPositioned` y `resolveBarMetrics`.
      // Sin esto la caja del label mide `tabWidth` y el pill `tabWidth - 2*
      // inset`: en el tab activo, las letras que se pasan del pill se pintan en
      // `palette.bg` (casi negro) sobre el fondo oscuro de la barra y se leen
      // como recortadas (ENTRENAR → ENTRENR). Y si fuera un número suelto más
      // grande que el inset, le comería al label ancho que el pill sí le da.
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
                          color: TreinoButtonTokens.foreground(context),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            ClipRect(
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: expansion,
                child: Opacity(
                  opacity: expansion,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      spec.label,
                      maxLines: 1,
                      softWrap: false,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
