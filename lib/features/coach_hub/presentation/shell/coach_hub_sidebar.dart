import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/application/sidebar_collapsed_provider.dart';

import 'sidebar_item.dart';
import 'sidebar_registry.dart';

/// Sidebar del Coach Hub web (REQ-CHW-SIDEBAR-001..003).
///
/// Renderiza `sidebarRegistry` agrupado por [SidebarGroup], con header por
/// grupo (oculto al colapsar) y `Ajustes` pinneado abajo. Ancho animado
/// 264↔72 px. El estado colapsado viene de `sidebarCollapsedProvider`, gateado
/// por `sharedPreferencesProvider` (optimistic-expanded mientras resuelve).
class CoachHubSidebar extends ConsumerWidget {
  const CoachHubSidebar({super.key, this.collapsedOverride});

  /// Si es no-nulo, fuerza el estado colapsado e ignora
  /// `sidebarCollapsedProvider`. El `CoachHubScaffold` lo pasa en `true` en
  /// viewport compact (ADR-CHW-004) sin escribir el provider, así el valor
  /// guardado del usuario se preserva al volver a desktop.
  final bool? collapsedOverride;

  static const double expandedWidth = 264;
  static const double collapsedWidth = 72;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final bool stored = ref.watch(sharedPreferencesProvider).maybeWhen(
          data: (_) => ref.watch(sidebarCollapsedProvider),
          orElse: () => false,
        );
    final collapsed = collapsedOverride ?? stored;
    // El toggle vive DENTRO del sidebar, fusionado con el header del primer
    // grupo (GESTIÓN) — sin fila propia arriba. Deshabilitado cuando el estado
    // está forzado (viewport compact, donde `collapsedOverride` es no-nulo) o
    // cuando prefs todavía no resolvió.
    final canToggle = collapsedOverride == null &&
        ref.watch(sharedPreferencesProvider).hasValue;
    final location = GoRouterState.of(context).uri.toString();

    final groups = <SidebarGroup, List<SidebarItem>>{};
    for (final group in SidebarGroup.values) {
      if (group == SidebarGroup.ajustes) continue;
      final items =
          sidebarRegistry.where((item) => item.group == group).toList();
      if (items.isNotEmpty) groups[group] = items;
    }
    final groupEntries = groups.entries.toList();
    final ajustesItems = sidebarRegistry
        .where((item) => item.group == SidebarGroup.ajustes)
        .toList();

    return AnimatedContainer(
      key: const Key('coach_hub_sidebar_container'),
      width: collapsed ? collapsedWidth : expandedWidth,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
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
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < groupEntries.length; i++) ...[
                    // El primer header (GESTIÓN) aloja el toggle — siempre
                    // visible (incluso colapsado, para poder re-expandir). Los
                    // demás headers siguen ocultándose al colapsar.
                    if (i == 0)
                      _GroupHeaderToggle(
                        label: groupEntries[i].key.label,
                        collapsed: collapsed,
                        canToggle: canToggle,
                        onToggle: () => ref
                            .read(sidebarCollapsedProvider.notifier)
                            .toggle(),
                      )
                    else if (!collapsed)
                      _GroupHeader(label: groupEntries[i].key.label),
                    for (final item in groupEntries[i].value)
                      _SidebarRow(
                        item: item,
                        collapsed: collapsed,
                        active: _isActive(location, item.route),
                      ),
                  ],
                ],
              ),
            ),
          ),
          for (final item in ajustesItems)
            _SidebarRow(
              item: item,
              collapsed: collapsed,
              active: _isActive(location, item.route),
            ),
        ],
      ),
    );
  }

  bool _isActive(String location, String route) =>
      location == route || location.startsWith('$route/');
}

/// Header de grupo (RESUMEN, ALUMNOS, …). Sólo visible expandido.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 8),
      child: Text(
        label,
        style: TextStyle(
          color: palette.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

/// Header del PRIMER grupo (GESTIÓN): además del label, aloja el toggle
/// contraer/expandir del sidebar — ícono hamburguesa clásico, sin fila propia.
/// A diferencia de [_GroupHeader], sigue visible colapsado (solo el ícono,
/// centrado) porque es el único punto para volver a expandir el sidebar.
class _GroupHeaderToggle extends StatelessWidget {
  const _GroupHeaderToggle({
    required this.label,
    required this.collapsed,
    required this.canToggle,
    required this.onToggle,
  });

  final String label;
  final bool collapsed;
  final bool canToggle;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final toggleButton = IconButton(
      tooltip: 'Contraer/expandir menú', // i18n: Fase W1
      icon: Icon(TreinoIcon.menu, size: 20, color: palette.textMuted),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      visualDensity: VisualDensity.compact,
      onPressed: canToggle ? onToggle : null,
    );

    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 8),
        child: Center(child: toggleButton),
      );
    }

    return Padding(
      // Left padding (14) matches _GroupHeader — el label queda alineado con
      // el de RECURSOS; el toggle va al final de la fila.
      padding: const EdgeInsets.fromLTRB(14, 14, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
          ),
          toggleButton,
        ],
      ),
    );
  }
}

/// Fila clickeable de un [SidebarItem]. Hover usa `palette.borderHover`
/// (ADR-CHW-006); el item activo se resalta con `accent` + `bgCard`.
class _SidebarRow extends StatefulWidget {
  const _SidebarRow({
    required this.item,
    required this.collapsed,
    required this.active,
  });

  final SidebarItem item;
  final bool collapsed;
  final bool active;

  @override
  State<_SidebarRow> createState() => _SidebarRowState();
}

class _SidebarRowState extends State<_SidebarRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final fg = widget.active ? palette.accent : palette.textMuted;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.go(widget.item.route),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: widget.active ? palette.bgCard : palette.bg,
            border: Border.all(
              // Borde invisible (color bg) en reposo → sin layout shift al
              // hacer hover; sin literal transparente.
              color: _hovered ? palette.borderHover : palette.bg,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: widget.collapsed
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(widget.item.iconBuilder(), size: 20, color: fg),
              if (!widget.collapsed) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.item.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: fg,
                      fontSize: 14,
                      fontWeight:
                          widget.active ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
