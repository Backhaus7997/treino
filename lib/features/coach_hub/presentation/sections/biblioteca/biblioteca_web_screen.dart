// NOTE: el Scaffold y el SafeArea los provee CoachHubScaffold (el shell).
// NO los agregues acá (ADR-CHW-005).
//
// PR2 — BibliotecaWebScreen: shell + 2 tabs (Ejercicios + Templates Rutinas).
// Wires the real EjerciciosTab and TemplatesTab; routes.dart is updated in
// the same PR to swap ProximamenteScreen → this screen.
//
// Todas las strings están en español hardcodeado + comentario // i18n.
// NO se usa AppL10n en este archivo (constraint C-6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

import 'providers/biblioteca_providers.dart';
import 'widgets/ejercicios_tab.dart';
import 'widgets/templates_tab.dart';

/// Sección Biblioteca del Coach Hub web.
///
/// Sigue el contrato de sección (ADR-CHW-005): sin Scaffold propio, sin
/// SafeArea. El shell [CoachHubScaffold] provee el chrome.
///
/// Dos tabs: "Ejercicios" (merged catalog+custom) y "Templates Rutinas".
/// Tab labels incluyen count reactivo:
///   - Ejercicios · N = unfiltered catalog+custom count (stable while filtering).
///   - Templates Rutinas · N = trainerTemplatesStreamProvider count.
///
/// REQ-BIBW-01, REQ-BIBW-02.
/// SCENARIO-BIBW-02a.
class BibliotecaWebScreen extends ConsumerStatefulWidget {
  const BibliotecaWebScreen({super.key});

  @override
  ConsumerState<BibliotecaWebScreen> createState() =>
      _BibliotecaWebScreenState();
}

class _BibliotecaWebScreenState extends ConsumerState<BibliotecaWebScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    // Unfiltered exercise count for the stable tab label.
    final unfilteredAsync = ref.watch(bibliotecaUnfilteredCountProvider);
    final ejerciciosN = unfilteredAsync.valueOrNull ?? 0;

    // Templates Rutinas · N count (reactive).
    final uid = ref.watch(currentUidProvider) ?? '';
    final templatesAsync = uid.isEmpty
        ? const AsyncValue<List<dynamic>>.data([])
        : ref.watch(trainerTemplatesStreamProvider(uid));
    final templatesN = templatesAsync.valueOrNull?.length ?? 0;

    final tabLabels = [
      'Ejercicios · $ejerciciosN', // i18n
      'Templates Rutinas · $templatesN', // i18n
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header + subtítulo honesto ──────────────────────────────
        TreinoFadeSlideIn(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s20,
              AppSpacing.s20,
              AppSpacing.s20,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TreinoSectionHeader(title: 'Biblioteca'), // i18n
                const SizedBox(height: AppSpacing.hairline),
                Text(
                  '$ejerciciosN ejercicios · $templatesN templates', // i18n
                  style: TextStyle(
                    fontFamily: AppFonts.barlow,
                    fontSize: 13,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── TabBar ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s18,
            AppSpacing.s20,
            AppSpacing.s18,
            0,
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: false,
            labelColor: palette.accent,
            unselectedLabelColor: palette.textMuted,
            indicatorColor: palette.accent,
            indicatorWeight: 2,
            labelStyle: const TextStyle(
              fontFamily: AppFonts.barlow,
              fontWeight: FontWeight.w600,
            ),
            tabs: tabLabels.map((l) => Tab(text: l)).toList(),
          ),
        ),

        // ── Tab body ────────────────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              EjerciciosTab(),
              TemplatesTab(),
            ],
          ),
        ),
      ],
    );
  }
}
