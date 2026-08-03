import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_motion.dart';
import '../../app/theme/app_palette.dart';
import 'treino_glass_surface.dart';
import 'treino_icon.dart';

/// Bottom bar de TREINO: pill flotante de vidrio (fill translúcido + reflejo
/// especular, SIN blur — ver [TreinoGlassSurface]), pill de gradient que se
/// desliza al tab activo, íconos `TreinoIcon` + labels Barlow Condensed.
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
  /// Es presentación pura: los tabs siguen siendo tapeables con el mismo
  /// tamaño de target y el `minHeight` que usan los scrollables para su padding
  /// inferior NO cambia — el contenido no salta cuando la barra se achica.
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
            }

            final equalTabContentWidth =
                constraints.maxWidth / _items.length - 20;
            final useScrollableTabs = maxLabelWidth > equalTabContentWidth;
            final desiredHeight = 22 + 8 + maxLabelHeight + 20;
            final barHeight =
                desiredHeight > minHeight ? desiredHeight : minHeight;

            // Una sola animación gobierna alto Y labels. Si fueran dos
            // (AnimatedContainer + AnimatedOpacity) podrían desincronizarse
            // un frame y el contenido desbordaría la caja mientras se achica.
            return TweenAnimationBuilder<double>(
              tween: Tween<double>(end: collapsed ? 0 : 1),
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
                        child: useScrollableTabs
                            ? SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                reverse: currentIndex >= 3,
                                child: Row(
                                  children: List.generate(_items.length, (i) {
                                    return SizedBox(
                                      width: maxLabelWidth + 40,
                                      child: _ScrollableTab(
                                        spec: _items[i],
                                        active: i == currentIndex,
                                        palette: palette,
                                        badgeCount: _badgeCountFor(i),
                                        expansion: expansion,
                                        onTap: () => onTap(i),
                                      ),
                                    );
                                  }),
                                ),
                              )
                            : LayoutBuilder(
                                builder: (context, innerConstraints) {
                                  final tabWidth =
                                      innerConstraints.maxWidth / _items.length;
                                  return Stack(
                                    children: [
                                      AnimatedPositioned(
                                        duration: AppMotion.slow,
                                        curve: AppMotion.standard,
                                        left: tabWidth * currentIndex + 8,
                                        top: 8,
                                        bottom: 8,
                                        width: tabWidth - 16,
                                        child: _PillHighlight(palette: palette),
                                      ),
                                      Row(
                                        children:
                                            List.generate(_items.length, (i) {
                                          final item = _items[i];
                                          final active = i == currentIndex;
                                          return Expanded(
                                            child: Semantics(
                                              button: true,
                                              selected: active,
                                              label: item.label,
                                              excludeSemantics: true,
                                              child: GestureDetector(
                                                behavior:
                                                    HitTestBehavior.opaque,
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
            );
          },
        ),
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
        borderRadius: BorderRadius.circular(28),
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

class _ScrollableTab extends StatelessWidget {
  const _ScrollableTab({
    required this.spec,
    required this.active,
    required this.palette,
    required this.badgeCount,
    required this.expansion,
    required this.onTap,
  });

  final _TabSpec spec;
  final bool active;
  final AppPalette palette;
  final int badgeCount;

  /// Ver [_TabContent.expansion].
  final double expansion;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: active,
      label: spec.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (active) _PillHighlight(palette: palette),
              _TabContent(
                spec: spec,
                active: active,
                palette: palette,
                badgeCount: badgeCount,
                expansion: expansion,
              ),
            ],
          ),
        ),
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
      // Horizontal padding matches the pill's 8px margin on each side of the
      // tab (see AnimatedPositioned: left = tabWidth*i + 8, width = tabWidth
      // - 16). Without this, the label's box is `tabWidth` wide but the pill
      // is `tabWidth - 16` — so on the active tab, characters that extend
      // past the pill are rendered in `palette.bg` (near-black) over the
      // dark navbar bg and read as clipped (ENTRENAR → ENTRENR). Keeping the
      // label inside the pill box guarantees readable contrast everywhere.
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
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
