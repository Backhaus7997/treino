import 'package:flutter/material.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/components/treino_transparent_tokens.dart';
import 'package:treino/app/theme/tokens/primitives.dart';

/// Tab bar del detalle de Alumno — Fase 3 WU-04.
///
/// Extraído de `_Tabs` (`alumno_detail_screen.dart`, ADR-A3-04). Conserva
/// `DefaultTabController` + `TabBarView` en el screen raíz (ADR-A3-08) — este
/// widget SOLO re-estila el `TabBar` con tokens del sistema (`AppSpacing`/
/// `AppRadius`) en vez de valores sueltos (`4`/`24` no pertenecían a la
/// escala cerrada). El foco por teclado (Tab/flechas + Enter/Space) ya lo
/// resuelve `TabBar` de Flutter de forma nativa — cada `Tab` es un
/// `FocusNode` navegable sin cambios adicionales.
class AlumnoTabs extends StatelessWidget {
  const AlumnoTabs({super.key, required this.palette, required this.labels});

  final AppPalette palette;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s8),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: palette.border),
      ),
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerColor: TreinoTransparentTokens.value,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: palette.accent,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        splashBorderRadius: BorderRadius.circular(AppRadius.lg),
        labelColor: palette.bg,
        unselectedLabelColor: palette.textMuted,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontSize: 13),
        tabs: [for (final l in labels) Tab(text: l, height: 38)],
      ),
    );
  }
}
