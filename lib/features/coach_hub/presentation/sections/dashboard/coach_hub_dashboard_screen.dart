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

            // Sin entrada one-shot: el resto de las secciones del hub
            // (Agenda, Pagos, Biblioteca, Chat, Ajustes, Alumnos) aparecen
            // instantáneas al click del sidebar, y cada sección monta vía
            // NoTransitionPage — un TreinoFadeSlideIn acá se re-dispararía
            // en CADA visita a la superficie más frecuentada del hub, no
            // solo la primera vez. Mismo motion que sus hermanas.
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
    // Sin `Column` intermedia: una `Column` reparte alto LIBRE a sus hijos, así
    // que se comía el stretch de la fila y la card volvía a su alto natural —
    // justo lo que la grilla viene a evitar. El wrapper de motion sí pasa las
    // constraints de largo.
    final leftColumn = TreinoFadeSlideIn(
      delay: AppMotion.stagger(_leftColumnIndex),
      child: const DashboardPendingSection(),
    );
    const rightColumn = DashboardRightColumn(
      startIndex: _rightColumnStartIndex,
    );

    // El stagger sigue el orden de LECTURA de la grilla —izquierda a derecha,
    // arriba a abajo—, que es el mismo orden en el que estaban las cards
    // cuando eran dos columnas apiladas.
    final filas = <(Widget, Widget)>[
      (
        leftColumn,
        TreinoFadeSlideIn(
          delay: AppMotion.stagger(_rightColumnStartIndex),
          child: const DashboardProximasSesionesCard(),
        ),
      ),
      (
        TreinoFadeSlideIn(
          delay: AppMotion.stagger(_rightColumnStartIndex + 1),
          child: const DashboardVencimientos7dCard(),
        ),
        TreinoFadeSlideIn(
          delay: AppMotion.stagger(_rightColumnStartIndex + 2),
          child: const DashboardInactivosCard(),
        ),
      ),
    ];

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
          _CardGrid(filas: filas),
        ] else ...[
          leftColumn,
          const SizedBox(height: AppSpacing.s18),
          rightColumn,
        ],
      ],
    );
  }
}

// ── Grilla de cards ───────────────────────────────────────────────────────────

/// Las cards de a pares, una fila por par.
///
/// Antes eran DOS COLUMNAS INDEPENDIENTES: una card a la izquierda y tres
/// apiladas a la derecha. Como cada columna crecía por su cuenta, la izquierda
/// terminaba a un tercio del alto de la derecha y abajo quedaba un agujero del
/// tamaño de dos cards.
///
/// En una grilla ese agujero no puede existir: cada fila mide lo que mide su
/// par y la siguiente arranca ahí nomás. Y el par no es arbitrario — arriba va
/// lo de HOY (pendientes + próximas sesiones), abajo lo que pide atención
/// (vencimientos + inactivos).
///
/// `stretch` dentro del `IntrinsicHeight` iguala el alto de las dos cards de
/// cada fila: dos cards de distinto alto lado a lado leen como desalineadas,
/// que es la mitad del desprolijo que esto viene a arreglar.
class _CardGrid extends StatelessWidget {
  const _CardGrid({required this.filas});

  /// Cada fila es (card ancha 55, card angosta 45). La proporción viene del
  /// layout anterior: la izquierda era la columna principal.
  final List<(Widget, Widget)> filas;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < filas.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.s18),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 55, child: filas[i].$1),
                const SizedBox(width: AppSpacing.s20),
                Expanded(flex: 45, child: filas[i].$2),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// Right column (Próximas sesiones + Vencimientos 7d + Inactivos) — extraída a
// dashboard/widgets/dashboard_right_column.dart (WU-05 fase-2, ADR-D2-05).
