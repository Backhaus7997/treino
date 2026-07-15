import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../measurements/application/measurement_providers.dart';
import '../../measurements/presentation/log_measurement_screen.dart';
import '../../measurements/presentation/widgets/measurement_progress_chart.dart';
import '../../profile/application/user_providers.dart' show userProfileProvider;

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
/// [athlete-self-measurements] El alumno también CARGA sus propias medidas
/// desde acá (botón "+" → [LogMeasurementScreen.selfLog]). Su entrenador
/// vinculado las ve con vínculo activo + consentimiento (gate dual
/// session_shares ∧ profile_shares en la regla de lectura). El empty state
/// sigue hablando de la EVOLUCIÓN que registra el PF.
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

    // Peso y altura ya cargados en el onboarding (Step 4 → UserProfile). El
    // atleta no debería recargarlos: se consumen del perfil. `userProfileProvider`
    // lee el perfil del usuario autenticado (owner-read), que en esta pantalla
    // es el propio alumno. `.valueOrNull` porque la tarjeta es secundaria: si
    // el perfil aún carga, simplemente no aparece todavía (no bloquea el chart).
    final profile = ref.watch(userProfileProvider).valueOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          title: l10n.measurementsScreenTitle,
          addTooltip: l10n.measurementsAddSelfLog,
        ),
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
                  // ── TUS DATOS (peso + altura del perfil) ──────────────
                  // Reutiliza lo del onboarding. La ALTURA sólo vive acá: no
                  // está en el modelo Measurement (es un dato estable, no una
                  // serie), así que nunca se recarga como medición.
                  if (profile != null &&
                      (profile.bodyWeightKg != null ||
                          profile.heightCm != null)) ...[
                    _ProfileDataCard(
                      title: l10n.measurementsProfileCardTitle,
                      hint: l10n.measurementsProfileCardHint,
                      weightLabel: l10n.measurementsWeightLabel,
                      heightLabel: l10n.measurementsHeightLabel,
                      weightKg: profile.bodyWeightKg,
                      heightCm: profile.heightCm,
                    ),
                    const SizedBox(height: 14),
                  ],

                  // ── EVOLUCIÓN (mediciones del entrenador en el tiempo) ─
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
  const _Header({required this.title, required this.addTooltip});

  final String title;

  /// Tooltip del botón "+" que abre el formulario de auto-carga.
  final String addTooltip;

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
          // [athlete-self-measurements] El alumno carga su propia medición.
          IconButton(
            icon: Icon(TreinoIcon.plus, color: palette.accent),
            tooltip: addTooltip,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => const LogMeasurementScreen.selfLog(),
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

// ── Profile data card (peso + altura del onboarding) ──────────────────────────

/// Muestra el peso y la altura que el atleta ya cargó en el onboarding, para
/// que no tenga que recargarlos. Se editan desde el Perfil, no acá — de ahí el
/// [hint]. Cada valor sólo se muestra si existe (el onboarding los pide, pero
/// un doc viejo podría no tenerlos).
class _ProfileDataCard extends StatelessWidget {
  const _ProfileDataCard({
    required this.title,
    required this.hint,
    required this.weightLabel,
    required this.heightLabel,
    required this.weightKg,
    required this.heightCm,
  });

  final String title;
  final String hint;
  final String weightLabel;
  final String heightLabel;
  final double? weightKg;
  final int? heightCm;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              if (weightKg != null)
                Expanded(
                  child: _Stat(
                    label: weightLabel,
                    value: '${_trimNum(weightKg!)} kg',
                    palette: palette,
                  ),
                ),
              if (weightKg != null && heightCm != null)
                const SizedBox(width: 12),
              if (heightCm != null)
                Expanded(
                  child: _Stat(
                    label: heightLabel,
                    value: '$heightCm cm',
                    palette: palette,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            hint,
            style: GoogleFonts.barlow(fontSize: 11, color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(
      {required this.label, required this.value, required this.palette});

  final String label;
  final String value;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 11,
            letterSpacing: 0.6,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 22,
            color: palette.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// `80.0` → `80`, `78.5` → `78.5`. Mismo criterio que las stat cards del radar.
String _trimNum(double v) =>
    v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

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
