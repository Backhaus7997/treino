import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/theme_mode_provider.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/profile/application/user_providers.dart';

import 'sidebar_registry.dart';

/// Top bar del Coach Hub web (REQ-SH-007). 64 px de alto.
///
/// - El toggle contraer/expandir del sidebar vive en el footer del sidebar
///   (ver `CoachHubSidebar`). El breadcrumb de sección se reemplaza por el
///   título de la sección activa (Barlow Condensed 700 UPPERCASE), derivado
///   de `sidebarRegistry` vía [activeSidebarItem] — sin nueva capa de datos.
/// - **Centro**: campo de búsqueda decorativo (Fase 1 — sin lógica de filtro
///   ni navegación; se activa en una fase posterior).
/// - **Derecha**: campana inerte (ODQ-4, sin badge) + menú de cuenta con
///   selector de tema (System/Light/Dark, ADR-SH-005) y "Salir" (mismo
///   `FirebaseAuth.instance.signOut()` que dashboard/not-allowed).
class CoachHubTopBar extends ConsumerWidget {
  const CoachHubTopBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);

    final displayName =
        ref.watch(userProfileProvider).valueOrNull?.displayName?.trim();
    final initial = (displayName != null && displayName.isNotEmpty)
        ? displayName.substring(0, 1).toUpperCase()
        : '?';

    final location = GoRouterState.of(context).uri.toString();
    final title = activeSidebarItem(location)?.label.toUpperCase() ?? '';

    final themeMode = ref.watch(themeModeProvider);

    return Container(
      height: CoachHubLayoutTokens.topBarHeight,
      color: palette.bg,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s20),
      child: Row(
        children: [
          Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppFonts.barlowCondensed,
              fontWeight: AppFonts.w700,
              fontSize: 24,
              letterSpacing: 0.5,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(width: AppSpacing.s20),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: _SearchField(palette: palette),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s20),
          IconButton(
            tooltip: 'Notificaciones', // i18n: Fase W1
            icon: Icon(TreinoIcon.bell, color: palette.textMuted),
            onPressed: () {}, // ODQ-4: visible pero inerte en W1
          ),
          PopupMenuButton<String>(
            tooltip: 'Cuenta', // i18n: Fase W1
            onSelected: (value) => _onSelected(context, ref, value),
            itemBuilder: (context) => [
              _ThemeMenuItem(
                value: 'theme_system',
                label: 'Sistema', // i18n: Fase W1
                selected: themeMode == ThemeMode.system,
                palette: palette,
              ),
              _ThemeMenuItem(
                value: 'theme_light',
                label: 'Claro', // i18n: Fase W1
                selected: themeMode == ThemeMode.light,
                palette: palette,
              ),
              _ThemeMenuItem(
                value: 'theme_dark',
                label: 'Oscuro', // i18n: Fase W1
                selected: themeMode == ThemeMode.dark,
                palette: palette,
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'signout',
                child: Row(
                  children: [
                    Icon(TreinoIcon.signOut,
                        size: 18, color: palette.textPrimary),
                    const SizedBox(width: 8),
                    const Text('Salir'), // i18n: Fase W1
                  ],
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: palette.bgCard,
                    child: Text(
                      initial,
                      style: TextStyle(
                        color: palette.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(TreinoIcon.chevronDown, size: 16, color: palette.textMuted),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _onSelected(BuildContext context, WidgetRef ref, String value) {
    switch (value) {
      case 'theme_system':
        ref.read(themeModeProvider.notifier).setMode(ThemeMode.system);
      case 'theme_light':
        ref.read(themeModeProvider.notifier).setMode(ThemeMode.light);
      case 'theme_dark':
        ref.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
      case 'signout':
        FirebaseAuth.instance.signOut();
    }
  }
}

/// Ítem de menú del selector de tema — check a la izquierda si está activo.
class _ThemeMenuItem extends PopupMenuItem<String> {
  _ThemeMenuItem({
    required String value,
    required String label,
    required bool selected,
    required AppPalette palette,
  }) : super(
          value: value,
          child: Row(
            children: [
              Icon(
                selected ? TreinoIcon.checkCircleFill : TreinoIcon.checkCircleEmpty,
                size: 16,
                color: selected ? palette.accent : palette.textMuted,
              ),
              const SizedBox(width: 8),
              Text(label),
            ],
          ),
        );
}

/// Campo de búsqueda decorativo (Fase 1) — sin lógica de filtro/navegación.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: TextField(
        enabled: false,
        style: TextStyle(color: palette.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Buscar alumnos, rutinas, plan...', // i18n: Fase W1
          hintStyle: TextStyle(color: palette.textMuted, fontSize: 14),
          prefixIcon: Icon(TreinoIcon.search, size: 18, color: palette.textMuted),
          filled: true,
          fillColor: palette.bgCard,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide(color: palette.border),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            borderSide: BorderSide(color: palette.border),
          ),
        ),
      ),
    );
  }
}
