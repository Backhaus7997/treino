import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../measurements/application/measurement_providers.dart';
import '../../measurements/presentation/widgets/measurement_progress_chart.dart';

/// MEDIDAS del PROPIO atleta — peso corporal y circunferencias en el tiempo.
///
/// Cierra una asimetría real: hasta ahora el entrenador cargaba las mediciones
/// de su alumno y era el ÚNICO que las veía ([athlete_detail_screen.dart]). El
/// alumno no tenía ninguna pantalla para mirar sus propios datos.
///
/// Usa [ownMeasurementsProvider] (query `athleteId ==`), NO
/// [measurementsForAthleteProvider] (query `recordedBy == trainerUid`, óptica
/// del PF): el atleta debe ver TODAS sus mediciones, sin importar cuál de sus
/// entrenadores —presente o pasado— las registró. (Verificado en el reporte
/// del usuario: tras desvincularse del PF, sigue viendo lo que aquél le cargó.)
///
/// SOLO-LECTURA por ahora: hoy sólo un usuario con rol `trainer` puede CREAR
/// mediciones (firestore.rules — decisión AD-1 de `rules-hardening`). El
/// auto-registro por el propio alumno + visibilidad para su entrenador
/// vinculado es la siguiente capa (cambio de reglas + esquema, va por SDD). El
/// empty state ya anticipa ese futuro apuntando a quién las carga hoy.
///
/// [uid] explícito — misma convención de reusabilidad que el resto de las
/// pantallas del hub ([MuscleDistributionScreen], [VolumeByGroupScreen]).
class MeasurementsScreen extends ConsumerWidget {
  const MeasurementsScreen({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final async = ref.watch(ownMeasurementsProvider(uid));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(title: l10n.measurementsScreenTitle),
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
                onRetry: () => ref.invalidate(ownMeasurementsProvider(uid)),
              ),
              data: (measurements) => ListView(
                padding: EdgeInsets.fromLTRB(
                    20, 12, 20, 20 + MediaQuery.paddingOf(context).bottom),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  // El chart exige >= 2 puntos (su propio contrato). Con 0 o 1
                  // no hay progreso que dibujar — y son dos situaciones
                  // distintas para el usuario, así que llevan mensajes
                  // distintos.
                  if (measurements.isEmpty)
                    _Hint(text: l10n.measurementsEmptyState)
                  else if (measurements.length < 2)
                    _Hint(text: l10n.measurementsNeedsMoreData)
                  else
                    MeasurementProgressChart(measurements: measurements),
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
