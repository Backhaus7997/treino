import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../workout/presentation/widgets/exercise_progression_section.dart'
    show ChartPeriodLabels, ChartPeriodSelector;
import '../application/wellbeing_trend_providers.dart';
import '../domain/chart_period.dart';
import '../domain/wellbeing_trend.dart';
import 'widgets/wellbeing_trend_chart.dart';

/// CÓMO ME SENTÍ — la serie subjetiva del atleta en el tiempo (#643 slice 3).
///
/// Es la pantalla que le da sentido a los dos slices de captura. Sin ella el
/// check-in es un diario que nadie lee: el valor del hallazgo no está en
/// anotar el dolor de hoy, está en ver que este mes duele menos que el
/// anterior. Cuatro de cinco entrevistados miden su progreso así, y hasta acá
/// la app sólo sabía medir kilos y volumen.
///
/// ⚠️ **Límite no negociable: registrar, no interpretar.** La pantalla muestra
/// la serie del usuario y cuenta sus registros. No diagnostica, no recomienda
/// ejercicios "para el dolor", no sugiere parar ni seguir, no dice si algo es
/// normal y no califica ningún número como bueno o malo. El único texto que se
/// acerca al terreno de la salud es el aviso neutro de consultar a un
/// profesional, que no condiciona nada de la app.
///
/// Tampoco es gamificación (AGENTS.md regla 4): no hay puntaje, racha, logro ni
/// recompensa por registrar.
///
/// [uid] explícito — misma convención del resto de las pantallas del hub.
class WellbeingTrendScreen extends ConsumerStatefulWidget {
  const WellbeingTrendScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<WellbeingTrendScreen> createState() =>
      _WellbeingTrendScreenState();
}

class _WellbeingTrendScreenState extends ConsumerState<WellbeingTrendScreen> {
  ChartPeriod _period = ChartPeriod.defaultPeriod;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final key = (uid: widget.uid, period: _period);
    final async = ref.watch(wellbeingTrendProvider(key));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(title: l10n.wellbeingTrendScreenTitle),
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
                onRetry: () => ref.invalidate(wellbeingTrendProvider(key)),
              ),
              data: (trend) => ListView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  20 + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: ChartPeriodSelector(
                      selected: _period,
                      labels: ChartPeriodLabels(
                        last30dLabel: l10n.progressionPeriodLast30Days,
                        thisWeekLabel: l10n.progressionPeriodThisWeek,
                        monthLabel: l10n.progressionPeriodMonth,
                      ),
                      onSelect: (p) => setState(() => _period = p),
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (trend.points.isEmpty)
                    _Hint(text: l10n.wellbeingTrendEmptyState)
                  else if (trend.points.length < kWellbeingTrendMinPoints)
                    _Hint(text: l10n.wellbeingTrendNeedsMoreData)
                  else
                    WellbeingTrendChart(points: trend.points),
                  if (trend.recordCount > 0) ...[
                    const SizedBox(height: 20),
                    _PainSummary(trend: trend),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Resumen de dolor ─────────────────────────────────────────────────────────

/// Cuántos registros del período reportaron dolor, cuántos el período anterior,
/// y en qué zonas.
///
/// El período anterior está para que el usuario compare SU dato con SU dato —
/// es literalmente lo que pidió el hallazgo. Se enuncia como dos conteos uno al
/// lado del otro y NUNCA como una diferencia calificada: nada de "mejoraste",
/// "empeoraste", flechas de tendencia ni colores de semáforo. La lectura la
/// hace el usuario.
class _PainSummary extends StatelessWidget {
  const _PainSummary({required this.trend});

  final WellbeingTrend trend;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.wellbeingTrendPainHeading,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.wellbeingTrendPainCount(trend.painCount, trend.recordCount),
            style: GoogleFonts.barlow(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          if (trend.previousRecordCount > 0) ...[
            const SizedBox(height: 4),
            Text(
              l10n.wellbeingTrendPainCountPrevious(
                trend.previousPainCount,
                trend.previousRecordCount,
              ),
              style: GoogleFonts.barlow(
                fontSize: 13,
                color: palette.textMuted,
              ),
            ),
          ],
          if (trend.painByArea.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              l10n.wellbeingTrendAreasHeading,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 1.2,
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            for (final entry in trend.painByArea)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.area.label,
                        style: GoogleFonts.barlow(
                          fontSize: 14,
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '${entry.count}',
                      style: GoogleFonts.barlowCondensed(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: palette.accent,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (trend.painCount > 0) ...[
            const SizedBox(height: 8),
            // Texto neutro y terminal, el mismo del sheet de captura: la app no
            // interpreta el dato ni condiciona nada a esta respuesta.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(TreinoIcon.infoCircle, size: 16, color: palette.textMuted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.wellbeingMedicalDisclaimer,
                    style: GoogleFonts.barlow(
                      fontSize: 13,
                      color: palette.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Chrome compartido del hub ────────────────────────────────────────────────

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
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 24,
                letterSpacing: 1.2,
                color: palette.textPrimary,
              ),
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
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Text(
        text,
        style: GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
      ),
    );
  }
}

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
              l10n.wellbeingTrendLoadError,
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
