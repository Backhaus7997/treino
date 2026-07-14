import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../performance/application/performance_test_providers.dart';
import '../../performance/presentation/widgets/performance_progress_chart.dart';

/// Rendimiento del PROPIO atleta — saltos, velocidad, fuerza 1RM y resistencia
/// en el tiempo.
///
/// Gemela de [AnthropometryScreen], con las mismas razones y la misma
/// limitación conocida (sólo un `trainer` puede CREAR evaluaciones hoy — ver la
/// doc de aquella pantalla). Usa [ownPerformanceTestsProvider], no la variante
/// de óptica-entrenador.
class PerformanceScreen extends ConsumerWidget {
  const PerformanceScreen({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final async = ref.watch(ownPerformanceTestsProvider(uid));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(title: l10n.performanceScreenTitle),
        Expanded(
          child: TreinoStateSwitcher(
            childKey: ValueKey(
              async.when(
                loading: () => 'loading',
                error: (_, __) => 'error',
                data: (_) => 'data',
              ),
            ),
            child: async.when(
              loading: () => Center(
                child: CircularProgressIndicator(color: palette.accent),
              ),
              error: (_, __) => _ErrorState(
                onRetry: () => ref.invalidate(ownPerformanceTestsProvider(uid)),
              ),
              data: (tests) => ListView(
                padding: EdgeInsets.fromLTRB(
                    20, 12, 20, 20 + MediaQuery.paddingOf(context).bottom),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  // El chart exige >= 2 evaluaciones (su propio contrato).
                  if (tests.isEmpty)
                    _Hint(text: l10n.performanceEmptyState)
                  else if (tests.length < 2)
                    _Hint(text: l10n.performanceNeedsMoreData)
                  else
                    PerformanceProgressChart(tests: tests),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(TreinoIcon.back, color: palette.textPrimary),
            onPressed: () => _safePopOrInsights(context),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 24,
              letterSpacing: 1.2,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

void _safePopOrInsights(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/home/insights');
  }
}

// ── Hint (empty / not-enough-data) ────────────────────────────────────────────

class _Hint extends StatelessWidget {
  const _Hint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              l10n.insightsLoadError,
              textAlign: TextAlign.center,
              style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: Text(l10n.coachRetryLabel)),
          ],
        ),
      ),
    );
  }
}
