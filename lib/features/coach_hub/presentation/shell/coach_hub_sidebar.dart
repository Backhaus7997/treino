import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/application/sidebar_collapsed_provider.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/profile/application/user_providers.dart';

import 'sidebar_item.dart';
import 'sidebar_registry.dart';

/// Sidebar del Coach Hub web (REQ-SH-001..006, ADR-SH-004).
///
/// Renderiza `sidebarRegistry` agrupado por [SidebarGroup] con header por
/// grupo (oculto al colapsar) y `Ajustes` pinneado al footer, junto al
/// toggle dedicado y al perfil del usuario. Ancho animado
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
    final ajustesItems =
        items.where((item) => item.group == SidebarGroup.ajustes).toList();
    final ajustesItem = ajustesItems.isEmpty ? null : ajustesItems.first;

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
          _SidebarHeader(collapsed: collapsed),
          Container(height: 1, color: palette.border),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < groupEntries.length; i++) ...[
                    if (i > 0) Container(height: 1, color: palette.border),
                    if (!collapsed)
                      _GroupHeader(label: groupEntries[i].key.label),
                    for (final item in groupEntries[i].value)
                      _SidebarItemRow(
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
            canToggle: canToggle,
            onToggle: () =>
                ref.read(sidebarCollapsedProvider.notifier).toggle(),
            ajustesItem: ajustesItem,
            ajustesActive:
                ajustesItem != null && _isActive(location, ajustesItem.route),
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
  const _SidebarHeader({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      alignment: collapsed ? Alignment.center : Alignment.centerLeft,
      padding: EdgeInsets.symmetric(
        horizontal: collapsed ? 0 : AppSpacing.s20,
      ),
      child: collapsed
          ? const SizedBox.shrink()
          : Text(
              'TREINO',
              style: TextStyle(
                fontFamily: AppFonts.barlowCondensed,
                fontWeight: AppFonts.w700,
                fontSize: 20,
                letterSpacing: 1,
                color: palette.accent,
              ),
            ),
    );
  }
}

/// Header de grupo (GESTIÓN, RECURSOS, …). Solo visible expandido — ya NO
/// aloja el toggle (REQ-SH-004/006: el toggle se mudó al footer).
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});

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

    final row = TreinoInteractiveState(
      onTap: () => context.go(item.route),
      builder: (ctx, states) {
        final background = active
            ? tokens.activeBackground
            : states.hovered
                ? tokens.hoverBackground
                : Colors.transparent;

        return AnimatedContainer(
          duration: AppMotionTokens.resolve(
            ctx,
            AppMotionTokens.cardStateChange,
          ),
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
          child: Row(
            mainAxisAlignment:
                collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Icon(item.iconBuilder(), size: 20, color: fg),
              if (!collapsed) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppFonts.barlow,
                      color: fg,
                      fontSize: 14,
                      fontWeight: active ? AppFonts.w600 : AppFonts.w400,
                    ),
                  ),
                ),
                if (badgeCount != null && badgeCount! > 0)
                  _Badge(count: badgeCount!),
              ],
            ],
          ),
        );
      },
    );

    return TreinoFadeSlideIn(
        delay: delay, distance: AppMotion.slideSm, child: row);
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

/// Footer del sidebar: Ajustes pinneado, toggle dedicado y perfil del
/// usuario (REQ-SH-005/006, ADR-SH-004).
class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({
    required this.collapsed,
    required this.canToggle,
    required this.onToggle,
    required this.ajustesItem,
    required this.ajustesActive,
  });

  final bool collapsed;
  final bool canToggle;
  final VoidCallback onToggle;
  final SidebarItem? ajustesItem;
  final bool ajustesActive;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (ajustesItem != null)
          _SidebarItemRow(
            item: ajustesItem!,
            collapsed: collapsed,
            active: ajustesActive,
            delay: Duration.zero,
            badgeCount: null,
          ),
        Container(height: 1, color: palette.border),
        _ToggleRow(
            collapsed: collapsed, canToggle: canToggle, onToggle: onToggle),
        Container(height: 1, color: palette.border),
        _ProfileRow(collapsed: collapsed),
      ],
    );
  }
}

/// Botón dedicado de contraer/expandir — REQ-SH-006. Tooltip contextual
/// (cambia según el estado actual).
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
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

    final button = Tooltip(
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: collapsed
          ? Center(child: button)
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s14),
              child: Align(alignment: Alignment.centerLeft, child: button),
            ),
    );
  }
}

/// Fila de perfil del footer: avatar + nombre + subtítulo + chevron
/// (REQ-SH-005). Colapsado: solo el avatar, centrado.
///
/// Subtítulo estático (placeholder) — sin nueva capa de datos en Fase 1.
class _ProfileRow extends ConsumerWidget {
  const _ProfileRow({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final displayName =
        ref.watch(userProfileProvider).valueOrNull?.displayName?.trim();
    final hasName = displayName != null && displayName.isNotEmpty;
    final initial = hasName ? displayName.substring(0, 1).toUpperCase() : '?';
    final name = hasName ? displayName : 'Mi cuenta'; // i18n: Fase W1

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

    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s12),
        child: Center(child: avatar),
      );
    }

    return Padding(
      key: const Key('sidebar_profile_row'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s14,
        vertical: AppSpacing.s12,
      ),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 12),
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
                  'Cuenta profesional', // i18n: Fase W1 — placeholder estático
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
          Icon(TreinoIcon.chevronDown, size: 16, color: palette.textMuted),
        ],
      ),
    );
  }
}
