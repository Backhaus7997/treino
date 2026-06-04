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
import '../application/athlete_note_providers.dart';
import '../domain/athlete_note.dart';
import '../../payments/application/billing_providers.dart';
import '../../payments/domain/athlete_billing.dart';
import '../../performance/application/performance_test_providers.dart';
import '../../performance/presentation/log_performance_test_screen.dart';
import '../../performance/presentation/widgets/performance_progress_chart.dart';
import '../../profile/application/user_providers.dart' show userProfileProvider;
import '../../profile/application/user_public_profile_providers.dart';
import '../../workout/application/assigned_routine_providers.dart';
import '../../workout/application/routine_providers.dart'
    show routineRepositoryProvider;
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
                    onDelete: () => _onDeletePlan(context, ref, plan),
                  ),
                  const SizedBox(height: 12),
                ],

              // ── Antropometría section ────────────────────────────────
              const SizedBox(height: 8),
              _AntropometriaSection(athleteId: athleteId),

              // ── Rendimiento section ──────────────────────────────────
              const SizedBox(height: 20),
              _RendimientoSection(athleteId: athleteId),

              // ── Cobro section ─────────────────────────────────────────
              const SizedBox(height: 20),
              _CobroSection(athleteId: athleteId),

              // ── Nota del alumno section ───────────────────────────────
              const SizedBox(height: 20),
              _NotaSection(athleteId: athleteId, trainerUid: trainerUid),
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

  /// Confirms then deletes a plan the trainer assigned to this athlete, and
  /// refreshes the list (the provider is a Future, so it needs an explicit
  /// invalidate — unlike the templates stream).
  Future<void> _onDeletePlan(
      BuildContext context, WidgetRef ref, Routine plan) async {
    final palette = AppPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.bgCard,
        title: Text(
          'Eliminar plan',
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
        content: Text(
          '¿Eliminar "${plan.name}" de este alumno? Esta acción no se puede deshacer.',
          style: GoogleFonts.barlow(fontSize: 13, color: palette.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.barlowCondensed(color: palette.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Eliminar',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                color: palette.danger,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(routineRepositoryProvider).deleteRoutine(plan.id);
      ref.invalidate(assignedRoutinesProvider(athleteId));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan eliminado.')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos eliminar el plan.')),
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

// ── Cobro section ─────────────────────────────────────────────────────────────

const _kCadenceLabels = {
  BillingCadence.mensual: 'Mensual',
  BillingCadence.semanal: 'Semanal',
  BillingCadence.porSesion: 'Por sesión',
  BillingCadence.suelto: 'Suelto',
};

class _CobroSection extends ConsumerWidget {
  const _CobroSection({required this.athleteId});

  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final billingAsync = ref.watch(athleteBillingProvider(athleteId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header row ──────────────────────────────────────────
        Row(
          children: [
            Text(
              'COBRO',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 1.2,
                color: palette.textMuted,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () =>
                  _openConfigSheet(context, ref, billingAsync.valueOrNull),
              child: Text(
                billingAsync.valueOrNull == null ? 'Configurar' : 'Editar',
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

        // ── Content ─────────────────────────────────────────────────────
        billingAsync.when(
          loading: () => _card(
            palette: palette,
            child: Text(
              'Cargando…',
              style: GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
            ),
          ),
          error: (_, __) => _card(
            palette: palette,
            child: Text(
              'No pudimos cargar la config de cobro.',
              style: GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
            ),
          ),
          data: (billing) => _card(
            palette: palette,
            child: billing == null
                ? Text(
                    'Sin configurar.',
                    style: GoogleFonts.barlow(
                        fontSize: 13, color: palette.textMuted),
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Text(
                          '\$${billing.amountArs} ARS',
                          style: GoogleFonts.barlow(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        _kCadenceLabels[billing.cadence] ??
                            billing.cadence.name,
                        style: GoogleFonts.barlow(
                          fontSize: 13,
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  void _openConfigSheet(
    BuildContext context,
    WidgetRef ref,
    AthleteBilling? existing,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.of(context).bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _CobroConfigSheet(
        athleteId: athleteId,
        existing: existing,
        ref: ref,
      ),
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

class _CobroConfigSheet extends ConsumerStatefulWidget {
  const _CobroConfigSheet({
    required this.athleteId,
    required this.existing,
    required this.ref,
  });

  final String athleteId;
  final AthleteBilling? existing;
  final WidgetRef ref;

  @override
  ConsumerState<_CobroConfigSheet> createState() => _CobroConfigSheetState();
}

class _CobroConfigSheetState extends ConsumerState<_CobroConfigSheet> {
  late final TextEditingController _priceController;
  late BillingCadence _cadence;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final trainerRate =
        widget.ref.read(userProfileProvider).valueOrNull?.trainerMonthlyRate;
    final initialAmount = widget.existing?.amountArs ?? trainerRate ?? 0;
    _priceController =
        TextEditingController(text: initialAmount > 0 ? '$initialAmount' : '');
    _cadence = widget.existing?.cadence ?? BillingCadence.mensual;
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final amount = int.tryParse(_priceController.text.trim());
    if (amount == null || amount <= 0) return;

    final trainerId = ref.read(currentUidProvider);
    if (trainerId == null) return;

    setState(() => _saving = true);
    try {
      await ref.read(billingRepositoryProvider).setConfig(
            AthleteBilling(
              trainerId: trainerId,
              athleteId: widget.athleteId,
              amountArs: amount,
              cadence: _cadence,
              updatedAt: DateTime.now().toUtc(),
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos guardar. Probá de nuevo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Handle ──────────────────────────────────────────────────
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'CONFIGURAR COBRO',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: palette.textPrimary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 18),

          // ── Precio ──────────────────────────────────────────────────
          Text(
            'PRECIO (ARS)',
            style: GoogleFonts.barlowCondensed(
              color: palette.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _priceController,
            keyboardType: TextInputType.number,
            style: TextStyle(color: palette.textPrimary),
            decoration: InputDecoration(
              hintText: 'Ej: 7000',
              hintStyle: TextStyle(color: palette.textMuted),
              filled: true,
              fillColor: palette.bg,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: palette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: palette.accent, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // ── Cadencia chips ───────────────────────────────────────────
          Text(
            'CADENCIA',
            style: GoogleFonts.barlowCondensed(
              color: palette.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: BillingCadence.values.map((c) {
              final selected = _cadence == c;
              return ChoiceChip(
                label: Text(_kCadenceLabels[c] ?? c.name),
                selected: selected,
                onSelected: (_) => setState(() => _cadence = c),
                selectedColor: palette.accent,
                backgroundColor: palette.bgCard,
                labelStyle: TextStyle(
                  color: selected ? palette.bg : palette.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
                side: BorderSide(
                  color: selected ? palette.accent : palette.border,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // ── Save button ──────────────────────────────────────────────
          ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.accent,
              foregroundColor: palette.bg,
              minimumSize: const Size.fromHeight(48),
              shape: const StadiumBorder(),
              disabledBackgroundColor: palette.accent.withValues(alpha: 0.3),
            ),
            child: _saving
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.bg,
                    ),
                  )
                : Text(
                    'GUARDAR',
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: 1.4,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Nota del alumno section ───────────────────────────────────────────────────

class _NotaSection extends ConsumerWidget {
  const _NotaSection({required this.athleteId, required this.trainerUid});

  final String athleteId;
  final String trainerUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final noteAsync = ref.watch(
      athleteNoteProvider((trainerId: trainerUid, athleteId: athleteId)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header row ──────────────────────────────────────────
        Row(
          children: [
            Text(
              'NOTA DEL ALUMNO',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 1.2,
                color: palette.textMuted,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => _openEditSheet(context, ref, noteAsync.valueOrNull),
              child: Text(
                noteAsync.valueOrNull == null ? 'Agregar' : 'Editar',
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

        // ── Content ─────────────────────────────────────────────────────
        noteAsync.when(
          loading: () => _card(
            palette: palette,
            child: Text(
              'Cargando…',
              style: GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
            ),
          ),
          error: (_, __) => _card(
            palette: palette,
            child: Text(
              'No pudimos cargar la nota.',
              style: GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
            ),
          ),
          data: (note) => _card(
            palette: palette,
            child: note == null || note.note.trim().isEmpty
                ? Text(
                    'Sin nota.',
                    style: GoogleFonts.barlow(
                        fontSize: 13, color: palette.textMuted),
                  )
                : Text(
                    note.note,
                    style: GoogleFonts.barlow(
                      fontSize: 14,
                      color: palette.textPrimary,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  void _openEditSheet(
    BuildContext context,
    WidgetRef ref,
    AthleteNote? existing,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.of(context).bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _NotaEditSheet(
        athleteId: athleteId,
        trainerUid: trainerUid,
        existing: existing,
      ),
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

class _NotaEditSheet extends ConsumerStatefulWidget {
  const _NotaEditSheet({
    required this.athleteId,
    required this.trainerUid,
    required this.existing,
  });

  final String athleteId;
  final String trainerUid;
  final AthleteNote? existing;

  @override
  ConsumerState<_NotaEditSheet> createState() => _NotaEditSheetState();
}

class _NotaEditSheetState extends ConsumerState<_NotaEditSheet> {
  late final TextEditingController _noteController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.existing?.note ?? '');
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(athleteNoteRepositoryProvider).setNote(
            AthleteNote(
              trainerId: widget.trainerUid,
              athleteId: widget.athleteId,
              note: _noteController.text.trim(),
              updatedAt: DateTime.now().toUtc(),
            ),
          );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos guardar. Probá de nuevo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Handle ──────────────────────────────────────────────────
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'NOTA DEL ALUMNO',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 18,
              color: palette.textPrimary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 18),

          // ── Nota field ───────────────────────────────────────────────
          TextField(
            controller: _noteController,
            maxLines: 5,
            style: TextStyle(color: palette.textPrimary),
            decoration: InputDecoration(
              hintText: 'Ej: viene de lesión de rodilla, no cargar piernas…',
              hintStyle: TextStyle(color: palette.textMuted),
              filled: true,
              fillColor: palette.bg,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: palette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: palette.accent, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Save button ──────────────────────────────────────────────
          ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.accent,
              foregroundColor: palette.bg,
              minimumSize: const Size.fromHeight(48),
              shape: const StadiumBorder(),
              disabledBackgroundColor: palette.accent.withValues(alpha: 0.3),
            ),
            child: _saving
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.bg,
                    ),
                  )
                : Text(
                    'GUARDAR',
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: 1.4,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Plan card ─────────────────────────────────────────────────────────────────

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, this.onTap, this.onDelete});
  final Routine plan;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

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
        child: Row(
          children: [
            Expanded(
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
            if (onDelete != null)
              IconButton(
                onPressed: onDelete,
                icon:
                    Icon(TreinoIcon.trash, size: 18, color: palette.textMuted),
                tooltip: 'Eliminar plan',
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.only(left: 8),
              ),
          ],
        ),
      ),
    );
  }
}
