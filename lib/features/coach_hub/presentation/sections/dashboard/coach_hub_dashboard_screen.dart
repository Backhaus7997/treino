// NOTE: el Scaffold y el SafeArea los provee CoachHubScaffold (el shell).
// NO los agregues acá (ADR-CHW-005).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/widgets/dashboard_hero.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/widgets/dashboard_kpi_strip.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/widgets/dashboard_pending.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/widgets/dashboard_right_column.dart';

// ─── Dashboard ────────────────────────────────────────────────────────────────

/// Coach Hub web dashboard — "Hoy" landing screen.
///
/// Adaptive two-column layout (>=900px wide) or single-column stack.
/// Section contract: ConsumerWidget, no Scaffold/SafeArea, AppPalette,
/// TreinoIcon, showDialog, AppL10n (ADR-CHW-005).
///
/// PR1: alert banner (placeholder) + welcome card + KPI strip + two column
/// stubs. Old student-list widgets preserved below for now (PR3 removes).
class CoachHubDashboardScreen extends ConsumerWidget {
  const CoachHubDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Align.topCenter en vez de Center: centra horizontalmente pero pega
    // el content al top. Con Center puro, cuando el viewport es alto y el
    // content es corto (poca data en dev), sobraba mucho espacio en blanco
    // arriba y abajo.
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        // maxWidth 1600 evita que el content se estire en 4K/5K pero
        // aprovecha bien viewports 1440-1920 sin dejar mucho espacio muerto
        // a los lados. Antes era 1280 (conservador para 720p/1080p) y en
        // monitores Retina/4K quedaba pegado a la izquierda con mucho aire
        // en la derecha.
        constraints: const BoxConstraints(maxWidth: 1600),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Finite-height guard mirrors agenda_web_screen.dart:107-108.
            final wide =
                constraints.maxWidth >= 900 && constraints.maxHeight.isFinite;

            final content = _DashboardContent(wide: wide);

            if (wide) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s20,
                  vertical: AppSpacing.s20,
                ),
                child: content,
              );
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s18,
                vertical: AppSpacing.s18,
              ),
              child: content,
            );
          },
        ),
      ),
    );
  }
}

// ── Dashboard Content ─────────────────────────────────────────────────────────

class _DashboardContent extends ConsumerWidget {
  const _DashboardContent({required this.wide});
  final bool wide;

  // Índices de stagger de las secciones de nivel superior (WU-06):
  // 0 alert banner · 1 welcome card · 2 KPI strip · 3 columna izquierda ·
  // 4-6 las 3 cards de la columna derecha (ver DashboardRightColumn).
  static const _bannerIndex = 0;
  static const _welcomeIndex = 1;
  static const _kpiIndex = 2;
  static const _leftColumnIndex = 3;
  static const _rightColumnStartIndex = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leftColumn = TreinoFadeSlideIn(
      delay: AppMotion.stagger(_leftColumnIndex),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashboardPendingSection(),
        ],
      ),
    );
    const rightColumn = DashboardRightColumn(
      startIndex: _rightColumnStartIndex,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TreinoFadeSlideIn(
          delay: AppMotion.stagger(_bannerIndex),
          child: const DashboardAlertBanner(),
        ),
        const SizedBox(height: AppSpacing.s18),
        TreinoFadeSlideIn(
          delay: AppMotion.stagger(_welcomeIndex),
          child: const DashboardWelcomeCard(),
        ),
        const SizedBox(height: AppSpacing.s18),
        TreinoFadeSlideIn(
          delay: AppMotion.stagger(_kpiIndex),
          child: DashboardKpiStrip(wide: wide),
        ),
        const SizedBox(height: AppSpacing.s20),
        if (wide) ...[
          _TwoColumnLayout(left: leftColumn, right: rightColumn),
        ] else ...[
          leftColumn,
          const SizedBox(height: AppSpacing.s18),
          rightColumn,
        ],
      ],
    );
  }
}

// ── Two-column layout ──────────────────────────────────────────────────────────

class _TwoColumnLayout extends StatelessWidget {
  const _TwoColumnLayout({required this.left, required this.right});
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 55, child: left),
          const SizedBox(width: AppSpacing.s20),
          Expanded(flex: 45, child: right),
        ],
      ),
    );
  }
}

// Right column (Próximas sesiones + Vencimientos 7d + Inactivos) — extraída a
// dashboard/widgets/dashboard_right_column.dart (WU-05 fase-2, ADR-D2-05).
