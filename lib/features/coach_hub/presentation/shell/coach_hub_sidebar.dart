import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/domain/subscription_tier.dart';
import 'package:treino/features/coach_hub/application/sidebar_collapsed_provider.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/plan_upsell_banner.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/profile/application/user_providers.dart';

import 'sidebar_item.dart';
import 'sidebar_registry.dart';
import '../../../../core/widgets/treino_logo.dart';

/// Sidebar del Coach Hub web (REQ-SH-001..006, ADR-SH-004).
///
/// Renderiza `sidebarRegistry` agrupado por [SidebarGroup] con header por
/// grupo (oculto al colapsar). El toggle vive junto al wordmark y el perfil
/// es el único acceso a la cuenta. Ancho animado
/// 240↔72 px (`CoachHubLayoutTokens`). El estado colapsado viene de
/// `sidebarCollapsedProvider`, gateado por `sharedPreferencesProvider`
/// (optimistic-expanded mientras resuelve).
class CoachHubSidebar extends ConsumerWidget {
  const CoachHubSidebar({
    super.key,
    this.collapsedOverride,
    this.itemsOverride,
  });

  /// Si es no-nulo, fuerza el estado colapsado e ignora
  /// `sidebarCollapsedProvider`. El `CoachHubScaffold` lo pasa en `true` en
  /// viewport compact (ADR-CHW-004) sin escribir el provider, así el valor
  /// guardado del usuario se preserva al volver a desktop.
  final bool? collapsedOverride;

  /// Si es no-nulo, reemplaza `sidebarRegistry` — solo para tests (eg.
  /// verificar el render de badges sin depender del wiring real de W1+).
  final List<SidebarItem>? itemsOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final bool stored = ref.watch(sharedPreferencesProvider).maybeWhen(
          data: (_) => ref.watch(sidebarCollapsedProvider),
          orElse: () => false,
        );
    final collapsed = collapsedOverride ?? stored;
    // El toggle vive DENTRO del footer (REQ-SH-006) — deshabilitado cuando el
    // estado está forzado (viewport compact, donde `collapsedOverride` es
    // no-nulo) o cuando prefs todavía no resolvió.
    final canToggle = collapsedOverride == null &&
        ref.watch(sharedPreferencesProvider).hasValue;
    final location = GoRouterState.of(context).uri.toString();
    final items = itemsOverride ?? sidebarRegistry;

    final groups = <SidebarGroup, List<SidebarItem>>{};
    for (final group in SidebarGroup.values) {
      if (group == SidebarGroup.ajustes) continue;
      final items0 = items.where((item) => item.group == group).toList();
      if (items0.isNotEmpty) groups[group] = items0;
    }
    final groupEntries = groups.entries.toList();
    var staggerIndex = 0;

    return AnimatedContainer(
      key: const Key('coach_hub_sidebar_container'),
      width: collapsed
          ? CoachHubLayoutTokens.sidebarCollapsedWidth
          : CoachHubLayoutTokens.sidebarExpandedWidth,
      duration: AppMotionTokens.resolve(context, AppMotionTokens.contentEnter),
      curve: AppMotionTokens.reposition,
      // Clip durante la animación de ancho: al colapsar/expandir (o al resize
      // entre desktop y compact) el ancho anima pero el layout de las filas
      // cambia al instante, así que sin clip las filas desbordarían unos px.
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: palette.bg,
        border: Border(right: BorderSide(color: palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SidebarHeader(
            collapsed: collapsed,
            canToggle: canToggle,
            onToggle: () =>
                ref.read(sidebarCollapsedProvider.notifier).toggle(),
          ),
          Container(height: 1, color: palette.border),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Todos los hijos van con `key`. NO es cosmética: los
                  // `_GroupHeader` se van de la lista al colapsar, y sin keys
                  // Flutter re-matchea por índice, así que cada fila se monta
                  // DE NUEVO en cada toggle. Un widget recién montado no tiene
                  // de dónde interpolar: sus animaciones implícitas nacen en el
                  // valor final. Es decir que el `AnimatedPositioned` del label
                  // saltaba, y parecía un bug de la animación cuando el bug
                  // estaba acá, dos archivos más arriba en el árbol.
                  for (var i = 0; i < groupEntries.length; i++) ...[
                    if (i > 0)
                      Container(
                        key: ValueKey('sep_${groupEntries[i].key.label}'),
                        height: 1,
                        color: palette.border,
                      ),
                    if (!collapsed)
                      _GroupHeader(
                        key: ValueKey('hdr_${groupEntries[i].key.label}'),
                        label: groupEntries[i].key.label,
                      ),
                    for (final item in groupEntries[i].value)
                      _SidebarItemRow(
                        key: ValueKey(item.route),
                        item: item,
                        collapsed: collapsed,
                        active: _isActive(location, item.route),
                        delay: AppMotion.stagger(staggerIndex++),
                        badgeCount: item.badgeProvider == null
                            ? null
                            : ref.watch(item.badgeProvider!),
                      ),
                  ],
                ],
              ),
            ),
          ),
          _SidebarFooter(
            collapsed: collapsed,
          ),
        ],
      ),
    );
  }

  bool _isActive(String location, String route) =>
      location == route || location.startsWith('$route/');
}

/// Header del sidebar: logotipo TREINO (REQ-SH-002). Oculto (sin texto)
/// cuando el sidebar está colapsado.
class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({
    required this.collapsed,
    required this.canToggle,
    required this.onToggle,
  });

  final bool collapsed;
  final bool canToggle;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(
        horizontal: collapsed ? 0 : AppSpacing.s14,
      ),
      // El wordmark, no la palabra "TREINO" tipeada en Barlow Condensed.
      //
      // Eran dos marcas distintas: la app mobile abre con el logotipo real y
      // el Coach Hub lo reescribía con la fuente del sistema de diseño. Un PF
      // que entra desde el teléfono a la web veía otra marca.
      //
      // `TreinoLogo` es el mismo widget que usan welcome, splash, login y
      // register, y renderiza `assets/logo/treino_logo.svg`.
      child: collapsed
          ? _ToggleButton(
              collapsed: collapsed,
              canToggle: canToggle,
              onToggle: onToggle,
            )
          : Row(
              children: [
                // En accent, no en el blanco por defecto: es el verde con el
                // que la marca aparece en el resto de la app.
                TreinoLogo(size: 26, color: AppPalette.of(context).accent),
                const Spacer(),
                _ToggleButton(
                  collapsed: collapsed,
                  canToggle: canToggle,
                  onToggle: onToggle,
                ),
              ],
            ),
    );
  }
}

/// Header de grupo (GESTIÓN, RECURSOS, …). Solo visible expandido — ya NO
/// aloja el toggle (REQ-SH-004/006: el toggle se mudó al footer).
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s14,
        AppSpacing.s18,
        AppSpacing.s14,
        AppSpacing.s8,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: AppFonts.barlowCondensed,
          color: palette.textMuted,
          fontSize: 12,
          fontWeight: AppFonts.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

/// Fila clickeable de un [SidebarItem] — píldora animada (ADR-SH-004).
///
/// **Variante activa (REQ-SH-003a)**: píldora completa — el mockup
/// (`docs/web-trainer/screens/sidebar/sidebar.png`) muestra fondo relleno
/// (`bgCard`) en todo el ancho de la fila, SIN barra lateral. Activo: fondo
/// `bgCard` + label/ícono en `accent` semibold. Hover (vía
/// [TreinoInteractiveState]): fondo `accent` al 8% de opacidad. El cambio de
/// fondo anima con [AppMotionTokens.cardStateChange] (interrumpible,
/// respeta reduce-motion vía `AppMotionTokens.resolve`).
class _SidebarItemRow extends StatelessWidget {
  const _SidebarItemRow({
    super.key,
    required this.item,
    required this.collapsed,
    required this.active,
    required this.delay,
    required this.badgeCount,
  });

  final SidebarItem item;
  final bool collapsed;
  final bool active;
  final Duration delay;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final tokens = CoachHubSidebarItemTokens.of(context);
    final fg = active ? tokens.activeForeground : tokens.inactiveForeground;
    final hasBadge = badgeCount != null && badgeCount! > 0;

    final row = TreinoInteractiveState(
      onTap: () => context.go(item.route),
      builder: (ctx, states) {
        final background = active
            ? tokens.activeBackground
            : states.hovered
                ? tokens.hoverBackground
                : Colors.transparent;

        return AnimatedContainer(
          // `tapFeedback` (120ms) y no `cardStateChange` (180): esto es el
          // hover de una LISTA que se barre con el mouse, no el cambio de
          // estado de una card suelta.
          //
          // A 180ms, al pasar de un item al siguiente el fondo del anterior
          // todavía se está apagando cuando el nuevo ya se encendió, y durante
          // ese solapamiento se ven DOS filas resaltadas. No es que el hover
          // esté en dos lados: es que la salida dura más que el gesto.
          //
          // Barrer una lista de 11 items es de las cosas que más veces por día
          // hace el PF, y a esa frecuencia lo que se quiere es respuesta, no
          // suavidad.
          duration: AppMotionTokens.resolve(ctx, AppMotionTokens.tapFeedback),
          curve: AppMotionTokens.enter,
          height: CoachHubLayoutTokens.sidebarItemHeight,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          padding: const EdgeInsets.symmetric(
            horizontal: CoachHubSidebarItemTokens.paddingH,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius:
                BorderRadius.circular(CoachHubSidebarItemTokens.borderRadius),
          ),
          // `Stack` y no `Row`: el label tiene que quedar MONTADO al colapsar
          // para poder desvanecerse —sin widget no hay nada que animar— pero
          // sin que su ancho intrínseco participe del layout de la fila.
          //
          // Un intento anterior lo hizo con `Row` + `AnimatedAlign(widthFactor)`
          // y voló: adentro de un `Row`, un `Text` sin ancho acotado pide
          // infinito y tira excepción de layout. Acá el `Positioned` con `left`
          // Y `right` deja el label completamente acotado, y el `AnimatedAlign`
          // sólo mueve un ícono de 20px, que es tamaño fijo.
          child: Stack(
            alignment: Alignment.centerLeft,
            // El label sale de su caja a propósito mientras se desliza: quien
            // lo recorta es el `clipBehavior` del `AnimatedContainer` del
            // sidebar, contra el borde que se está moviendo. Si clipeara acá
            // se cortaría contra la fila —que mide 28px colapsada— y quedaría
            // un muñón de texto visible en vez de nada.
            clipBehavior: Clip.none,
            children: [
              // El label se apaga y se enciende; NO se mueve. Moverlo además
              // de fundirlo compite con el ancho del sidebar, que ya se está
              // desplazando abajo suyo.
              // El label NO se desmonta al colapsar: se DESLIZA hacia
              // afuera, empujado por el mismo borde que ya animaba sus
              // 240→72px. Sale de cuadro justo cuando el sidebar termina de
              // cerrarse, así que el contenido acompaña al contenedor en vez
              // de desaparecer en el primer frame mientras el ancho sigue
              // viajando —que era exactamente el salto que se veía.
              //
              // Su ancho es FIJO (`_labelWidth`) y no `right: 0`. Atado al
              // borde derecho se iría angostando hasta ~16px y el texto
              // colapsaría a puntos suspensivos antes de irse: el ojo lee eso
              // como el label rompiéndose, no como el panel cerrándose.
              //
              // Va a `sidebarCollapsedWidth` y no a un valor menor porque ese
              // es el punto exacto donde el clip lo tapa entero.
              AnimatedPositioned(
                left: collapsed
                    ? CoachHubLayoutTokens.sidebarCollapsedWidth
                    : _kIconSize + 12,
                width: _labelWidth,
                // SIN `top`/`bottom` a propósito. Con verticales el label se
                // estira a los 48px de la fila y lo centra el `Row`; sin
                // ellas se dimensiona por su altura intrínseca y lo centra el
                // `Stack`. El centro es el mismo en teoría y el redondeo no:
                // ponerlas corrió cada label 1px y movió 374px en TODOS los
                // goldens del gate a la vez.
                duration:
                    AppMotionTokens.resolve(ctx, AppMotionTokens.contentEnter),
                curve: AppMotionTokens.reposition,
                child: IgnorePointer(
                  // Fuera de cuadro el texto sigue en el árbol: que no reciba
                  // el mouse. Colapsado, quien nombra al item es el Tooltip.
                  ignoring: collapsed,
                  child: ExcludeSemantics(
                    excluding: collapsed,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.label,
                            overflow: TextOverflow.ellipsis,
                            softWrap: false,
                            style: TextStyle(
                              fontFamily: AppFonts.barlow,
                              color: fg,
                              fontSize: AppTextSize.body,
                              fontWeight:
                                  active ? AppFonts.w600 : AppFonts.w400,
                            ),
                          ),
                        ),
                        if (hasBadge) _Badge(count: badgeCount!),
                      ],
                    ),
                  ),
                ),
              ),
              // El ícono viaja de la izquierda al centro con el mismo escalón
              // que el ancho del sidebar, así las dos cosas cuentan lo mismo.
              AnimatedAlign(
                alignment: collapsed ? Alignment.center : Alignment.centerLeft,
                duration: AppMotionTokens.resolve(
                  ctx,
                  AppMotionTokens.contentEnter,
                ),
                curve: AppMotionTokens.enter,
                child: _ItemIcon(
                  icon: item.iconBuilder(),
                  color: fg,
                  // Colapsado el número no entra: el badge se degrada a un
                  // punto pegado al ícono. Expandido el punto sobra — el número
                  // va al final de la fila, que es donde se lee mejor.
                  dot: collapsed && hasBadge,
                ),
              ),
            ],
          ),
        );
      },
    );

    // Colapsado el label desaparece del render, así que el ítem queda sin
    // nombre para el mouse Y para un lector de pantalla. El tooltip cubre lo
    // primero; el `Semantics(label:)` explícito, lo segundo —
    // `TreinoInteractiveState` marca `button: true` pero no tiene con qué
    // nombrarlo.
    // `MergeSemantics` y no un `Semantics` suelto: `TreinoInteractiveState` ya
    // aporta su propio `Semantics(button: true)` sin label, y dos anotaciones
    // encadenadas no se combinan solas — el label quedaba en un nodo aparte
    // que el lector nunca ata al botón. Merged, el ítem se anuncia como una
    // sola cosa: «Pagos, 3, botón».
    // LA FORMA DEL ÁRBOL NO CAMBIA CON `collapsed`. Lo que cambia son sus
    // propiedades.
    //
    // Antes esto era `collapsed ? MergeSemantics(...Tooltip(row)) : row`, o sea
    // dos árboles distintos en la misma posición. Flutter no los reconcilia:
    // destruye el subárbol y monta uno nuevo, y con él el `State` del
    // `AnimatedPositioned` del label — que entonces nace ya en su valor final y
    // NUNCA anima. Es la misma trampa que las keys del `Column` de arriba
    // resuelven un nivel más afuera: para que una animación implícita sirva,
    // su elemento tiene que SOBREVIVIR al rebuild. Las dos condiciones son
    // necesarias; con una sola, el label sigue saltando.
    //
    // Ahora los wrappers están siempre. El `Tooltip` con mensaje vacío no se
    // muestra —expandido el label ya está en pantalla y un tooltip sería
    // redundante— y el `Semantics` lleva el mismo label en los dos estados,
    // que es correcto en ambos.
    final labelled = MergeSemantics(
      child: Semantics(
        label: hasBadge ? '${item.label}, $badgeCount' : item.label,
        child: Tooltip(
          message: collapsed
              ? (hasBadge ? '${item.label} ($badgeCount)' : item.label)
              : '',
          // El sidebar colapsado tiene 23 íconos y el tooltip es la única
          // forma de leerlos: 200 ms alcanzan para no dispararlo mientras
          // el mouse cruza la columna, y se sienten instantáneos al frenar.
          waitDuration: const Duration(milliseconds: 200),
          // El label ya lo pone el `Semantics` de arriba; sin esto el
          // lector lo diría dos veces.
          excludeFromSemantics: true,
          child: row,
        ),
      ),
    );

    return TreinoFadeSlideIn(
        delay: delay, distance: AppMotion.slideSm, child: labelled);
  }
}

/// Lado del ícono de un item del sidebar.
///
/// Vive como constante porque el `Positioned` del label lo necesita para saber
/// desde dónde arrancar: si el ícono cambia de tamaño y este número no, el
/// label se le monta encima.
const double _kIconSize = 20;

/// Ancho del label de un item con el sidebar expandido.
///
/// Se calcula una vez y queda fijo: 240 de sidebar, menos el margen de la fila
/// (8 por lado), menos su padding (14 por lado), menos el hueco del ícono
/// (20 + 12). Ese resto es lo que el texto ocupa cuando está en su lugar, y es
/// lo que conserva mientras se desliza hacia afuera.
const double _labelWidth = CoachHubLayoutTokens.sidebarExpandedWidth -
    _kSidebarBorderWidth -
    8 * 2 -
    CoachHubSidebarItemTokens.paddingH * 2 -
    (_kIconSize + 12);

/// Ancho del borde derecho del sidebar. Entra en la cuenta de `_labelWidth`
/// porque el `Border` del `BoxDecoration` se come ese píxel del content box.
///
/// Olvidarlo dejaba el label 1px más ancho de lo que era con `right: 0`, lo que
/// corría dónde ellipsiza cada texto: 374px de diferencia en los cuatro
/// goldens del gate visual, por un píxel de aritmética.
const double _kSidebarBorderWidth = 1;

/// Ícono del ítem, con el punto de badge opcional para el estado colapsado.
///
/// El punto no anima: aparecer y desaparecer acá es un cambio de estado que se
/// lee solo, y el sidebar es de las superficies que el PF más mira por día.
class _ItemIcon extends StatelessWidget {
  const _ItemIcon({
    required this.icon,
    required this.color,
    required this.dot,
  });

  final IconData icon;
  final Color color;
  final bool dot;

  /// Diámetro del punto — la mitad del badge numérico (`TreinoBadgeTokens.size`).
  static const double _dotSize = 8;

  @override
  Widget build(BuildContext context) {
    final glyph = Icon(icon, size: _kIconSize, color: color);
    if (!dot) return glyph;

    final palette = AppPalette.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        glyph,
        Positioned(
          top: -1,
          right: -2,
          child: Container(
            width: _dotSize,
            height: _dotSize,
            decoration: BoxDecoration(
              color: TreinoBadgeTokens.of(context).background,
              shape: BoxShape.circle,
              // Anillo del color del sidebar: sin él el punto se pega al glifo
              // y los dos se leen como una sola forma sucia.
              border: Border.all(color: palette.bg, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

/// Badge numérico (Pagos/Chat) — 16px círculo `highlight`, Barlow 700 10px.
class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = TreinoBadgeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Container(
        constraints: const BoxConstraints(
          minWidth: TreinoBadgeTokens.size,
          minHeight: TreinoBadgeTokens.size,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.background,
          borderRadius: BorderRadius.circular(TreinoBadgeTokens.borderRadius),
        ),
        child: Text(
          '$count',
          style: TextStyle(
            fontFamily: AppFonts.barlow,
            fontWeight: AppFonts.w700,
            fontSize: 10,
            color: tokens.foreground,
          ),
        ),
      ),
    );
  }
}

/// Footer del sidebar: sólo el perfil del usuario. Cuenta no aparece también
/// como item genérico: la fila con nombre y plan es su único entrypoint.
class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({
    required this.collapsed,
  });

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(height: 1, color: palette.border),
        _ProfileRow(collapsed: collapsed),
      ],
    );
  }
}

/// Botón dedicado de contraer/expandir — REQ-SH-006. Tooltip contextual
/// (cambia según el estado actual).
class _ToggleButton extends StatelessWidget {
  const _ToggleButton({
    required this.collapsed,
    required this.canToggle,
    required this.onToggle,
  });

  final bool collapsed;
  final bool canToggle;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final tooltip =
        collapsed ? 'Expandir menú' : 'Contraer menú'; // i18n: Fase W1

    return Tooltip(
      message: tooltip,
      child: IconButton(
        key: const Key('sidebar_toggle_button'),
        icon: Icon(TreinoIcon.menu, size: 20, color: palette.textMuted),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        visualDensity: VisualDensity.compact,
        onPressed: canToggle ? onToggle : null,
      ),
    );
  }
}

/// Fila de perfil del footer: avatar + nombre + plan + chevron (REQ-SH-005).
/// Colapsado: solo el avatar, centrado, con tooltip.
///
/// **Es el entrypoint a la cuenta.** Antes era decorativa —chevron incluido,
/// que prometía un menú que nunca abría— y el subtítulo era el literal
/// "Cuenta profesional", igual para un PF en Free que para uno en Plan 3.
/// Ahora navega a `/ajustes` (tab Cuenta, el default), donde vive el banner
/// de upsell, y el subtítulo muestra el tier real vía [tierPlanLabel].
///
/// `go` y no `push`: Ajustes es una sección del shell, no un sub-flujo. Con
/// `push` el sidebar quedaría con Ajustes activo encima de la sección
/// anterior y el back del browser se volvería un laberinto.
class _ProfileRow extends ConsumerWidget {
  const _ProfileRow({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final tokens = CoachHubSidebarItemTokens.of(context);
    final profile = ref.watch(userProfileProvider).valueOrNull;
    final displayName = profile?.displayName?.trim();
    final hasName = displayName != null && displayName.isNotEmpty;
    final initial = hasName ? displayName.substring(0, 1).toUpperCase() : '?';
    final name = hasName ? displayName : 'Mi cuenta'; // i18n: Fase W1
    // Sin `subscription` en el doc → Free por definición, mismo criterio que
    // FacturacionTab (sin backfill).
    final tier = profile?.subscription?.tier ?? SubscriptionTier.free;

    final avatar = CircleAvatar(
      radius: CoachHubLayoutTokens.sidebarAvatarDiameter / 2,
      backgroundColor: palette.bgCard,
      child: Text(
        initial,
        style: TextStyle(
          fontFamily: AppFonts.barlow,
          fontWeight: AppFonts.w700,
          color: palette.accent,
        ),
      ),
    );

    final content = collapsed
        ? Center(child: avatar)
        : Row(
            children: [
              avatar,
              const SizedBox(width: AppSpacing.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppFonts.barlow,
                        fontWeight: AppFonts.w600,
                        fontSize: 14,
                        color: palette.textPrimary,
                      ),
                    ),
                    Text(
                      tierPlanLabel(tier),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppFonts.barlow,
                        fontWeight: AppFonts.w400,
                        fontSize: 12,
                        color: palette.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(TreinoIcon.chevronRight, size: 16, color: palette.textMuted),
            ],
          );

    // Sin margin ni radius: el hover pinta la banda completa del footer, igual
    // que el resto de la franja. Con la píldora de `_SidebarItemRow` (margin 8
    // + padding 14) el avatar de 44 px se corría 6 px respecto del layout que
    // ya tenía la fila, y el footer quedaba desalineado con el nombre.
    final row = TreinoInteractiveState(
      key: Key(collapsed ? 'sidebar_profile_avatar' : 'sidebar_profile_row'),
      onTap: () => context.go('/ajustes'),
      builder: (ctx, states) => AnimatedContainer(
        duration: AppMotionTokens.resolve(ctx, AppMotionTokens.cardStateChange),
        curve: AppMotionTokens.enter,
        padding: EdgeInsets.symmetric(
          // Colapsado el avatar va centrado en 72 px; el padding lo desalinearía.
          horizontal: collapsed ? 0 : AppSpacing.s14,
          vertical: AppSpacing.s12,
        ),
        color: states.hovered ? tokens.hoverBackground : Colors.transparent,
        child: content,
      ),
    );

    return collapsed
        ? Tooltip(message: 'Mi cuenta', child: row) // i18n: Fase W1
        : row;
  }
}
