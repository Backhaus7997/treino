import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../workout/presentation/workout_strings.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../chat/application/chat_providers.dart';
import '../../measurements/application/measurement_providers.dart';
import '../../measurements/presentation/log_measurement_screen.dart';
import '../../measurements/presentation/widgets/measurement_progress_chart.dart';
import '../../performance/application/performance_test_providers.dart';
import '../../performance/presentation/log_performance_test_screen.dart';
import '../../performance/presentation/widgets/performance_progress_chart.dart';
import '../../profile/application/user_public_profile_providers.dart';
import '../../workout/application/assigned_routine_providers.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../workout/domain/routine.dart';
import 'coach_strings.dart';

/// Trainer's drill-down view for a specific athlete.
///
/// Shows the athlete header (avatar + displayName) and all plans assigned by
/// the current trainer to this athlete. Provides a "CREAR PLAN" CTA that
/// navigates to the RoutineEditorScreen.
///
/// Lives under ShellRoute — NO own Scaffold (bottom bar provided by shell).
/// REQ-COACH-PLANS-020, 021, 022 · SCENARIO-454, 455, 456.
class AthleteDetailScreen extends ConsumerWidget {
  const AthleteDetailScreen({super.key, required this.athleteId});

  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final trainerUid = ref.watch(currentUidProvider) ?? '';

    final profileAsync = ref.watch(userPublicProfileProvider(athleteId));
    final plansAsync = ref.watch(assignedRoutinesProvider(athleteId));

    return Column(
      children: [
        // ── Header bar ────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
          child: Row(
            children: [
              IconButton(
                icon: Icon(TreinoIcon.back, color: palette.textPrimary),
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/coach'),
              ),
              const SizedBox(width: 4),
              profileAsync.maybeWhen(
                data: (profile) => Text(
                  profile?.displayName ?? '...',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: palette.textPrimary,
                  ),
                ),
                orElse: () => Text(
                  '...',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Body ─────────────────────────────────────────────────────────
        Expanded(
          child: _AthleteDetailBody(
            athleteId: athleteId,
            trainerUid: trainerUid,
            profileAsync: profileAsync,
            plansAsync: plansAsync,
          ),
        ),
      ],
    );
  }
}

class _AthleteDetailBody extends ConsumerWidget {
  const _AthleteDetailBody({
    required this.athleteId,
    required this.trainerUid,
    required this.profileAsync,
    required this.plansAsync,
  });

  final String athleteId;
  final String trainerUid;
  final AsyncValue<dynamic> profileAsync;
  final AsyncValue<List<Routine>> plansAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);

    if (profileAsync.isLoading || plansAsync.isLoading) {
      return Center(
        child: CircularProgressIndicator(color: palette.accent),
      );
    }

    if (profileAsync.hasError) {
      return Center(
        child: Text(
          'No pudimos cargar este perfil.',
          style: GoogleFonts.barlow(color: palette.textMuted, fontSize: 14),
        ),
      );
    }

    if (plansAsync.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Error cargando planes:',
                style:
                    GoogleFonts.barlow(color: palette.textMuted, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Text(
                plansAsync.error.toString(),
                style:
                    GoogleFonts.barlow(color: palette.textMuted, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Client-side filter: only show plans assigned by current trainer
    final allPlans = plansAsync.valueOrNull ?? const [];
    final myPlans = allPlans.where((r) => r.assignedBy == trainerUid).toList();

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            children: [
              // ── Athlete header ──────────────────────────────────────
              _AthleteHeader(profileAsync: profileAsync),
              const SizedBox(height: 20),

              // ── Planes section ──────────────────────────────────────
              Text(
                'PLANES ASIGNADOS',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              if (myPlans.isEmpty)
                Text(
                  CoachStrings.athleteDetailNoPlans,
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 14,
                    color: palette.textMuted,
                  ),
                )
              else
                for (final plan in myPlans) ...[
                  _PlanCard(
                    plan: plan,
                    onTap: () => context.push('/workout/routine/${plan.id}'),
                  ),
                  const SizedBox(height: 12),
                ],

              // ── Antropometría section ────────────────────────────────
              const SizedBox(height: 8),
              _AntropometriaSection(athleteId: athleteId),

              // ── Rendimiento section ──────────────────────────────────
              const SizedBox(height: 20),
              _RendimientoSection(athleteId: athleteId),
            ],
          ),
        ),

        // ── MENSAJE + CREAR PLAN buttons ──────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _onMessage(context, ref),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: palette.accent, width: 1),
                    foregroundColor: palette.accent,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                  icon: Icon(TreinoIcon.chat, size: 18, color: palette.accent),
                  label: Text(
                    'MENSAJE',
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      context.push('/workout/routine-editor/$athleteId'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: palette.bg,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9999),
                    ),
                  ),
                  child: Text(
                    CoachStrings.createPlanCta,
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _onMessage(BuildContext context, WidgetRef ref) async {
    if (trainerUid.isEmpty) return;
    try {
      final chat = await ref.read(chatRepositoryProvider).getOrCreate(
            selfId: trainerUid,
            otherId: athleteId,
          );
      if (!context.mounted) return;
      context.push('/coach/chat/${chat.chatId}?other=$athleteId');
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No pudimos abrir el chat. Probá de nuevo.'),
        ),
      );
    }
  }
}

// ── Athlete header ─────────────────────────────────────────────────────────────

class _AthleteHeader extends StatelessWidget {
  const _AthleteHeader({required this.profileAsync});
  final AsyncValue<dynamic> profileAsync;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final profile = profileAsync.valueOrNull;
    final name = (profile != null) ? (profile.displayName ?? '...') : '...';

    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.bg,
            border: Border.all(color: palette.border, width: 1),
          ),
          alignment: Alignment.center,
          child:
              Icon(TreinoIcon.tabProfile, size: 28, color: palette.textMuted),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Text(
            name,
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w600,
              fontSize: 18,
              color: palette.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Antropometría section ─────────────────────────────────────────────────────

const _kMonthsShort = <String>[
  '',
  'ene',
  'feb',
  'mar',
  'abr',
  'may',
  'jun',
  'jul',
  'ago',
  'sep',
  'oct',
  'nov',
  'dic',
];

String _formatMeasurementDate(DateTime dt) {
  // Dates are stored UTC; display as-is (no .toLocal()) — same UTC convention
  // used across the dashboard (see appointment_detail_sheet.dart).
  return '${dt.day} ${_kMonthsShort[dt.month]} ${dt.year}';
}

/// Section that shows the latest anthropometric measurement for [athleteId]
/// and a '+ Cargar' CTA to open the log form.
///
/// Non-empty state: shows a summary card with the most recent measurement
/// (list is sorted ASC, so latest = last). Only non-null key metrics are shown.
/// A count line indicates total measurements recorded.
///
/// When ≥2 measurements exist a PROGRESO chart card is rendered below the
/// summary card (TANDA-3). With <2 measurements a muted hint card is shown.
class _AntropometriaSection extends ConsumerWidget {
  const _AntropometriaSection({required this.athleteId});

  final String athleteId;

  void _openLogForm(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => LogMeasurementScreen(athleteId: athleteId),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final measurementsAsync =
        ref.watch(measurementsForAthleteProvider(athleteId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header row ─────────────────────────────────────────────
        Row(
          children: [
            Text(
              'ANTROPOMETRÍA',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 1.2,
                color: palette.textMuted,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => _openLogForm(context),
              child: Text(
                '+ Cargar',
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: palette.accent,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Async content ──────────────────────────────────────────────────
        measurementsAsync.when(
          loading: () => _card(
            palette: palette,
            child: Text(
              'Cargando…',
              style: GoogleFonts.barlow(
                fontSize: 13,
                color: palette.textMuted,
              ),
            ),
          ),
          error: (_, __) => _card(
            palette: palette,
            child: Text(
              'No pudimos cargar las medidas.',
              style: GoogleFonts.barlow(
                fontSize: 13,
                color: palette.textMuted,
              ),
            ),
          ),
          data: (measurements) {
            if (measurements.isEmpty) {
              return _card(
                palette: palette,
                child: Text(
                  'Sin mediciones todavía. Cargá la primera.',
                  style: GoogleFonts.barlow(
                    fontSize: 13,
                    color: palette.textMuted,
                  ),
                ),
              );
            }

            // List sorted ASC → latest is last
            final latest = measurements.last;
            final count = measurements.length;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Latest-measurement summary card ────────────────────
                _card(
                  palette: palette,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Date
                      Text(
                        _formatMeasurementDate(latest.recordedAt),
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: palette.textPrimary,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Key metrics (non-null only)
                      _MetricRow(
                        metrics: [
                          if (latest.weightKg != null)
                            _Metric(
                              'Peso',
                              '${latest.weightKg} kg',
                            ),
                          if (latest.fatPercentage != null)
                            _Metric(
                              '% Graso',
                              '${latest.fatPercentage}%',
                            ),
                          if (latest.muscleMassKg != null)
                            _Metric(
                              'Masa muscular',
                              '${latest.muscleMassKg} kg',
                            ),
                          if (latest.waistCm != null)
                            _Metric(
                              'Cintura',
                              '${latest.waistCm} cm',
                            ),
                        ],
                        palette: palette,
                      ),

                      const SizedBox(height: 8),
                      Text(
                        '$count ${count == 1 ? 'medición registrada' : 'mediciones registradas'}',
                        style: GoogleFonts.barlow(
                          fontSize: 12,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Progress chart (TANDA-3) ───────────────────────────
                const SizedBox(height: 12),
                if (measurements.length >= 2)
                  MeasurementProgressChart(measurements: measurements)
                else
                  _card(
                    palette: palette,
                    child: Text(
                      'Cargá otra medición para ver el progreso.',
                      style: GoogleFonts.barlow(
                        fontSize: 13,
                        color: palette.textMuted,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _card({required AppPalette palette, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: child,
    );
  }
}

// ── Metric data ───────────────────────────────────────────────────────────────

class _Metric {
  const _Metric(this.label, this.value);
  final String label;
  final String value;
}

// ── Metric row ────────────────────────────────────────────────────────────────

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.metrics, required this.palette});

  final List<_Metric> metrics;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    if (metrics.isEmpty) {
      return Text(
        'Sin datos de composición.',
        style: GoogleFonts.barlow(fontSize: 12, color: palette.textMuted),
      );
    }
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children:
          metrics.map((m) => _MetricChip(metric: m, palette: palette)).toList(),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.metric, required this.palette});

  final _Metric metric;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          metric.label,
          style: GoogleFonts.barlow(
            fontSize: 12,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          metric.value,
          style: GoogleFonts.barlow(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ── Rendimiento section ───────────────────────────────────────────────────────

/// Section that shows the latest performance test for [athleteId]
/// and a '+ Cargar' CTA to open the log form.
///
/// Non-empty state: shows a summary card with the most recent test
/// (list is sorted ASC, so latest = last). Only non-null key metrics shown.
/// A count line indicates total tests recorded.
///
/// When ≥2 tests exist a PROGRESO chart card is rendered below the summary
/// card. With <2 tests a muted hint card is shown.
class _RendimientoSection extends ConsumerWidget {
  const _RendimientoSection({required this.athleteId});

  final String athleteId;

  void _openLogForm(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => LogPerformanceTestScreen(athleteId: athleteId),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final testsAsync = ref.watch(performanceTestsForAthleteProvider(athleteId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header row ─────────────────────────────────────────────
        Row(
          children: [
            Text(
              'RENDIMIENTO',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 1.2,
                color: palette.textMuted,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => _openLogForm(context),
              child: Text(
                '+ Cargar',
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: palette.accent,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Async content ──────────────────────────────────────────────────
        testsAsync.when(
          loading: () => _card(
            palette: palette,
            child: Text(
              'Cargando…',
              style: GoogleFonts.barlow(
                fontSize: 13,
                color: palette.textMuted,
              ),
            ),
          ),
          error: (_, __) => _card(
            palette: palette,
            child: Text(
              'No pudimos cargar las evaluaciones.',
              style: GoogleFonts.barlow(
                fontSize: 13,
                color: palette.textMuted,
              ),
            ),
          ),
          data: (tests) {
            if (tests.isEmpty) {
              return _card(
                palette: palette,
                child: Text(
                  'Sin evaluaciones todavía. Cargá la primera.',
                  style: GoogleFonts.barlow(
                    fontSize: 13,
                    color: palette.textMuted,
                  ),
                ),
              );
            }

            // List sorted ASC → latest is last
            final latest = tests.last;
            final count = tests.length;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Latest-test summary card ───────────────────────────
                _card(
                  palette: palette,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Date
                      Text(
                        _formatMeasurementDate(latest.recordedAt),
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: palette.textPrimary,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Key metrics (non-null only)
                      _MetricRow(
                        metrics: [
                          if (latest.cmjCm != null)
                            _Metric('CMJ', '${latest.cmjCm} cm'),
                          if (latest.squat1rmKg != null)
                            _Metric(
                                'Sentadilla 1RM', '${latest.squat1rmKg} kg'),
                          if (latest.sprint20mS != null)
                            _Metric('Sprint 20m', '${latest.sprint20mS} s'),
                          if (latest.vo2maxMlKgMin != null)
                            _Metric(
                                'VO2máx', '${latest.vo2maxMlKgMin} ml/kg/min'),
                        ],
                        palette: palette,
                      ),

                      const SizedBox(height: 8),
                      Text(
                        '$count ${count == 1 ? 'evaluación registrada' : 'evaluaciones registradas'}',
                        style: GoogleFonts.barlow(
                          fontSize: 12,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Progress chart ─────────────────────────────────────
                const SizedBox(height: 12),
                if (tests.length >= 2)
                  PerformanceProgressChart(tests: tests)
                else
                  _card(
                    palette: palette,
                    child: Text(
                      'Cargá otra evaluación para ver el progreso.',
                      style: GoogleFonts.barlow(
                        fontSize: 13,
                        color: palette.textMuted,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _card({required AppPalette palette, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: child,
    );
  }
}

// ── Plan card ─────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, this.onTap});
  final Routine plan;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border, width: 1),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plan.name,
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${plan.days.length} ${plan.days.length == 1 ? "día" : "días"} · ${plan.split ?? WorkoutStrings.splitFallback}',
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w400,
                fontSize: 12,
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
