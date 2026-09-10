import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/widgets/treino_icon.dart';

import 'sidebar_registry.dart';
import 'package:treino/features/coach_hub/presentation/widgets/button/treino_button.dart';

/// Top bar del Coach Hub web (REQ-SH-007). 64 px de alto.
///
/// - El toggle contraer/expandir del sidebar vive en el footer del sidebar
///   (ver `CoachHubSidebar`). El breadcrumb de sección se reemplaza por el
///   título de la sección activa (Barlow Condensed 700 UPPERCASE), derivado
///   de `sidebarRegistry` vía [activeSidebarItem] — sin nueva capa de datos.
/// - **Centro**: campo de búsqueda decorativo (Fase 1 — sin lógica de filtro
///   ni navegación; se activa en una fase posterior).
/// - **Derecha**: campana inerte (ODQ-4, sin badge). La cuenta vive solamente
///   en la fila de perfil del sidebar; duplicarla acá creaba tres accesos a la
///   misma pantalla y repartía preferencias entre superficies distintas.
class CoachHubTopBar extends StatelessWidget {
  const CoachHubTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final location = GoRouterState.of(context).uri.toString();
    final title = activeSidebarItem(location)?.label.toUpperCase() ?? '';

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
          TreinoIconButton(
            icon: TreinoIcon.bell,
            tooltip: 'Notificaciones', // i18n: Fase W1
            color: palette.textMuted,
            onPressed: () {}, // ODQ-4: visible pero inerte en W1
          ),
        ],
      ),
    );
  }
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
          prefixIcon:
              Icon(TreinoIcon.search, size: 18, color: palette.textMuted),
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
