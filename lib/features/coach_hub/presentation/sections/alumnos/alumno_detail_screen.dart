import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/chat/application/chat_providers.dart';
import 'package:treino/features/coach/application/athlete_file_providers.dart';
import 'package:treino/features/coach/application/athlete_note_providers.dart';
import 'package:treino/features/coach/application/follow_up_entry_providers.dart';
import 'package:treino/features/coach/application/nutrition_plan_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/athlete_file_repository.dart';
import 'package:treino/features/coach/domain/athlete_file.dart';
import 'package:treino/features/coach/domain/athlete_note.dart';
import 'package:treino/features/coach/domain/follow_up_entry.dart';
import 'package:treino/features/coach/domain/nutrition_plan.dart';
import 'package:treino/features/coach/domain/nutrition_plan_presets.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/chat/widgets/chat_detail_pane.dart';
import 'package:treino/features/gyms/application/gym_providers.dart';
import 'package:treino/features/measurements/application/measurement_providers.dart';
import 'package:treino/features/measurements/domain/measurement.dart';
import 'package:treino/features/measurements/presentation/widgets/measurement_progress_chart.dart';
import 'package:treino/features/payments/application/billing_providers.dart';
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart';
import 'package:treino/features/payments/application/payment_providers.dart';
import 'package:treino/features/payments/domain/athlete_billing.dart';
import 'package:treino/features/performance/application/performance_test_providers.dart';
import 'package:treino/features/performance/domain/performance_test.dart';
import 'package:treino/features/performance/presentation/widgets/performance_progress_chart.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/exercise_progression_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_status.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_progression_chart.dart';
import 'package:treino/features/workout/presentation/widgets/session_exercise_block.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../pagos/widgets/estado_cuenta_card.dart';
import '../pagos/widgets/marcar_pagado_actions.dart';
import '../pagos/widgets/pagos_table.dart';
import '../pagos/widgets/payment_format.dart';
import 'alumnos_screen.dart' show AlumnoEstado, AlumnoEstadoX, estadoForLink;
import 'resumen_metrics.dart';

/// Detalle del alumno (`/alumnos/:id`, Fase W2 PR2).
///
/// Header (identidad + estado + métricas denormalizadas) + tab bar de 10
/// secciones. En PR2 sólo **Progreso › Antropometría** está implementado
/// (reusa `measurementsForAthleteProvider` + `MeasurementProgressChart`); el
/// resto de tabs son placeholder. Rendimiento (performance), Nutrición,
/// Historial, Notas, Archivos, Seguimiento y los botones de acción del header
/// llegan en PRs siguientes (varios necesitan backend nuevo / l10n en
/// CoachHubApp). Renderiza DENTRO del shell — sin Scaffold (ADR-CHW-005).
class AlumnoDetailScreen extends ConsumerWidget {
  const AlumnoDetailScreen({super.key, required this.athleteId});

  final String athleteId;

  static const _tabs = <String>[
    'Resumen', // i18n: Fase W2
    'Entrenamientos',
    'Nutrición',
    'Progreso',
    'Pagos',
    'Historial',
    'Chat',
    'Notas privadas',
    'Archivos',
    'Seguimiento',
    'Mediciones',
  ];
  static const _resumenIndex = 0;
  static const _entrenamientoIndex = 1;
  static const _nutricionIndex = 2;
  static const _progresoIndex = 3;
  static const _pagosIndex = 4;
  static const _historialIndex = 5;
  static const _chatIndex = 6;
  static const _notasPrivadasIndex = 7;
  static const _archivosIndex = 8;
  static const _seguimientoIndex = 9;
  static const _medicionesIndex = 10;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final profile = ref.watch(userPublicProfileProvider(athleteId)).valueOrNull;
    // Mismo criterio que el roster: el link más reciente NO-pending del alumno
    // (el stream viene requestedAt DESC). Sin el filtro de pending, un alumno
    // re-vinculado mostraría estados contradictorios entre roster y detalle.
    final link = ref
        .watch(trainerLinksStreamProvider)
        .valueOrNull
        ?.where((l) =>
            l.athleteId == athleteId && l.status != TrainerLinkStatus.pending)
        .firstOrNull;
    final conDeudaIds = <String>{
      for (final c in ref.watch(pagosPorCobrarProvider).valueOrNull ?? const [])
        c.athleteId,
    };
    final estado = link == null ? null : estadoForLink(link, conDeudaIds);
    final gymId = profile?.gymId;
    final gymName = gymId == null
        ? null
        : ref.watch(gymByIdProvider(gymId)).valueOrNull?.name;
    final billing = ref.watch(athleteBillingProvider(athleteId)).valueOrNull;

    return DefaultTabController(
      length: _tabs.length,
      initialIndex: _resumenIndex,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _BackLink(palette: palette),
                const SizedBox(height: 12),
                _Header(
                  profile: profile,
                  link: link,
                  estado: estado,
                  gymName: gymName,
                  billing: billing,
                  onPago: () => registrarPago(context, ref, athleteId),
                  palette: palette,
                ),
                const SizedBox(height: 14),
                _Tabs(palette: palette, labels: _tabs),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < _tabs.length; i++)
                  if (i == _resumenIndex)
                    _ResumenTab(athleteId: athleteId)
                  else if (i == _entrenamientoIndex)
                    _EntrenamientoTab(athleteId: athleteId)
                  else if (i == _nutricionIndex)
                    _NutricionTab(athleteId: athleteId)
                  else if (i == _progresoIndex)
                    _ProgresoTab(athleteId: athleteId)
                  else if (i == _pagosIndex)
                    _PagosTab(athleteId: athleteId)
                  else if (i == _historialIndex)
                    _HistorialTab(athleteId: athleteId)
                  else if (i == _chatIndex)
                    _ChatTab(athleteId: athleteId)
                  else if (i == _notasPrivadasIndex)
                    _NotasPrivadasTab(athleteId: athleteId)
                  else if (i == _archivosIndex)
                    _ArchivosTab(athleteId: athleteId)
                  else if (i == _seguimientoIndex)
                    _SeguimientoTab(athleteId: athleteId)
                  else if (i == _medicionesIndex)
                    _MedicionesTab(athleteId: athleteId)
                  else
                    const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BackLink extends StatelessWidget {
  const _BackLink({required this.palette});
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.go('/alumnos'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(TreinoIcon.chevronLeft, size: 16, color: palette.textMuted),
          const SizedBox(width: 4),
          Text(
            'Alumnos', // i18n: Fase W2
            style: TextStyle(color: palette.textMuted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.profile,
    required this.link,
    required this.estado,
    required this.gymName,
    required this.billing,
    required this.onPago,
    required this.palette,
  });

  final UserPublicProfile? profile;
  final TrainerLink? link;
  final AlumnoEstado? estado;
  final String? gymName;
  final AthleteBilling? billing;
  final VoidCallback onPago;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final name = profile?.displayName ?? 'Atleta'; // i18n: Fase W2
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final sesiones = profile?.workoutsCount ?? 0;
    final racha = profile?.racha ?? 0;
    final avatarUrl = profile?.avatarUrl;
    final desde = link?.acceptedAt;
    final b = billing;
    // .toUtc() para compartir reloj con el pipeline de billing (monthKey/weekKey
    // de pagosPorCobrarProvider y las escrituras usan UTC); evita un desfase de
    // 1 día en el borde del período en AR (UTC-3).
    final proxCobro = b == null ? null : nextDueDate(b, DateTime.now().toUtc());

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: palette.bg,
                backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                    ? NetworkImage(avatarUrl)
                    : null,
                child: (avatarUrl == null || avatarUrl.isEmpty)
                    ? Text(initial,
                        style: TextStyle(
                            color: palette.accent,
                            fontSize: 20,
                            fontWeight: FontWeight.w700))
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (estado != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _Dot(color: estado!.color(palette)),
                              const SizedBox(width: 6),
                              Text(
                                estado!.label(AppL10n.of(context)),
                                style: TextStyle(
                                    color: estado!.color(palette),
                                    fontSize: 13),
                              ),
                            ],
                          ),
                        if (gymName != null)
                          Text(
                            gymName!,
                            style: TextStyle(
                                color: palette.textMuted, fontSize: 13),
                          ),
                        if (desde != null)
                          Text(
                            'Desde ${fmtDate(desde)}', // i18n: Fase W2
                            style: TextStyle(
                                color: palette.textMuted, fontSize: 13),
                          ),
                        if (b != null && b.cadence != BillingCadence.suelto)
                          Text(
                            '${fmtArs(b.amountArs)} · ${_cadenciaLabel(b.cadence)}', // i18n: Fase W2
                            style: TextStyle(
                                color: palette.textMuted, fontSize: 13),
                          ),
                        if (proxCobro != null)
                          Text(
                            'Próx. cobro: ${fmtDayMonth(proxCobro)}', // i18n: Fase W2
                            style: TextStyle(
                                color: palette.textMuted, fontSize: 13),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: onPago,
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.accent,
                  side: BorderSide(color: palette.border),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Pago', // i18n: Fase W2
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _MetricChip(
                  label: 'Sesiones',
                  value: '$sesiones',
                  palette: palette), // i18n: Fase W2
              const SizedBox(width: 10),
              _MetricChip(
                  label: 'Racha',
                  value: '$racha d',
                  palette: palette), // i18n: Fase W2
            ],
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}

class _MetricChip extends StatelessWidget {
  const _MetricChip(
      {required this.label, required this.value, required this.palette});
  final String label;
  final String value;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: palette.bg,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: palette.textMuted, fontSize: 11)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.palette, required this.labels});
  final AppPalette palette;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: palette.border),
      ),
      child: TabBar(
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: palette.accent,
          borderRadius: BorderRadius.circular(20),
        ),
        splashBorderRadius: BorderRadius.circular(20),
        labelColor: palette.bg,
        unselectedLabelColor: palette.textMuted,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontSize: 13),
        tabs: [for (final l in labels) Tab(text: l, height: 38)],
      ),
    );
  }
}

/// Tab «Chat» del Alumno detalle: reusa el [ChatDetailPane] del chat web
/// global (split-pane sidebar), resolviendo el [Chat] entre PF y este alumno
/// puntual vía [chatForOtherUidProvider]. Sin lista de conversaciones — el
/// alumno YA está fijado por el route, no hay nada que elegir.
///
/// V1 (2026-06-30): solo texto. La V2 con media reusa el mismo upgrade que
/// la sección de chat global del sidebar.
class _ChatTab extends ConsumerWidget {
  const _ChatTab({required this.athleteId});
  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final chatAsync = ref.watch(chatForOtherUidProvider(athleteId));
    return chatAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
      error: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Text(
          'No pudimos abrir el chat. Reintentá.', // i18n: Fase W2
          style: TextStyle(color: palette.textMuted, fontSize: 15),
        ),
      ),
      data: (chat) => ChatDetailPane(chatId: chat.chatId),
    );
  }
}

class _ProgresoTab extends ConsumerWidget {
  const _ProgresoTab({required this.athleteId});
  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final measAsync = ref.watch(measurementsForAthleteProvider(athleteId));
    final perfAsync = ref.watch(performanceTestsForAthleteProvider(athleteId));

    // Antropometría y Rendimiento son fuentes independientes: gateamos juntas
    // (spinner hasta que ambas tengan valor, error si alguna falla) y mostramos
    // cada sección por separado según haya datos.
    if (measAsync.isLoading || perfAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (measAsync.hasError || perfAsync.hasError) {
      return _muted(palette, 'No se pudo cargar el progreso.'); // i18n: Fase W2
    }

    final ms = measAsync.requireValue;
    final tests = perfAsync.requireValue;
    if (ms.isEmpty && tests.isEmpty) {
      return _muted(palette, 'Sin datos de progreso todavía.'); // i18n: Fase W2
    }

    final latest = ms.isEmpty ? null : ms.last;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (latest != null) ...[
            _sectionLabel(palette, 'ANTROPOMETRÍA'), // i18n: Fase W2
            const SizedBox(height: 10),
            Row(
              children: [
                _MeasCard(
                    label: 'Peso',
                    value: latest.weightKg,
                    unit: 'kg',
                    palette: palette), // i18n: Fase W2
                const SizedBox(width: 10),
                _MeasCard(
                    label: '% Graso',
                    value: latest.fatPercentage,
                    unit: '%',
                    palette: palette), // i18n: Fase W2
                const SizedBox(width: 10),
                _MeasCard(
                    label: 'Cintura',
                    value: latest.waistCm,
                    unit: 'cm',
                    palette: palette), // i18n: Fase W2
              ],
            ),
            if (ms.length >= 2) ...[
              const SizedBox(height: 16),
              // El chart trae su propia card + heading; no lo re-envolvemos.
              MeasurementProgressChart(measurements: ms),
            ],
          ],
          // ── Rendimiento (W2 PR8) ──────────────────────────────────────────
          // Ambos casos lideran con la misma sección «RENDIMIENTO» (consistencia
          // con el módulo coach legacy). Con ≥2 tests el chart agrega ABAJO su
          // propia card interna (heading l10n «PROGRESO»).
          if (tests.isNotEmpty) ...[
            if (latest != null) const SizedBox(height: 20),
            _sectionLabel(palette, 'RENDIMIENTO'), // i18n: Fase W2
            const SizedBox(height: 10),
            if (tests.length >= 2)
              PerformanceProgressChart(tests: tests)
            else
              _muted(palette,
                  'Cargá al menos 2 tests para ver la evolución.'), // i18n: Fase W2
          ],
        ],
      ),
    );
  }
}

class _MeasCard extends StatelessWidget {
  const _MeasCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.palette,
  });

  final String label;
  final double? value;
  final String unit;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: palette.bgCard,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(color: palette.textMuted, fontSize: 11)),
            const SizedBox(height: 4),
            Text(
              value == null ? '—' : '${_trimNum(value!)} $unit',
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _sectionLabel(AppPalette palette, String text) => Text(
      text,
      style: TextStyle(
        color: palette.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
      ),
    );

Widget _muted(AppPalette palette, String text) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text,
            style: TextStyle(color: palette.textMuted, fontSize: 14)),
      ),
    );

/// Entero si es redondo, un decimal si no (61 → "61", 60.5 → "60.5").
String _trimNum(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Volumen compacto: kg hasta 999, toneladas con un decimal de ahí en más.
String _fmtVolKg(double kg) =>
    kg >= 1000 ? '${(kg / 1000).toStringAsFixed(1)} t' : '${kg.round()} kg';

/// Tab Resumen (W2 PR4): 4 métricas derivadas + heatmap de adherencia de 12
/// semanas. Sólo usa data trainer-readable (sesiones, mediciones, plan
/// activo) vía [ResumenMetrics]. La última-sesión por ejercicio, los datos
/// personales privados, la nota fijada y la próxima sesión se difieren
/// (dependen de `setLogs` owner-only, campos privados o backend nuevo).
class _ResumenTab extends ConsumerWidget {
  const _ResumenTab({required this.athleteId});
  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final trainerUid = ref.watch(currentUidProvider);
    final sessionsAsync = ref.watch(sessionsByUidProvider(athleteId));
    final measAsync = ref.watch(measurementsForAthleteProvider(athleteId));
    final routinesAsync = ref.watch(assignedRoutinesProvider(athleteId));

    // El resumen combina tres fuentes async: spinner hasta que las tres tengan
    // valor, y un único error si alguna falla. Si leyéramos routines/measurements
    // con valueOrNull, un error o un load lento se disfrazaría de «sin plan /
    // sin datos» — data trainer-facing engañosa.
    if (sessionsAsync.isLoading ||
        measAsync.isLoading ||
        routinesAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (sessionsAsync.hasError ||
        measAsync.hasError ||
        routinesAsync.hasError) {
      return _muted(palette, 'No se pudo cargar el resumen.'); // i18n: Fase W2
    }

    final routines = routinesAsync.requireValue;
    final actives = routines.where((r) => r.status == RoutineStatus.active);
    final active =
        actives.where((r) => r.assignedBy == trainerUid).firstOrNull ??
            actives.firstOrNull;
    final m = ResumenMetrics.compute(
      sessions: sessionsAsync.requireValue,
      measurements: measAsync.requireValue,
      weeklyTarget: active?.days.length ?? 0,
      now: DateTime.now(),
    );

    final adh = m.adherencia30dPct;
    final adhDelta = m.adherenciaDeltaPts;
    final volDelta = m.volumenDeltaPct;
    final peso = m.pesoActualKg;
    final pesoDelta = m.pesoDelta30dKg;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MetricCard(
                  palette: palette,
                  label: 'ADHERENCIA 30D', // i18n: Fase W2
                  value: adh == null ? '—' : '${adh.round()}%',
                  delta: adhDelta == null
                      ? null
                      : '${adhDelta >= 0 ? '↑' : '↓'} ${adhDelta.abs().round()} pts',
                  deltaColor: adhDelta == null
                      ? null
                      : (adhDelta >= 0 ? palette.accent : palette.danger),
                  caption: adh == null ? 'Sin plan' : 'vs 30 días previos',
                ),
                const SizedBox(width: 10),
                _MetricCard(
                  palette: palette,
                  label: 'SESIONES / SEM', // i18n: Fase W2
                  value: m.sesionesPorSemana.toStringAsFixed(1),
                  caption: m.weeklyTarget > 0
                      ? 'Plan: ${m.weeklyTarget}'
                      : 'Sin plan',
                ),
                const SizedBox(width: 10),
                _MetricCard(
                  palette: palette,
                  label: 'VOLUMEN', // i18n: Fase W2
                  value: _fmtVolKg(m.volumenSemanaActualKg),
                  delta: volDelta == null
                      ? null
                      : '${volDelta >= 0 ? '+' : ''}${volDelta.round()}%',
                  deltaColor: volDelta == null
                      ? null
                      : (volDelta >= 0 ? palette.accent : palette.danger),
                  caption:
                      volDelta == null ? 'esta semana' : 'vs semana pasada',
                ),
                const SizedBox(width: 10),
                _MetricCard(
                  palette: palette,
                  label: 'PESO CORPORAL', // i18n: Fase W2
                  value: peso == null ? '—' : '${_trimNum(peso)} kg',
                  delta: pesoDelta == null
                      ? null
                      : '${pesoDelta >= 0 ? '+' : ''}${pesoDelta.toStringAsFixed(1)} kg',
                  deltaColor: palette.textMuted,
                  caption: pesoDelta == null ? null : '30 días',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _sectionLabel(palette, 'ADHERENCIA · 12 SEMANAS'), // i18n: Fase W2
          const SizedBox(height: 10),
          _AdherenciaHeatmap(data: m.heatmap, palette: palette),
          const SizedBox(height: 14),
          Text(
            'Próximamente: última sesión por ejercicio, datos personales, '
            'nota fijada y próxima sesión.', // i18n: Fase W2
            style: TextStyle(color: palette.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.palette,
    required this.label,
    required this.value,
    this.delta,
    this.deltaColor,
    this.caption,
  });

  final AppPalette palette;
  final String label;
  final String value;
  final String? delta;
  final Color? deltaColor;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.bgCard,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (delta != null || caption != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  if (delta != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(
                        delta!,
                        style: TextStyle(
                          color: deltaColor ?? palette.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (caption != null)
                    Flexible(
                      child: Text(
                        caption!,
                        overflow: TextOverflow.ellipsis,
                        style:
                            TextStyle(color: palette.textMuted, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Heatmap estilo GitHub: 7 filas (días, lunes→domingo) × 12 columnas
/// (semanas, vieja→actual). Cada celda colorea por nivel 0..4.
class _AdherenciaHeatmap extends StatelessWidget {
  const _AdherenciaHeatmap({required this.data, required this.palette});

  /// 12 semanas × 7 días (nivel 0..4), como lo devuelve [ResumenMetrics].
  final List<List<int>> data;
  final AppPalette palette;

  // Abreviaturas es-AR sin colisión (martes/miércoles no quedan ambos como 'M').
  static const _dayLabels = ['L', 'Ma', 'Mi', 'J', 'V', 'S', 'D'];
  static const _labelWidth = 22.0;

  Color _cellColor(int level) => level <= 0
      ? palette.border.withValues(alpha: 0.35)
      : palette.accent.withValues(alpha: 0.25 + level * 0.1875);

  @override
  Widget build(BuildContext context) {
    final axisStyle = TextStyle(color: palette.textMuted, fontSize: 9);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Grilla + eje temporal comparten ancho intrínseco para que las
          // etiquetas «hace 12 sem» / «esta semana» caigan bajo la primera y la
          // última columna.
          IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var day = 0; day < 7; day++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        SizedBox(
                          width: _labelWidth,
                          child: Text(_dayLabels[day], style: axisStyle),
                        ),
                        for (var week = 0; week < data.length; week++)
                          Padding(
                            padding: const EdgeInsets.all(2),
                            child: Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: _cellColor(data[week][day]),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.only(left: _labelWidth),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('hace 12 sem', style: axisStyle), // i18n: Fase W2
                      Text('esta semana', style: axisStyle), // i18n: Fase W2
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text('Menos', style: axisStyle), // i18n: Fase W2
              const SizedBox(width: 6),
              for (var level = 0; level <= 4; level++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _cellColor(level),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              Text('Más', style: axisStyle), // i18n: Fase W2
            ],
          ),
        ],
      ),
    );
  }
}

String _cadenciaLabel(BillingCadence c) => switch (c) {
      BillingCadence.mensual => 'Mensual', // i18n: Fase W2
      BillingCadence.semanal => 'Semanal',
      BillingCadence.porSesion => 'Por sesión',
      BillingCadence.suelto => 'Suelto',
    };

/// Tab Pagos (W2 PR5/PR6): estado de cuenta + historial de pagos + acciones.
///
/// Sólo data trainer-readable: el historial sale de `trainerPaymentsProvider`
/// (que filtra por `trainerId == uid`, única forma que las reglas permiten al
/// entrenador) acotado a este alumno, y el cobro pendiente se reusa de
/// `pagosPorCobrarProvider` (que ya computa cadencia/deuda) sin reimplementar
/// billing. PR6 agrega **registrar pago** (crea un Payment pagado) y **marcar
/// pagado** (settlea un cobro pendiente: `markManyPaid` para los sueltos; crea
/// un Payment pagado con el `periodKey` que corresponda para los recurrentes —
/// misma receta que el dashboard del coach). Los recordatorios y las métricas
/// globales (ingreso del mes/proyección) se difieren.
class _PagosTab extends ConsumerWidget {
  const _PagosTab({required this.athleteId});
  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final paymentsAsync = ref.watch(trainerPaymentsProvider);
    final pendingAsync = ref.watch(pagosPorCobrarProvider);

    if (paymentsAsync.isLoading || pendingAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (paymentsAsync.hasError || pendingAsync.hasError) {
      return _muted(
          palette, 'No se pudieron cargar los pagos.'); // i18n: Fase W2
    }

    final history = paymentsAsync.requireValue
        .where((p) => p.athleteId == athleteId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final pending = pendingAsync.requireValue
        .where((c) => c.athleteId == athleteId)
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child:
                    _sectionLabel(palette, 'ESTADO DE CUENTA'), // i18n: Fase W2
              ),
              TextButton(
                onPressed: () => registrarPago(context, ref, athleteId),
                child: Text(
                  '+ Registrar pago', // i18n: Fase W2
                  style: TextStyle(
                    color: palette.accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          EstadoCuentaCard(
            palette: palette,
            pending: pending,
            onMarcarPagado: (c) => marcarPagado(context, ref, c),
          ),
          const SizedBox(height: 20),
          _sectionLabel(palette, 'HISTORIAL DE PAGOS'), // i18n: Fase W2
          const SizedBox(height: 10),
          if (history.isEmpty)
            _muted(palette, 'Sin pagos registrados todavía.') // i18n: Fase W2
          else
            PagosTable(payments: history, palette: palette),
          const SizedBox(height: 14),
          Text(
            'Próximamente: recordatorios y exportar.', // i18n: Fase W2
            style: TextStyle(color: palette.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Tab Entrenamiento (W2 PR3): rutina activa + historial de sesiones + evolución
/// por ejercicio. Reusa `assignedRoutinesProvider`, `sessionsByUidProvider`,
/// `athleteExerciseListProvider` y `exerciseProgressionProvider`.
class _EntrenamientoTab extends ConsumerWidget {
  const _EntrenamientoTab({required this.athleteId});
  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final trainerUid = ref.watch(currentUidProvider);
    final routinesAsync = ref.watch(assignedRoutinesProvider(athleteId));
    final sessionsAsync = ref.watch(sessionsByUidProvider(athleteId));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionLabel(palette, 'RUTINA ACTIVA'), // i18n: Fase W2
          const SizedBox(height: 10),
          routinesAsync.when(
            loading: () => _muted(palette, 'Cargando…'), // i18n: Fase W2
            error: (e, _) => _muted(
                palette, 'No se pudo cargar la rutina.'), // i18n: Fase W2
            data: (routines) {
              final actives =
                  routines.where((r) => r.status == RoutineStatus.active);
              final active = actives
                      .where((r) => r.assignedBy == trainerUid)
                      .firstOrNull ??
                  actives.firstOrNull;
              if (active == null) {
                return _muted(
                    palette, 'Sin rutina activa asignada.'); // i18n: Fase W2
              }
              return _RutinaCard(routine: active, palette: palette);
            },
          ),
          const SizedBox(height: 20),
          _sectionLabel(palette, 'HISTORIAL DE SESIONES'), // i18n: Fase W2
          const SizedBox(height: 10),
          sessionsAsync.when(
            loading: () => _muted(palette, 'Cargando…'), // i18n: Fase W2
            error: (e, _) => _muted(
                palette,
                e is FirebaseException && e.code == 'permission-denied'
                    ? 'El alumno no compartió su historial.' // i18n: Fase W2
                    : 'No se pudo cargar el historial.'), // i18n: Fase W2
            data: (sessions) {
              // isCompletedSession excluye sesiones abandonadas (status=finished
              // pero wasFullyCompleted=false) para no divergir del historial del
              // propio alumno ni de los contadores públicos. // i18n: Fase W2
              final finished =
                  sessions.where(isCompletedSession).take(20).toList();
              if (finished.isEmpty) {
                return _muted(palette,
                    'Sin sesiones registradas todavía.'); // i18n: Fase W2
              }
              return _HistorialTable(
                  sessions: finished, palette: palette, athleteId: athleteId);
            },
          ),
          const SizedBox(height: 24),
          _ProgressionTabSection(athleteId: athleteId, palette: palette),
        ],
      ),
    );
  }
}

// ── Evolución por ejercicio (PR2) ─────────────────────────────────────────────

/// Web-surface exercise-progression section.
///
/// Wires [athleteExerciseListProvider] + [exerciseProgressionProvider] into
/// [ExercisePickerRow] + [ExerciseProgressionChart].
///
/// All user-visible strings are hardcoded Spanish — the web Coach Hub does NOT
/// use AppL10n. Marked `// i18n: Fase W2` for future extraction.
///
/// Firestore access: trainer READ on setLogs is granted by firestore.rules:507-520
/// (mirrors the session-share predicate: owner OR linked trainer).
class _ProgressionTabSection extends ConsumerStatefulWidget {
  const _ProgressionTabSection({
    required this.athleteId,
    required this.palette,
  });

  final String athleteId;
  final AppPalette palette;

  @override
  ConsumerState<_ProgressionTabSection> createState() =>
      _ProgressionTabSectionState();
}

class _ProgressionTabSectionState
    extends ConsumerState<_ProgressionTabSection> {
  String? _selectedExerciseId;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final exerciseListAsync =
        ref.watch(athleteExerciseListProvider(widget.athleteId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Section label — hardcoded Spanish (i18n: Fase W2).
        Text(
          'EVOLUCIÓN POR EJERCICIO', // i18n: Fase W2
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        exerciseListAsync.when(
          loading: () => Text('Cargando…', // i18n: Fase W2
              style: TextStyle(color: palette.textMuted, fontSize: 13)),
          error: (_, __) => Text(
            'No se pudo cargar la evolución.', // i18n: Fase W2
            style: TextStyle(color: palette.textMuted, fontSize: 13),
          ),
          data: (exercises) {
            if (exercises.isEmpty) {
              return Text(
                'Sin registros de series todavía.', // i18n: Fase W2
                style: TextStyle(color: palette.textMuted, fontSize: 13),
              );
            }

            // Default selection: most-recently-logged exercise (first in list).
            final effectiveId =
                _selectedExerciseId ?? exercises.first.exerciseId;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ExercisePickerRow(
                  exercises: exercises,
                  selectedId: effectiveId,
                  onSelect: (id) => setState(() => _selectedExerciseId = id),
                ),
                const SizedBox(height: 12),
                _ProgressionChartLoader(
                  athleteId: widget.athleteId,
                  exerciseId: effectiveId,
                  palette: palette,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Watches [exerciseProgressionProvider] for the selected exercise and renders
/// [ExerciseProgressionChart] with hardcoded Spanish labels.
class _ProgressionChartLoader extends ConsumerWidget {
  const _ProgressionChartLoader({
    required this.athleteId,
    required this.exerciseId,
    required this.palette,
  });

  final String athleteId;
  final String exerciseId;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressionAsync = ref.watch(
      exerciseProgressionProvider(
          (athleteUid: athleteId, exerciseId: exerciseId)),
    );

    return progressionAsync.when(
      loading: () => Text('Cargando…', // i18n: Fase W2
          style: TextStyle(color: palette.textMuted, fontSize: 13)),
      error: (_, __) => Text(
        'No se pudo cargar la evolución.', // i18n: Fase W2
        style: TextStyle(color: palette.textMuted, fontSize: 13),
      ),
      data: (progression) => ExerciseProgressionChart(
        progression: progression,
        localeName: 'es_AR', // hardcoded for web Coach Hub (i18n: Fase W2)
        labels: ExerciseProgressionChartLabels(
          prLabel: 'PR', // i18n: Fase W2
          volumeLabel: 'Volumen', // i18n: Fase W2
          volumeUnit: 'kg·reps', // i18n: Fase W2
          prUnit: 'kg', // i18n: Fase W2
          frequencyLabel: (n) => n == 1
              ? '1 sesión en las últimas 8 semanas' // i18n: Fase W2
              : '$n sesiones en las últimas 8 semanas', // i18n: Fase W2
          singlePointHint:
              'Necesitás al menos 2 sesiones para ver la evolución.', // i18n: Fase W2
          emptyHint:
              'Sin datos suficientes para este ejercicio.', // i18n: Fase W2
        ),
      ),
    );
  }
}

class _RutinaCard extends StatelessWidget {
  const _RutinaCard({required this.routine, required this.palette});
  final Routine routine;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            routine.name,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${routine.days.length} días · ${routine.numWeeks} ${routine.numWeeks == 1 ? 'semana' : 'semanas'}', // i18n: Fase W2
            style: TextStyle(color: palette.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 10),
          for (final day in routine.days)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      day.name,
                      style:
                          TextStyle(color: palette.textPrimary, fontSize: 14),
                    ),
                  ),
                  Text(
                    '${day.slots.length} ${day.slots.length == 1 ? 'ejercicio' : 'ejercicios'}', // i18n: Fase W2
                    style: TextStyle(color: palette.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HistorialTable extends StatelessWidget {
  const _HistorialTable({
    required this.sessions,
    required this.palette,
    required this.athleteId,
    this.showStatusBadge = false,
  });
  final List<Session> sessions;
  final AppPalette palette;
  final String athleteId;

  /// If true, the row prefixes the session name with a small status pill
  /// (Completada / Incompleta / En curso). Used by the Historial tab where
  /// non-completed sessions are shown; the Entrenamientos tab filters to
  /// completed and doesn't need it.
  final bool showStatusBadge;

  @override
  Widget build(BuildContext context) {
    final h = TextStyle(
        color: palette.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                // i18n: Fase W2 (encabezados)
                Expanded(flex: 3, child: Text('FECHA', style: h)),
                Expanded(flex: 4, child: Text('SESIÓN', style: h)),
                Expanded(flex: 2, child: Text('DURACIÓN', style: h)),
                Expanded(
                  flex: 2,
                  child: Text('VOLUMEN', style: h, textAlign: TextAlign.right),
                ),
                const SizedBox(width: 24),
              ],
            ),
          ),
          // Tap a session to expand its real per-exercise set detail
          // (trainer-athlete-set-logs).
          for (final s in sessions)
            _ExpandableSessionRow(
              session: s,
              athleteId: athleteId,
              palette: palette,
              showStatusBadge: showStatusBadge,
            ),
        ],
      ),
    );
  }
}

/// A session row that expands on tap to show the athlete's REAL logged sets
/// for that session (read-only; gated by `session_shares`).
class _ExpandableSessionRow extends ConsumerStatefulWidget {
  const _ExpandableSessionRow({
    required this.session,
    required this.athleteId,
    required this.palette,
    this.showStatusBadge = false,
  });
  final Session session;
  final String athleteId;
  final AppPalette palette;
  final bool showStatusBadge;

  @override
  ConsumerState<_ExpandableSessionRow> createState() =>
      _ExpandableSessionRowState();
}

class _ExpandableSessionRowState extends ConsumerState<_ExpandableSessionRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final s = widget.session;
    final c = TextStyle(color: palette.textPrimary, fontSize: 13);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    // Historial tab shows active sessions too; fall back to
                    // startedAt when finishedAt is null so the user still
                    // sees WHEN the athlete started it.
                    s.finishedAt != null
                        ? fmtDate(s.finishedAt!)
                        : widget.showStatusBadge
                            ? fmtDate(s.startedAt)
                            : '—',
                    style: c,
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: widget.showStatusBadge
                      ? Row(
                          children: [
                            _SessionStatusPill(session: s, palette: palette),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(s.routineName,
                                  overflow: TextOverflow.ellipsis, style: c),
                            ),
                          ],
                        )
                      : Text(s.routineName,
                          overflow: TextOverflow.ellipsis, style: c),
                ),
                Expanded(
                  flex: 2,
                  child:
                      Text('${s.durationMin} min', style: c), // i18n: Fase W2
                ),
                Expanded(
                  flex: 2,
                  child: Text('${s.totalVolumeKg.round()} kg', // i18n: Fase W2
                      style: c,
                      textAlign: TextAlign.right),
                ),
                SizedBox(
                  width: 24,
                  child: Icon(
                    _expanded ? TreinoIcon.chevronUp : TreinoIcon.chevronDown,
                    size: 16,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          _SetLogsExpansion(
            athleteId: widget.athleteId,
            sessionId: s.id,
            palette: palette,
          ),
      ],
    );
  }
}

/// Loads and renders one session's per-exercise set logs for the trainer.
/// Maps `permission-denied` (athlete hasn't shared) to a friendly placeholder.
class _SetLogsExpansion extends ConsumerWidget {
  const _SetLogsExpansion({
    required this.athleteId,
    required this.sessionId,
    required this.palette,
  });
  final String athleteId;
  final String sessionId;
  final AppPalette palette;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(coachSessionSetLogsProvider(
        (athleteUid: athleteId, sessionId: sessionId)));
    final muted = TextStyle(color: palette.textMuted, fontSize: 12);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: async.when(
        loading: () => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: palette.accent),
          ),
        ),
        error: (e, _) {
          final noShare =
              e is FirebaseException && e.code == 'permission-denied';
          return Text(
            noShare
                ? 'El alumno no compartió su historial.' // i18n: Fase W2
                : 'No se pudo cargar el detalle de la sesión.', // i18n: Fase W2
            style: muted,
          );
        },
        data: (logs) {
          if (logs.isEmpty) {
            return Text(
                'Sin series registradas en esta sesión.', // i18n: Fase W2
                style: muted);
          }
          final groups = <String, List<SetLog>>{};
          for (final log in logs) {
            groups.putIfAbsent(log.exerciseId, () => <SetLog>[]).add(log);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final entry in groups.entries)
                SessionExerciseBlock(
                  exerciseName: entry.value.first.exerciseName,
                  sets: entry.value,
                ),
            ],
          );
        },
      ),
    );
  }
}

// ── _NotasPrivadasTab ─────────────────────────────────────────────────────────

/// Coach Hub web — Tab «Notas privadas» del alumno detail.
///
/// UX (W2+):
/// - Text area grande, editable inline (no modal/bottom sheet, hay espacio).
/// - Botón GUARDAR habilitado solo cuando hay cambios pendientes vs lo que
///   trae el stream (compará contra el último save).
/// - Timestamp "Última edición ..." arriba a la derecha si hay una nota
///   guardada previamente.
/// - Empty state = text area vacío + hint. La regla del PF es "solo vos lo
///   ves" — no lo mostrás al alumno en NINGÚN surface.
///
/// Data:
/// - Reusa el mismo stack de mobile (`AthleteNote` + `athleteNoteProvider` +
///   `AthleteNoteRepository`). Sin data model nuevo, sin rules nuevas.
class _NotasPrivadasTab extends ConsumerStatefulWidget {
  const _NotasPrivadasTab({required this.athleteId});

  final String athleteId;

  @override
  ConsumerState<_NotasPrivadasTab> createState() => _NotasPrivadasTabState();
}

class _NotasPrivadasTabState extends ConsumerState<_NotasPrivadasTab> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  String _lastSavedContent = '';
  bool _initialized = false;
  bool _saving = false;

  @override
  void didUpdateWidget(covariant _NotasPrivadasTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the parent swaps to a different athlete, Flutter reuses this
    // State — the controller keeps the previous athlete's text and the
    // "typing wins" gate blocks the new stream from populating it. Reset
    // the local buffer so the new athlete's stream seeds the controller
    // on its first emission.
    if (oldWidget.athleteId != widget.athleteId) {
      _initialized = false;
      _controller.text = '';
      _lastSavedContent = '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Sync `_controller` with the incoming server value the FIRST time the
  /// stream emits data — after that, we own the buffer (typing wins). If the
  /// PF opens the tab, types "foo", and a stale re-emit comes in with an
  /// older `note`, we DON'T overwrite what they typed. Save button drives
  /// the reconciliation.
  void _initFromStream(AthleteNote? note) {
    if (_initialized) return;
    _initialized = true;
    final content = note?.note ?? '';
    _controller.text = content;
    _lastSavedContent = content;
  }

  bool get _hasChanges => _controller.text != _lastSavedContent;

  Future<void> _save(String trainerUid) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final content = _controller.text;
      await ref.read(athleteNoteRepositoryProvider).setNote(
            AthleteNote(
              trainerId: trainerUid,
              athleteId: widget.athleteId,
              note: content,
              updatedAt: DateTime.now(),
            ),
          );
      if (!mounted) return;
      setState(() {
        _lastSavedContent = content;
      });
      final l10n = AppL10n.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.coachHubAlumnoDetailNotasSaveSuccess),
          duration: const Duration(seconds: 2),
        ),
      );
    } on FirebaseException catch (_) {
      if (!mounted) return;
      final l10n = AppL10n.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.coachHubAlumnoDetailNotasSaveError)),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _formatUpdatedAt(DateTime updatedAt) {
    final local = updatedAt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year.toString();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$d/$m/$y · $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final trainerUid = ref.watch(currentUidProvider);
    if (trainerUid == null) {
      return const SizedBox.shrink();
    }
    final noteAsync = ref.watch(
      athleteNoteProvider(
        (trainerId: trainerUid, athleteId: widget.athleteId),
      ),
    );

    return noteAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
      error: (_, __) => Center(
        child: Text(
          l10n.coachHubAlumnoDetailNotasLoadError,
          style: TextStyle(color: palette.textMuted, fontSize: 14),
        ),
      ),
      data: (note) {
        // First data emission: seed the text controller. Subsequent emissions
        // are ignored — the PF's local buffer wins to avoid clobbering typing.
        _initFromStream(note);
        final updatedAt = note?.updatedAt;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header row: title + last-updated timestamp ─────────────
              Row(
                children: [
                  Text(
                    l10n.coachHubAlumnoDetailNotasTitle,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (updatedAt != null)
                    Text(
                      l10n.coachHubAlumnoDetailNotasUpdatedAt(
                          _formatUpdatedAt(updatedAt)),
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                l10n.coachHubAlumnoDetailNotasSubtitle,
                style: TextStyle(color: palette.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              // ── Editable text area ──────────────────────────────────────
              Expanded(
                // Rounded box that clips the scrollable content. Instead of
                // `TextField(expands: true)` which paints outside its parent
                // in some Flutter Web configs, we let the TextField grow to
                // its natural content height inside a SingleChildScrollView
                // — the SCV owns the scrolling and clips reliably against
                // the ClipRRect ancestor.
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: palette.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: ColoredBox(
                      color: palette.bgCard,
                      child: Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        thickness: 6,
                        child: SingleChildScrollView(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 16, 20, 16),
                          child: TextField(
                            controller: _controller,
                            maxLines: null,
                            minLines: 12,
                            keyboardType: TextInputType.multiline,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 14,
                              height: 1.4,
                            ),
                            decoration: InputDecoration.collapsed(
                              hintText: l10n.coachHubAlumnoDetailNotasHint,
                              hintStyle: TextStyle(
                                color: palette.textMuted,
                                fontSize: 14,
                              ),
                            ),
                            onChanged: (_) {
                              // Trigger rebuild to toggle save enabled state.
                              setState(() {});
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // ── Save button ─────────────────────────────────────────────
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: (_saving || !_hasChanges)
                      ? null
                      : () => _save(trainerUid),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: palette.bg,
                    disabledBackgroundColor:
                        palette.accent.withValues(alpha: 0.3),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: const StadiumBorder(),
                  ),
                  child: _saving
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: palette.bg,
                          ),
                        )
                      : Text(
                          l10n.coachHubAlumnoDetailNotasSaveButton,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── _HistorialTab ─────────────────────────────────────────────────────────────

/// Coach Hub web — Tab «Historial» del alumno detail.
///
/// Timeline cronológico de TODAS las sesiones del alumno (finished OK,
/// finished incompleta/abandonada, y active). Ordenadas más nuevas arriba,
/// vienen así del `sessionsByUidProvider`.
///
/// Diferencia con el tab «Entrenamientos»:
/// - Entrenamientos: últimas 20 sesiones COMPLETAS (isCompletedSession) +
///   evolución por ejercicio.
/// - Historial: TODAS las sesiones (sin límite, sin filtro) con badge de
///   status para que el PF distinga completadas, incompletas y activas.
///
/// Reusa el mismo `_HistorialTable` + `_ExpandableSessionRow` que
/// Entrenamientos, activando el flag `showStatusBadge`.
class _HistorialTab extends ConsumerWidget {
  const _HistorialTab({required this.athleteId});

  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final sessionsAsync = ref.watch(sessionsByUidProvider(athleteId));
    return sessionsAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
      error: (_, __) => Center(
        child: Text(
          'No pudimos cargar el historial.', // i18n: Fase W2
          style: TextStyle(color: palette.textMuted, fontSize: 14),
        ),
      ),
      data: (sessions) {
        if (sessions.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Text(
                'Este alumno todavía no registró sesiones.', // i18n: Fase W2
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textMuted, fontSize: 14),
              ),
            ),
          );
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Historial completo · ${sessions.length} sesiones', // i18n: Fase W2
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Todas las sesiones que registró — completas, incompletas y en curso.', // i18n: Fase W2
                style: TextStyle(color: palette.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              _HistorialTable(
                sessions: sessions,
                palette: palette,
                athleteId: athleteId,
                showStatusBadge: true,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── _SessionStatusPill ────────────────────────────────────────────────────────

/// Small pill/badge rendering the session's completion status: verde
/// «Completa», amarillo «Incompleta», naranja «En curso». Used inside the
/// Historial tab's session rows to distinguish state at a glance.
class _SessionStatusPill extends StatelessWidget {
  const _SessionStatusPill({required this.session, required this.palette});

  final Session session;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _statusFor(session, palette);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// Returns (label, color) for the session's current state.
  /// - `active` → «En curso» (rare in Historial but we show it if we see it).
  /// - `finished + wasFullyCompleted` → «Completa».
  /// - `finished + !wasFullyCompleted` → «Incompleta» (athlete abandoned).
  static (String, Color) _statusFor(Session s, AppPalette palette) {
    if (s.status == SessionStatus.active) {
      return ('EN CURSO', palette.warning); // i18n: Fase W2
    }
    if (s.wasFullyCompleted) {
      return ('COMPLETA', palette.accent); // i18n: Fase W2
    }
    return ('INCOMPLETA', palette.danger); // i18n: Fase W2
  }
}

// ── _ArchivosTab ──────────────────────────────────────────────────────────────

/// Coach Hub web — Tab «Archivos» del alumno detail.
///
/// Carpeta privada del PF por alumno para subir PDFs e imágenes (estudios
/// médicos, fotos de postura/lesión, planes impresos). El alumno NUNCA los
/// ve — es una herramienta interna del PF.
///
/// Data: reusa `athleteFilesProvider` + `AthleteFileRepository` (Firestore
/// para metadata + Firebase Storage para el binario). Rules trainer-only en
/// ambos lados.
///
/// V1 scope:
/// - Solo PDF + imágenes (10 MB max).
/// - Lista simple (más nuevos arriba).
/// - Subir → file picker → upload + set doc.
/// - Descargar → abre `downloadUrl` en tab nueva.
/// - Borrar → confirm dialog → borra Storage + Firestore.
class _ArchivosTab extends ConsumerStatefulWidget {
  const _ArchivosTab({required this.athleteId});

  final String athleteId;

  @override
  ConsumerState<_ArchivosTab> createState() => _ArchivosTabState();
}

class _ArchivosTabState extends ConsumerState<_ArchivosTab> {
  bool _uploading = false;

  Future<void> _pickAndUpload(String trainerUid) async {
    if (_uploading) return;
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'gif'],
      withData: true, // Necesitamos bytes para putData en web.
    );
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final bytes = picked.bytes;
    if (bytes == null) return;

    setState(() => _uploading = true);
    try {
      final contentType = _guessContentType(picked.name, picked.extension);
      await ref.read(athleteFileRepositoryProvider).upload(
            trainerId: trainerUid,
            athleteId: widget.athleteId,
            fileName: picked.name,
            contentType: contentType,
            bytes: bytes,
          );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.coachHubAlumnoDetailArchivosUploadSuccess),
          duration: const Duration(seconds: 2),
        ),
      );
    } on AthleteFileTooLargeException {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.coachHubAlumnoDetailArchivosUploadTooLarge),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.coachHubAlumnoDetailArchivosUploadError),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _confirmAndDelete(AthleteFile file) async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.coachHubAlumnoDetailArchivosDeleteTitle),
        content: Text(
          l10n.coachHubAlumnoDetailArchivosDeleteBody(file.fileName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.coachHubActionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.coachHubActionConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(athleteFileRepositoryProvider).delete(file);
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.coachHubAlumnoDetailArchivosDeleteError),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final trainerUid = ref.watch(currentUidProvider);
    if (trainerUid == null) return const SizedBox.shrink();
    final filesAsync = ref.watch(
      athleteFilesProvider(
        (trainerId: trainerUid, athleteId: widget.athleteId),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ─────────────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.coachHubAlumnoDetailArchivosTitle,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.coachHubAlumnoDetailArchivosSubtitle,
                      style:
                          TextStyle(color: palette.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _uploading ? null : () => _pickAndUpload(trainerUid),
                icon: _uploading
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.bg,
                        ),
                      )
                    : Icon(TreinoIcon.upload, size: 16, color: palette.bg),
                label: Text(l10n.coachHubAlumnoDetailArchivosUploadButton),
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.bg,
                  disabledBackgroundColor:
                      palette.accent.withValues(alpha: 0.3),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 12),
                  shape: const StadiumBorder(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            // Sticky-data pattern: si ya emitimos data alguna vez, la
            // seguimos mostrando aunque el stream emita error después
            // (ej. reconnect transient de Firestore). Solo mostramos el
            // error state duro cuando NO hay data previa.
            child: Builder(
              builder: (_) {
                if (filesAsync.hasValue) {
                  final files = filesAsync.requireValue;
                  if (files.isEmpty) {
                    return Center(
                      child: Text(
                        l10n.coachHubAlumnoDetailArchivosEmpty,
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: palette.textMuted, fontSize: 14),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: files.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: palette.border,
                    ),
                    itemBuilder: (_, i) => _ArchivoRow(
                      file: files[i],
                      palette: palette,
                      onDelete: () => _confirmAndDelete(files[i]),
                    ),
                  );
                }
                if (filesAsync.hasError) {
                  return Center(
                    child: Text(
                      l10n.coachHubAlumnoDetailArchivosLoadError,
                      style: TextStyle(color: palette.textMuted, fontSize: 14),
                    ),
                  );
                }
                return Center(
                  child: CircularProgressIndicator(color: palette.accent),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Deriva contentType desde el nombre/extension del picker. Files desde
  /// web NO siempre traen mimeType poblado (a diferencia de image_picker),
  /// así que armamos el contentType nosotros basado en la extensión.
  static String _guessContentType(String fileName, String? extension) {
    final ext = (extension ?? _extFromName(fileName)).toLowerCase();
    switch (ext) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'application/octet-stream';
    }
  }

  static String _extFromName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot >= fileName.length - 1) return '';
    return fileName.substring(dot + 1);
  }
}

/// Row de un archivo dentro del tab Archivos.
class _ArchivoRow extends StatelessWidget {
  const _ArchivoRow({
    required this.file,
    required this.palette,
    required this.onDelete,
  });

  final AthleteFile file;
  final AppPalette palette;
  final VoidCallback onDelete;

  Future<void> _open() async {
    final uri = Uri.tryParse(file.downloadUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final icon = switch (file.kind) {
      AthleteFileKind.pdf => TreinoIcon.filePdf,
      AthleteFileKind.image => TreinoIcon.image,
      AthleteFileKind.other => TreinoIcon.file,
    };
    final subtitle =
        '${_formatSize(file.sizeBytes)} · ${fmtDate(file.uploadedAt)}';
    return InkWell(
      onTap: _open,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 24, color: palette.textMuted),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.fileName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: palette.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: l10n.coachHubAlumnoDetailArchivosOpenTooltip,
              onPressed: _open,
              icon: Icon(TreinoIcon.download,
                  size: 18, color: palette.textMuted),
            ),
            IconButton(
              tooltip: l10n.coachHubAlumnoDetailArchivosDeleteTooltip,
              onPressed: onDelete,
              icon: Icon(TreinoIcon.trash, size: 18, color: palette.danger),
            ),
          ],
        ),
      ),
    );
  }

  /// KB si < 1 MB, MB con 1 decimal si mayor. Redondeo defensivo.
  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.round()} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }
}

// ── _MedicionesTab ────────────────────────────────────────────────────────────

/// Vistas del tab Mediciones. PR#2 (2026-07-03) sumó `rendimiento` como
/// segunda subvista con el toggle en el header.
enum _MedicionView { antropometricas, rendimiento }

/// Coach Hub web — Tab «Mediciones» del alumno detail.
///
/// PR#1: CRUD antropométricas.
/// PR#2 (2026-07-03): toggle Antropo/Rendimiento + subvista Rendimiento
/// con el mismo pattern (ver + agregar + borrar). Reusa
/// `performanceTestsForAthleteProvider` + `PerformanceTestRepository`.
/// PR#3 sumará editar.
///
/// **Diferencia con tab Progreso**: Progreso muestra CHARTS (evolución).
/// Mediciones muestra la DATA cruda con opción de gestionar entradas.
class _MedicionesTab extends ConsumerStatefulWidget {
  const _MedicionesTab({required this.athleteId});

  final String athleteId;

  @override
  ConsumerState<_MedicionesTab> createState() => _MedicionesTabState();
}

class _MedicionesTabState extends ConsumerState<_MedicionesTab> {
  _MedicionView _view = _MedicionView.antropometricas;

  Future<void> _openAntropoDialog({Measurement? initial}) async {
    final trainerUid = ref.read(currentUidProvider);
    if (trainerUid == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _NuevaMedicionDialog(
        athleteId: widget.athleteId,
        trainerUid: trainerUid,
        initial: initial,
      ),
    );
  }

  Future<void> _openRendimientoDialog({PerformanceTest? initial}) async {
    final trainerUid = ref.read(currentUidProvider);
    if (trainerUid == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _NuevoRendimientoDialog(
        athleteId: widget.athleteId,
        trainerUid: trainerUid,
        initial: initial,
      ),
    );
  }

  Future<void> _confirmDeleteMedicion(Measurement m) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar medición?'), // i18n: Fase W2
        content: Text(
          'La medición del ${fmtDate(m.recordedAt)} se va a borrar. '
          'No se puede deshacer.', // i18n: Fase W2
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'), // i18n: Fase W2
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmar'), // i18n: Fase W2
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(measurementRepositoryProvider).delete(m.id);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No pudimos eliminar la medición.'), // i18n: Fase W2
        ),
      );
    }
  }

  Future<void> _confirmDeleteRendimiento(PerformanceTest t) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar prueba?'), // i18n: Fase W2
        content: Text(
          'La prueba del ${fmtDate(t.recordedAt)} se va a borrar. '
          'No se puede deshacer.', // i18n: Fase W2
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'), // i18n: Fase W2
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmar'), // i18n: Fase W2
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(performanceTestRepositoryProvider).delete(t.id);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No pudimos eliminar la prueba.'), // i18n: Fase W2
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final isAntropo = _view == _MedicionView.antropometricas;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header con toggle ──────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isAntropo
                          ? 'Mediciones antropométricas' // i18n: Fase W2
                          : 'Pruebas de rendimiento', // i18n: Fase W2
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isAntropo
                          ? 'Peso, composición corporal y circunferencias.' // i18n: Fase W2
                          : 'Saltos, sprints, 1RM y resistencia.', // i18n: Fase W2
                      style: TextStyle(
                          color: palette.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: isAntropo
                    ? () => _openAntropoDialog()
                    : () => _openRendimientoDialog(),
                icon: const Icon(Icons.add, size: 16),
                label: Text(isAntropo
                    ? 'NUEVA MEDICIÓN' // i18n: Fase W2
                    : 'NUEVA PRUEBA'), // i18n: Fase W2
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.bg,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 12),
                  shape: const StadiumBorder(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── Toggle segmented ────────────────────────────────────────────
          _MedicionesToggle(
            view: _view,
            palette: palette,
            onChanged: (v) => setState(() => _view = v),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: isAntropo
                ? _AntropoList(
                    athleteId: widget.athleteId,
                    palette: palette,
                    onDelete: _confirmDeleteMedicion,
                    onEdit: (m) => _openAntropoDialog(initial: m),
                  )
                : _RendimientoList(
                    athleteId: widget.athleteId,
                    palette: palette,
                    onDelete: _confirmDeleteRendimiento,
                    onEdit: (t) => _openRendimientoDialog(initial: t),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Toggle segmented del header — Antropométricas / Rendimiento.
class _MedicionesToggle extends StatelessWidget {
  const _MedicionesToggle({
    required this.view,
    required this.palette,
    required this.onChanged,
  });

  final _MedicionView view;
  final AppPalette palette;
  final ValueChanged<_MedicionView> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(_MedicionView v, String label) {
      final active = view == v;
      return Expanded(
        child: InkWell(
          onTap: () => onChanged(v),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active ? palette.accent.withValues(alpha: 0.15) : null,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? palette.accent : palette.border,
                width: active ? 1.5 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: active ? palette.accent : palette.textMuted,
                fontSize: 13,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        seg(_MedicionView.antropometricas, 'ANTROPOMÉTRICAS'), // i18n: Fase W2
        const SizedBox(width: 8),
        seg(_MedicionView.rendimiento, 'RENDIMIENTO'), // i18n: Fase W2
      ],
    );
  }
}

/// Subvista de mediciones antropométricas.
class _AntropoList extends ConsumerWidget {
  const _AntropoList({
    required this.athleteId,
    required this.palette,
    required this.onDelete,
    required this.onEdit,
  });

  final String athleteId;
  final AppPalette palette;
  final Future<void> Function(Measurement) onDelete;
  final Future<void> Function(Measurement) onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final measAsync = ref.watch(measurementsForAthleteProvider(athleteId));
    if (measAsync.hasValue) {
      final all = measAsync.requireValue;
      // Provider ordena ASC — queremos DESC para "más nuevas arriba".
      final ms = all.reversed.toList();
      if (ms.isEmpty) {
        return Center(
          child: Text(
            'Este alumno todavía no tiene mediciones cargadas.', // i18n: Fase W2
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.textMuted, fontSize: 14),
          ),
        );
      }
      return ListView.separated(
        itemCount: ms.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: palette.border),
        itemBuilder: (_, i) => _MedicionRow(
          measurement: ms[i],
          palette: palette,
          onDelete: () => onDelete(ms[i]),
          onEdit: () => onEdit(ms[i]),
        ),
      );
    }
    if (measAsync.hasError) {
      return Center(
        child: Text(
          'No pudimos cargar las mediciones.', // i18n: Fase W2
          style: TextStyle(color: palette.textMuted, fontSize: 14),
        ),
      );
    }
    return Center(child: CircularProgressIndicator(color: palette.accent));
  }
}

/// Subvista de pruebas de rendimiento.
class _RendimientoList extends ConsumerWidget {
  const _RendimientoList({
    required this.athleteId,
    required this.palette,
    required this.onDelete,
    required this.onEdit,
  });

  final String athleteId;
  final AppPalette palette;
  final Future<void> Function(PerformanceTest) onDelete;
  final Future<void> Function(PerformanceTest) onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final testsAsync =
        ref.watch(performanceTestsForAthleteProvider(athleteId));
    if (testsAsync.hasValue) {
      final all = testsAsync.requireValue;
      final tests = all.reversed.toList();
      if (tests.isEmpty) {
        return Center(
          child: Text(
            'Este alumno todavía no tiene pruebas de rendimiento cargadas.', // i18n: Fase W2
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.textMuted, fontSize: 14),
          ),
        );
      }
      return ListView.separated(
        itemCount: tests.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: palette.border),
        itemBuilder: (_, i) => _RendimientoRow(
          test: tests[i],
          palette: palette,
          onDelete: () => onDelete(tests[i]),
          onEdit: () => onEdit(tests[i]),
        ),
      );
    }
    if (testsAsync.hasError) {
      return Center(
        child: Text(
          'No pudimos cargar las pruebas.', // i18n: Fase W2
          style: TextStyle(color: palette.textMuted, fontSize: 14),
        ),
      );
    }
    return Center(child: CircularProgressIndicator(color: palette.accent));
  }
}

/// Row de una medición individual. Tap para expandir y ver TODOS los campos
/// cargados (los que son null no se muestran para no ensuciar la UI).
class _MedicionRow extends StatefulWidget {
  const _MedicionRow({
    required this.measurement,
    required this.palette,
    required this.onDelete,
    required this.onEdit,
  });

  final Measurement measurement;
  final AppPalette palette;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  State<_MedicionRow> createState() => _MedicionRowState();
}

class _MedicionRowState extends State<_MedicionRow> {
  bool _expanded = false;

  /// Summary line: los 3 campos que suele pedir el PF: peso, % grasa, cintura.
  /// Si alguno es null, se omite del summary.
  String _summary() {
    final m = widget.measurement;
    final parts = <String>[];
    if (m.weightKg != null) parts.add('${m.weightKg} kg');
    if (m.fatPercentage != null) parts.add('${m.fatPercentage}% grasa');
    if (m.waistCm != null) parts.add('cintura ${m.waistCm} cm');
    if (parts.isEmpty) return 'Sin datos de composición'; // i18n: Fase W2
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.measurement;
    final palette = widget.palette;
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 22,
                  color: palette.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fmtDate(m.recordedAt),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _summary(),
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Editar', // i18n: Fase W2
                  onPressed: widget.onEdit,
                  icon: Icon(Icons.edit,
                      size: 18, color: palette.textMuted),
                ),
                IconButton(
                  tooltip: 'Eliminar', // i18n: Fase W2
                  onPressed: widget.onDelete,
                  icon: Icon(TreinoIcon.trash,
                      size: 18, color: palette.danger),
                ),
              ],
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(30, 12, 8, 0),
                child: _MedicionDetail(measurement: m, palette: palette),
              ),
          ],
        ),
      ),
    );
  }
}

/// Detalle expandido de una medición. Muestra solo los campos con valor.
/// Layout: 2 columnas de "label: valor" para aprovechar el ancho del web.
class _MedicionDetail extends StatelessWidget {
  const _MedicionDetail(
      {required this.measurement, required this.palette});

  final Measurement measurement;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final m = measurement;
    final entries = <(String, String)>[
      // Composición
      if (m.weightKg != null) ('Peso', '${m.weightKg} kg'),
      if (m.fatPercentage != null) ('% grasa', '${m.fatPercentage}%'),
      if (m.muscleMassKg != null) ('Masa muscular', '${m.muscleMassKg} kg'),
      // Trunk
      if (m.shouldersCm != null) ('Hombros', '${m.shouldersCm} cm'),
      if (m.chestCm != null) ('Pecho', '${m.chestCm} cm'),
      if (m.waistCm != null) ('Cintura', '${m.waistCm} cm'),
      if (m.hipsCm != null) ('Cadera', '${m.hipsCm} cm'),
      if (m.glutesCm != null) ('Glúteos', '${m.glutesCm} cm'),
      // Upper
      if (m.bicepsLCm != null) ('Bíceps izq.', '${m.bicepsLCm} cm'),
      if (m.bicepsRCm != null) ('Bíceps der.', '${m.bicepsRCm} cm'),
      if (m.bicepsFlexedLCm != null)
        ('Bíceps flex. izq.', '${m.bicepsFlexedLCm} cm'),
      if (m.bicepsFlexedRCm != null)
        ('Bíceps flex. der.', '${m.bicepsFlexedRCm} cm'),
      if (m.forearmLCm != null) ('Antebrazo izq.', '${m.forearmLCm} cm'),
      if (m.forearmRCm != null) ('Antebrazo der.', '${m.forearmRCm} cm'),
      // Lower
      if (m.upperThighLCm != null)
        ('Muslo sup. izq.', '${m.upperThighLCm} cm'),
      if (m.upperThighRCm != null)
        ('Muslo sup. der.', '${m.upperThighRCm} cm'),
      if (m.midThighLCm != null) ('Muslo med. izq.', '${m.midThighLCm} cm'),
      if (m.midThighRCm != null) ('Muslo med. der.', '${m.midThighRCm} cm'),
      if (m.calfLCm != null) ('Gemelo izq.', '${m.calfLCm} cm'),
      if (m.calfRCm != null) ('Gemelo der.', '${m.calfRCm} cm'),
    ];

    if (entries.isEmpty && (m.notes ?? '').isEmpty) {
      return Text(
        'Esta medición no tiene valores cargados.', // i18n: Fase W2
        style: TextStyle(color: palette.textMuted, fontSize: 13),
      );
    }

    // Split en 2 columnas para aprovechar ancho del web.
    final half = (entries.length / 2).ceil();
    final left = entries.take(half).toList();
    final right = entries.skip(half).toList();

    Widget colFor(List<(String, String)> items) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (label, value) in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 130,
                      child: Text(
                        label,
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      value,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: colFor(left)),
            const SizedBox(width: 24),
            Expanded(child: colFor(right)),
          ],
        ),
        if ((m.notes ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Nota',
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            m.notes!,
            style: TextStyle(color: palette.textPrimary, fontSize: 13),
          ),
        ],
      ],
    );
  }
}

/// Dialog modal para cargar (o editar) una medición antropométrica.
///
/// Todos los campos son opcionales — el PF loguea solo lo que midió esa
/// sesión. Composición corporal siempre expandida (más común); las
/// circunferencias en 3 secciones colapsables para no abrumar.
///
/// PR#3 (2026-07-03): si [initial] es no-nulo → **modo edición**. El
/// formulario arranca pre-populado con los valores actuales y guarda con
/// `MeasurementRepository.update` preservando `id`/`recordedBy`/
/// `athleteId`/`recordedAt`. Si es nulo → **modo crear** con `.add`.
class _NuevaMedicionDialog extends ConsumerStatefulWidget {
  const _NuevaMedicionDialog({
    required this.athleteId,
    required this.trainerUid,
    this.initial,
  });

  final String athleteId;
  final String trainerUid;
  final Measurement? initial;

  @override
  ConsumerState<_NuevaMedicionDialog> createState() =>
      _NuevaMedicionDialogState();
}

class _NuevaMedicionDialogState extends ConsumerState<_NuevaMedicionDialog> {
  final _formKey = GlobalKey<FormState>();

  // Composición
  final _weightC = TextEditingController();
  final _fatC = TextEditingController();
  final _muscleC = TextEditingController();
  // Trunk
  final _shouldersC = TextEditingController();
  final _chestC = TextEditingController();
  final _waistC = TextEditingController();
  final _hipsC = TextEditingController();
  final _glutesC = TextEditingController();
  // Upper
  final _bicepsLC = TextEditingController();
  final _bicepsRC = TextEditingController();
  final _bicepsFlexedLC = TextEditingController();
  final _bicepsFlexedRC = TextEditingController();
  final _forearmLC = TextEditingController();
  final _forearmRC = TextEditingController();
  // Lower
  final _upperThighLC = TextEditingController();
  final _upperThighRC = TextEditingController();
  final _midThighLC = TextEditingController();
  final _midThighRC = TextEditingController();
  final _calfLC = TextEditingController();
  final _calfRC = TextEditingController();
  // Meta
  final _notesC = TextEditingController();

  bool _trunkExpanded = false;
  bool _upperExpanded = false;
  bool _lowerExpanded = false;
  bool _saving = false;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) return;
    // Pre-populate controllers con los valores existentes.
    void set(TextEditingController c, double? v) {
      if (v != null) c.text = v.toString();
    }

    set(_weightC, initial.weightKg);
    set(_fatC, initial.fatPercentage);
    set(_muscleC, initial.muscleMassKg);
    set(_shouldersC, initial.shouldersCm);
    set(_chestC, initial.chestCm);
    set(_waistC, initial.waistCm);
    set(_hipsC, initial.hipsCm);
    set(_glutesC, initial.glutesCm);
    set(_bicepsLC, initial.bicepsLCm);
    set(_bicepsRC, initial.bicepsRCm);
    set(_bicepsFlexedLC, initial.bicepsFlexedLCm);
    set(_bicepsFlexedRC, initial.bicepsFlexedRCm);
    set(_forearmLC, initial.forearmLCm);
    set(_forearmRC, initial.forearmRCm);
    set(_upperThighLC, initial.upperThighLCm);
    set(_upperThighRC, initial.upperThighRCm);
    set(_midThighLC, initial.midThighLCm);
    set(_midThighRC, initial.midThighRCm);
    set(_calfLC, initial.calfLCm);
    set(_calfRC, initial.calfRCm);
    if (initial.notes != null) _notesC.text = initial.notes!;

    // Auto-expand secciones que tienen algún valor cargado, así el PF ve
    // los campos sin tener que abrir manualmente cada sección.
    _trunkExpanded = initial.shouldersCm != null ||
        initial.chestCm != null ||
        initial.waistCm != null ||
        initial.hipsCm != null ||
        initial.glutesCm != null;
    _upperExpanded = initial.bicepsLCm != null ||
        initial.bicepsRCm != null ||
        initial.bicepsFlexedLCm != null ||
        initial.bicepsFlexedRCm != null ||
        initial.forearmLCm != null ||
        initial.forearmRCm != null;
    _lowerExpanded = initial.upperThighLCm != null ||
        initial.upperThighRCm != null ||
        initial.midThighLCm != null ||
        initial.midThighRCm != null ||
        initial.calfLCm != null ||
        initial.calfRCm != null;
  }

  @override
  void dispose() {
    for (final c in [
      _weightC, _fatC, _muscleC,
      _shouldersC, _chestC, _waistC, _hipsC, _glutesC,
      _bicepsLC, _bicepsRC, _bicepsFlexedLC, _bicepsFlexedRC,
      _forearmLC, _forearmRC,
      _upperThighLC, _upperThighRC, _midThighLC, _midThighRC,
      _calfLC, _calfRC,
      _notesC,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Parse defensivo: acepta coma o punto, vacío → null, no-parseable → null.
  double? _parse(TextEditingController c) {
    final s = c.text.trim().replaceAll(',', '.');
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final initial = widget.initial;
    try {
      // En edición preservamos id + recordedBy + athleteId + recordedAt
      // (Firestore rule exige que los inmutables no cambien).
      final measurement = Measurement(
        id: initial?.id ?? '',
        athleteId: widget.athleteId,
        recordedBy: widget.trainerUid,
        recordedAt: initial?.recordedAt ?? DateTime.now(),
        weightKg: _parse(_weightC),
        fatPercentage: _parse(_fatC),
        muscleMassKg: _parse(_muscleC),
        shouldersCm: _parse(_shouldersC),
        chestCm: _parse(_chestC),
        waistCm: _parse(_waistC),
        hipsCm: _parse(_hipsC),
        glutesCm: _parse(_glutesC),
        bicepsLCm: _parse(_bicepsLC),
        bicepsRCm: _parse(_bicepsRC),
        bicepsFlexedLCm: _parse(_bicepsFlexedLC),
        bicepsFlexedRCm: _parse(_bicepsFlexedRC),
        forearmLCm: _parse(_forearmLC),
        forearmRCm: _parse(_forearmRC),
        upperThighLCm: _parse(_upperThighLC),
        upperThighRCm: _parse(_upperThighRC),
        midThighLCm: _parse(_midThighLC),
        midThighRCm: _parse(_midThighRC),
        calfLCm: _parse(_calfLC),
        calfRCm: _parse(_calfRC),
        notes: _notesC.text.trim().isEmpty ? null : _notesC.text.trim(),
      );
      final repo = ref.read(measurementRepositoryProvider);
      if (_isEditing) {
        await repo.update(measurement);
      } else {
        await repo.add(measurement);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(_isEditing
              ? 'Medición actualizada.' // i18n: Fase W2
              : 'Medición guardada.'), // i18n: Fase W2
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content:
              Text('No pudimos guardar la medición.'), // i18n: Fase W2
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Dialog(
      backgroundColor: palette.bg,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isEditing
                    ? 'Editar medición' // i18n: Fase W2
                    : 'Nueva medición', // i18n: Fase W2
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Cargá los campos que hayas medido. Todos son opcionales.', // i18n: Fase W2
                style: TextStyle(color: palette.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _NuevaMedicionSection(
                          title: 'COMPOSICIÓN CORPORAL', // i18n: Fase W2
                          palette: palette,
                          expanded: true,
                          onToggle: null,
                          children: [
                            _NuevaMedicionField(
                                label: 'Peso',
                                suffix: 'kg',
                                controller: _weightC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: '% grasa',
                                suffix: '%',
                                controller: _fatC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Masa muscular',
                                suffix: 'kg',
                                controller: _muscleC,
                                palette: palette),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _NuevaMedicionSection(
                          title: 'CIRCUNFERENCIAS TRUNK', // i18n: Fase W2
                          palette: palette,
                          expanded: _trunkExpanded,
                          onToggle: () =>
                              setState(() => _trunkExpanded = !_trunkExpanded),
                          children: [
                            _NuevaMedicionField(
                                label: 'Hombros',
                                suffix: 'cm',
                                controller: _shouldersC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Pecho',
                                suffix: 'cm',
                                controller: _chestC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Cintura',
                                suffix: 'cm',
                                controller: _waistC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Cadera',
                                suffix: 'cm',
                                controller: _hipsC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Glúteos',
                                suffix: 'cm',
                                controller: _glutesC,
                                palette: palette),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _NuevaMedicionSection(
                          title: 'MIEMBROS SUPERIORES', // i18n: Fase W2
                          palette: palette,
                          expanded: _upperExpanded,
                          onToggle: () =>
                              setState(() => _upperExpanded = !_upperExpanded),
                          children: [
                            _NuevaMedicionField(
                                label: 'Bíceps izq.',
                                suffix: 'cm',
                                controller: _bicepsLC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Bíceps der.',
                                suffix: 'cm',
                                controller: _bicepsRC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Bíceps flex. izq.',
                                suffix: 'cm',
                                controller: _bicepsFlexedLC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Bíceps flex. der.',
                                suffix: 'cm',
                                controller: _bicepsFlexedRC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Antebrazo izq.',
                                suffix: 'cm',
                                controller: _forearmLC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Antebrazo der.',
                                suffix: 'cm',
                                controller: _forearmRC,
                                palette: palette),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _NuevaMedicionSection(
                          title: 'MIEMBROS INFERIORES', // i18n: Fase W2
                          palette: palette,
                          expanded: _lowerExpanded,
                          onToggle: () =>
                              setState(() => _lowerExpanded = !_lowerExpanded),
                          children: [
                            _NuevaMedicionField(
                                label: 'Muslo sup. izq.',
                                suffix: 'cm',
                                controller: _upperThighLC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Muslo sup. der.',
                                suffix: 'cm',
                                controller: _upperThighRC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Muslo med. izq.',
                                suffix: 'cm',
                                controller: _midThighLC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Muslo med. der.',
                                suffix: 'cm',
                                controller: _midThighRC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Gemelo izq.',
                                suffix: 'cm',
                                controller: _calfLC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Gemelo der.',
                                suffix: 'cm',
                                controller: _calfRC,
                                palette: palette),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _notesC,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: 'Nota (opcional)', // i18n: Fase W2
                            labelStyle:
                                TextStyle(color: palette.textMuted),
                            filled: true,
                            fillColor: palette.bgCard,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: palette.border),
                            ),
                          ),
                          style: TextStyle(color: palette.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'), // i18n: Fase W2
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: palette.bg,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      shape: const StadiumBorder(),
                    ),
                    child: _saving
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: palette.bg,
                            ),
                          )
                        : const Text('GUARDAR'), // i18n: Fase W2
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Sección del dialog de nueva medición. Si `onToggle` es null, siempre
/// expandida (composición corporal). Si es non-null, header clickeable para
/// colapsar/expandir.
class _NuevaMedicionSection extends StatelessWidget {
  const _NuevaMedicionSection({
    required this.title,
    required this.palette,
    required this.expanded,
    required this.onToggle,
    required this.children,
  });

  final String title;
  final AppPalette palette;
  final bool expanded;
  final VoidCallback? onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final header = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (onToggle != null)
            Icon(
              expanded
                  ? Icons.keyboard_arrow_down
                  : Icons.keyboard_arrow_right,
              size: 18,
              color: palette.textMuted,
            ),
          if (onToggle != null) const SizedBox(width: 4),
          Text(
            title,
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (onToggle != null)
          InkWell(onTap: onToggle, child: header)
        else
          header,
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            // 2 columnas
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final c in children)
                  ConstrainedBox(
                    constraints: const BoxConstraints(minWidth: 240),
                    child: SizedBox(
                      width: 270,
                      child: c,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Campo numérico del dialog. Acepta coma o punto como decimal.
class _NuevaMedicionField extends StatelessWidget {
  const _NuevaMedicionField({
    required this.label,
    required this.suffix,
    required this.controller,
    required this.palette,
  });

  final String label;
  final String suffix;
  final TextEditingController controller;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: TextStyle(color: palette.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: palette.textMuted, fontSize: 12),
          suffix: Text(
            suffix,
            style: TextStyle(color: palette.textMuted, fontSize: 11),
          ),
          isDense: true,
          filled: true,
          fillColor: palette.bgCard,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: palette.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: palette.accent, width: 1.5),
          ),
        ),
        validator: (v) {
          final s = v?.trim().replaceAll(',', '.') ?? '';
          if (s.isEmpty) return null; // opcional
          final parsed = double.tryParse(s);
          if (parsed == null) return 'Número inválido'; // i18n: Fase W2
          if (parsed < 0 || parsed > 500) return 'Fuera de rango'; // i18n: Fase W2
          return null;
        },
      ),
    );
  }
}

// ── Rendimiento (PR#2) ────────────────────────────────────────────────────────

/// Row de una prueba de rendimiento individual.
class _RendimientoRow extends StatefulWidget {
  const _RendimientoRow({
    required this.test,
    required this.palette,
    required this.onDelete,
    required this.onEdit,
  });

  final PerformanceTest test;
  final AppPalette palette;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  State<_RendimientoRow> createState() => _RendimientoRowState();
}

class _RendimientoRowState extends State<_RendimientoRow> {
  bool _expanded = false;

  /// Summary line: los 3 campos más marker del test — CMJ, Sprint 10m,
  /// Sentadilla 1RM. Si alguno es null se omite.
  String _summary() {
    final t = widget.test;
    final parts = <String>[];
    if (t.cmjCm != null) parts.add('CMJ ${t.cmjCm} cm');
    if (t.sprint10mS != null) parts.add('10m ${t.sprint10mS}s');
    if (t.squat1rmKg != null) parts.add('Sent. ${t.squat1rmKg} kg');
    if (parts.isEmpty) return 'Sin métricas cargadas'; // i18n: Fase W2
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.test;
    final palette = widget.palette;
    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _expanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  size: 22,
                  color: palette.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fmtDate(t.recordedAt),
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _summary(),
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Editar', // i18n: Fase W2
                  onPressed: widget.onEdit,
                  icon: Icon(Icons.edit,
                      size: 18, color: palette.textMuted),
                ),
                IconButton(
                  tooltip: 'Eliminar', // i18n: Fase W2
                  onPressed: widget.onDelete,
                  icon: Icon(TreinoIcon.trash,
                      size: 18, color: palette.danger),
                ),
              ],
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(30, 12, 8, 0),
                child: _RendimientoDetail(test: t, palette: palette),
              ),
          ],
        ),
      ),
    );
  }
}

/// Detalle expandido de una prueba de rendimiento. Muestra solo los campos
/// con valor cargado, agrupados por categoría (saltos / sprints / 1RM /
/// resistencia).
class _RendimientoDetail extends StatelessWidget {
  const _RendimientoDetail(
      {required this.test, required this.palette});

  final PerformanceTest test;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final t = test;
    final entries = <(String, String)>[
      // Saltos
      if (t.cmjCm != null) ('CMJ', '${t.cmjCm} cm'),
      if (t.squatJumpCm != null) ('Squat Jump', '${t.squatJumpCm} cm'),
      if (t.abalakovCm != null) ('Abalakov', '${t.abalakovCm} cm'),
      if (t.broadJumpCm != null) ('Salto largo', '${t.broadJumpCm} cm'),
      // Sprints
      if (t.sprint10mS != null) ('Sprint 10m', '${t.sprint10mS} s'),
      if (t.sprint20mS != null) ('Sprint 20m', '${t.sprint20mS} s'),
      if (t.sprint30mS != null) ('Sprint 30m', '${t.sprint30mS} s'),
      if (t.sprint40mS != null) ('Sprint 40m', '${t.sprint40mS} s'),
      // 1RM
      if (t.squat1rmKg != null) ('Sentadilla 1RM', '${t.squat1rmKg} kg'),
      if (t.benchPress1rmKg != null)
        ('Press banca 1RM', '${t.benchPress1rmKg} kg'),
      if (t.deadlift1rmKg != null)
        ('Peso muerto 1RM', '${t.deadlift1rmKg} kg'),
      if (t.overheadPress1rmKg != null)
        ('Press militar 1RM', '${t.overheadPress1rmKg} kg'),
      if (t.pullUp1rmKg != null) ('Dominada 1RM', '${t.pullUp1rmKg} kg'),
      // Resistencia
      if (t.vo2maxMlKgMin != null)
        ('VO2 máx', '${t.vo2maxMlKgMin} ml/kg/min'),
      if (t.courseNavetteLevel != null)
        ('Course Navette', 'nivel ${t.courseNavetteLevel}'),
      if (t.cooperMeters != null) ('Cooper', '${t.cooperMeters} m'),
      if (t.sitAndReachCm != null)
        ('Sit & Reach', '${t.sitAndReachCm} cm'),
    ];

    if (entries.isEmpty && (t.notes ?? '').isEmpty) {
      return Text(
        'Esta prueba no tiene valores cargados.', // i18n: Fase W2
        style: TextStyle(color: palette.textMuted, fontSize: 13),
      );
    }

    final half = (entries.length / 2).ceil();
    final left = entries.take(half).toList();
    final right = entries.skip(half).toList();

    Widget colFor(List<(String, String)> items) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (label, value) in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 140,
                      child: Text(
                        label,
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        value,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: colFor(left)),
            const SizedBox(width: 24),
            Expanded(child: colFor(right)),
          ],
        ),
        if ((t.notes ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Nota',
            style: TextStyle(
              color: palette.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            t.notes!,
            style: TextStyle(color: palette.textPrimary, fontSize: 13),
          ),
        ],
      ],
    );
  }
}

/// Dialog modal para cargar (o editar) una prueba de rendimiento.
///
/// Todos los campos opcionales. Saltos siempre expandido (la sección más
/// común según el research de PT); Sprints, 1RM y Resistencia colapsables
/// por default para no abrumar.
///
/// PR#3 (2026-07-03): si [initial] es no-nulo → **modo edición**. Mismo
/// pattern que `_NuevaMedicionDialog`.
class _NuevoRendimientoDialog extends ConsumerStatefulWidget {
  const _NuevoRendimientoDialog({
    required this.athleteId,
    required this.trainerUid,
    this.initial,
  });

  final String athleteId;
  final String trainerUid;
  final PerformanceTest? initial;

  @override
  ConsumerState<_NuevoRendimientoDialog> createState() =>
      _NuevoRendimientoDialogState();
}

class _NuevoRendimientoDialogState
    extends ConsumerState<_NuevoRendimientoDialog> {
  final _formKey = GlobalKey<FormState>();

  // Saltos
  final _cmjC = TextEditingController();
  final _squatJumpC = TextEditingController();
  final _abalakovC = TextEditingController();
  final _broadJumpC = TextEditingController();
  // Sprints
  final _sprint10C = TextEditingController();
  final _sprint20C = TextEditingController();
  final _sprint30C = TextEditingController();
  final _sprint40C = TextEditingController();
  // 1RM
  final _squat1rmC = TextEditingController();
  final _bench1rmC = TextEditingController();
  final _deadlift1rmC = TextEditingController();
  final _overhead1rmC = TextEditingController();
  final _pullUp1rmC = TextEditingController();
  // Resistencia
  final _vo2maxC = TextEditingController();
  final _courseNavetteC = TextEditingController();
  final _cooperC = TextEditingController();
  final _sitAndReachC = TextEditingController();
  // Meta
  final _notesC = TextEditingController();

  bool _sprintsExpanded = false;
  bool _oneRmExpanded = false;
  bool _resistExpanded = false;
  bool _saving = false;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) return;

    void set(TextEditingController c, double? v) {
      if (v != null) c.text = v.toString();
    }

    set(_cmjC, initial.cmjCm);
    set(_squatJumpC, initial.squatJumpCm);
    set(_abalakovC, initial.abalakovCm);
    set(_broadJumpC, initial.broadJumpCm);
    set(_sprint10C, initial.sprint10mS);
    set(_sprint20C, initial.sprint20mS);
    set(_sprint30C, initial.sprint30mS);
    set(_sprint40C, initial.sprint40mS);
    set(_squat1rmC, initial.squat1rmKg);
    set(_bench1rmC, initial.benchPress1rmKg);
    set(_deadlift1rmC, initial.deadlift1rmKg);
    set(_overhead1rmC, initial.overheadPress1rmKg);
    set(_pullUp1rmC, initial.pullUp1rmKg);
    set(_vo2maxC, initial.vo2maxMlKgMin);
    set(_courseNavetteC, initial.courseNavetteLevel);
    set(_cooperC, initial.cooperMeters);
    set(_sitAndReachC, initial.sitAndReachCm);
    if (initial.notes != null) _notesC.text = initial.notes!;

    _sprintsExpanded = initial.sprint10mS != null ||
        initial.sprint20mS != null ||
        initial.sprint30mS != null ||
        initial.sprint40mS != null;
    _oneRmExpanded = initial.squat1rmKg != null ||
        initial.benchPress1rmKg != null ||
        initial.deadlift1rmKg != null ||
        initial.overheadPress1rmKg != null ||
        initial.pullUp1rmKg != null;
    _resistExpanded = initial.vo2maxMlKgMin != null ||
        initial.courseNavetteLevel != null ||
        initial.cooperMeters != null ||
        initial.sitAndReachCm != null;
  }

  @override
  void dispose() {
    for (final c in [
      _cmjC, _squatJumpC, _abalakovC, _broadJumpC,
      _sprint10C, _sprint20C, _sprint30C, _sprint40C,
      _squat1rmC, _bench1rmC, _deadlift1rmC, _overhead1rmC, _pullUp1rmC,
      _vo2maxC, _courseNavetteC, _cooperC, _sitAndReachC,
      _notesC,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _parse(TextEditingController c) {
    final s = c.text.trim().replaceAll(',', '.');
    if (s.isEmpty) return null;
    return double.tryParse(s);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final initial = widget.initial;
    try {
      final test = PerformanceTest(
        id: initial?.id ?? '',
        athleteId: widget.athleteId,
        recordedBy: widget.trainerUid,
        recordedAt: initial?.recordedAt ?? DateTime.now(),
        cmjCm: _parse(_cmjC),
        squatJumpCm: _parse(_squatJumpC),
        abalakovCm: _parse(_abalakovC),
        broadJumpCm: _parse(_broadJumpC),
        sprint10mS: _parse(_sprint10C),
        sprint20mS: _parse(_sprint20C),
        sprint30mS: _parse(_sprint30C),
        sprint40mS: _parse(_sprint40C),
        squat1rmKg: _parse(_squat1rmC),
        benchPress1rmKg: _parse(_bench1rmC),
        deadlift1rmKg: _parse(_deadlift1rmC),
        overheadPress1rmKg: _parse(_overhead1rmC),
        pullUp1rmKg: _parse(_pullUp1rmC),
        vo2maxMlKgMin: _parse(_vo2maxC),
        courseNavetteLevel: _parse(_courseNavetteC),
        cooperMeters: _parse(_cooperC),
        sitAndReachCm: _parse(_sitAndReachC),
        notes: _notesC.text.trim().isEmpty ? null : _notesC.text.trim(),
      );
      final repo = ref.read(performanceTestRepositoryProvider);
      if (_isEditing) {
        await repo.update(test);
      } else {
        await repo.add(test);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(_isEditing
              ? 'Prueba actualizada.' // i18n: Fase W2
              : 'Prueba guardada.'), // i18n: Fase W2
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No pudimos guardar la prueba.'), // i18n: Fase W2
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Dialog(
      backgroundColor: palette.bg,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _isEditing
                    ? 'Editar prueba de rendimiento' // i18n: Fase W2
                    : 'Nueva prueba de rendimiento', // i18n: Fase W2
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Cargá los campos que hayas medido. Todos son opcionales.', // i18n: Fase W2
                style: TextStyle(color: palette.textMuted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _NuevaMedicionSection(
                          title: 'SALTOS', // i18n: Fase W2
                          palette: palette,
                          expanded: true,
                          onToggle: null,
                          children: [
                            _NuevaMedicionField(
                                label: 'CMJ',
                                suffix: 'cm',
                                controller: _cmjC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Squat Jump',
                                suffix: 'cm',
                                controller: _squatJumpC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Abalakov',
                                suffix: 'cm',
                                controller: _abalakovC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Salto largo',
                                suffix: 'cm',
                                controller: _broadJumpC,
                                palette: palette),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _NuevaMedicionSection(
                          title: 'SPRINTS', // i18n: Fase W2
                          palette: palette,
                          expanded: _sprintsExpanded,
                          onToggle: () => setState(
                              () => _sprintsExpanded = !_sprintsExpanded),
                          children: [
                            _NuevaMedicionField(
                                label: 'Sprint 10m',
                                suffix: 's',
                                controller: _sprint10C,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Sprint 20m',
                                suffix: 's',
                                controller: _sprint20C,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Sprint 30m',
                                suffix: 's',
                                controller: _sprint30C,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Sprint 40m',
                                suffix: 's',
                                controller: _sprint40C,
                                palette: palette),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _NuevaMedicionSection(
                          title: 'FUERZA MÁXIMA 1RM', // i18n: Fase W2
                          palette: palette,
                          expanded: _oneRmExpanded,
                          onToggle: () =>
                              setState(() => _oneRmExpanded = !_oneRmExpanded),
                          children: [
                            _NuevaMedicionField(
                                label: 'Sentadilla',
                                suffix: 'kg',
                                controller: _squat1rmC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Press banca',
                                suffix: 'kg',
                                controller: _bench1rmC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Peso muerto',
                                suffix: 'kg',
                                controller: _deadlift1rmC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Press militar',
                                suffix: 'kg',
                                controller: _overhead1rmC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Dominada',
                                suffix: 'kg',
                                controller: _pullUp1rmC,
                                palette: palette),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _NuevaMedicionSection(
                          title: 'RESISTENCIA / FLEXIBILIDAD', // i18n: Fase W2
                          palette: palette,
                          expanded: _resistExpanded,
                          onToggle: () => setState(
                              () => _resistExpanded = !_resistExpanded),
                          children: [
                            _NuevaMedicionField(
                                label: 'VO2 máx',
                                suffix: 'ml/kg/min',
                                controller: _vo2maxC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Course Navette',
                                suffix: 'nivel',
                                controller: _courseNavetteC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Cooper',
                                suffix: 'm',
                                controller: _cooperC,
                                palette: palette),
                            _NuevaMedicionField(
                                label: 'Sit & Reach',
                                suffix: 'cm',
                                controller: _sitAndReachC,
                                palette: palette),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _notesC,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: 'Nota (opcional)', // i18n: Fase W2
                            labelStyle:
                                TextStyle(color: palette.textMuted),
                            filled: true,
                            fillColor: palette.bgCard,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide:
                                  BorderSide(color: palette.border),
                            ),
                          ),
                          style: TextStyle(color: palette.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'), // i18n: Fase W2
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.accent,
                      foregroundColor: palette.bg,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      shape: const StadiumBorder(),
                    ),
                    child: _saving
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: palette.bg,
                            ),
                          )
                        : const Text('GUARDAR'), // i18n: Fase W2
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── _SeguimientoTab ──────────────────────────────────────────────────────────

/// Coach Hub web — Tab «Seguimiento» del alumno detail.
///
/// Log cronológico privado del PF sobre un alumno. Múltiples entradas
/// datadas con tag categórico (general/entrenamiento/nutricion/molestia/
/// motivacion). Diferencia con Notas privadas (hoja libre única):
/// Seguimiento es un TIMELINE de eventos/observaciones — cada entrada tiene
/// su timestamp y tag.
///
/// Reusa `followUpEntriesProvider` (stream DESC) +
/// `FollowUpEntryRepository.add/update/delete`. Trainer-only en rules.
class _SeguimientoTab extends ConsumerStatefulWidget {
  const _SeguimientoTab({required this.athleteId});

  final String athleteId;

  @override
  ConsumerState<_SeguimientoTab> createState() => _SeguimientoTabState();
}

class _SeguimientoTabState extends ConsumerState<_SeguimientoTab> {
  Future<void> _openDialog({FollowUpEntry? initial}) async {
    final trainerUid = ref.read(currentUidProvider);
    if (trainerUid == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _NuevaEntradaSeguimientoDialog(
        athleteId: widget.athleteId,
        trainerUid: trainerUid,
        initial: initial,
      ),
    );
  }

  Future<void> _confirmDelete(FollowUpEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar entrada?'), // i18n: Fase W2
        content: Text(
          'La entrada del ${fmtDate(entry.recordedAt)} se va a borrar. '
          'No se puede deshacer.', // i18n: Fase W2
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'), // i18n: Fase W2
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmar'), // i18n: Fase W2
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(followUpEntryRepositoryProvider).delete(entry.id);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No pudimos eliminar la entrada.'), // i18n: Fase W2
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final trainerUid = ref.watch(currentUidProvider);
    if (trainerUid == null) return const SizedBox.shrink();
    final entriesAsync = ref.watch(
      followUpEntriesProvider(
        (trainerId: trainerUid, athleteId: widget.athleteId),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Seguimiento privado', // i18n: Fase W2
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Bitácora del PF con observaciones, molestias y decisiones. Solo vos las ves.', // i18n: Fase W2
                      style: TextStyle(
                          color: palette.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _openDialog(),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('NUEVA ENTRADA'), // i18n: Fase W2
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.bg,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 12),
                  shape: const StadiumBorder(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Builder(
              builder: (_) {
                if (entriesAsync.hasValue) {
                  final entries = entriesAsync.requireValue;
                  if (entries.isEmpty) {
                    return Center(
                      child: Text(
                        'No hay entradas de seguimiento todavía.', // i18n: Fase W2
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: palette.textMuted, fontSize: 14),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _SeguimientoEntryCard(
                      entry: entries[i],
                      palette: palette,
                      onEdit: () => _openDialog(initial: entries[i]),
                      onDelete: () => _confirmDelete(entries[i]),
                    ),
                  );
                }
                if (entriesAsync.hasError) {
                  return Center(
                    child: Text(
                      'No pudimos cargar el seguimiento.', // i18n: Fase W2
                      style: TextStyle(
                          color: palette.textMuted, fontSize: 14),
                    ),
                  );
                }
                return Center(
                  child: CircularProgressIndicator(color: palette.accent),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Card de una entrada del seguimiento.
class _SeguimientoEntryCard extends StatelessWidget {
  const _SeguimientoEntryCard({
    required this.entry,
    required this.palette,
    required this.onEdit,
    required this.onDelete,
  });

  final FollowUpEntry entry;
  final AppPalette palette;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                fmtDate(entry.recordedAt),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              _TagChip(tag: entry.tag, palette: palette),
              const Spacer(),
              IconButton(
                tooltip: 'Editar', // i18n: Fase W2
                onPressed: onEdit,
                icon:
                    Icon(Icons.edit, size: 18, color: palette.textMuted),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                    minWidth: 32, minHeight: 32),
              ),
              IconButton(
                tooltip: 'Eliminar', // i18n: Fase W2
                onPressed: onDelete,
                icon: Icon(TreinoIcon.trash,
                    size: 18, color: palette.danger),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                    minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            entry.text,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip pequeño coloreado según el tag.
class _TagChip extends StatelessWidget {
  const _TagChip({required this.tag, required this.palette});

  final FollowUpTag tag;
  final AppPalette palette;

  static (String, Color) _labelAndColor(
      FollowUpTag tag, AppPalette palette) {
    switch (tag) {
      case FollowUpTag.general:
        return ('GENERAL', palette.textMuted);
      case FollowUpTag.entrenamiento:
        return ('ENTRENAMIENTO', palette.accent);
      case FollowUpTag.nutricion:
        return ('NUTRICIÓN', palette.warning);
      case FollowUpTag.molestia:
        return ('MOLESTIA', palette.danger);
      case FollowUpTag.motivacion:
        return ('MOTIVACIÓN', palette.highlight);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (label, color) = _labelAndColor(tag, palette);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Dialog modal para crear (o editar) una entrada del seguimiento.
class _NuevaEntradaSeguimientoDialog extends ConsumerStatefulWidget {
  const _NuevaEntradaSeguimientoDialog({
    required this.athleteId,
    required this.trainerUid,
    this.initial,
  });

  final String athleteId;
  final String trainerUid;
  final FollowUpEntry? initial;

  @override
  ConsumerState<_NuevaEntradaSeguimientoDialog> createState() =>
      _NuevaEntradaSeguimientoDialogState();
}

class _NuevaEntradaSeguimientoDialogState
    extends ConsumerState<_NuevaEntradaSeguimientoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _textC = TextEditingController();
  late FollowUpTag _tag;
  bool _saving = false;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial != null) {
      _textC.text = initial.text;
      _tag = initial.tag;
    } else {
      _tag = FollowUpTag.general;
    }
  }

  @override
  void dispose() {
    _textC.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final initial = widget.initial;
    final repo = ref.read(followUpEntryRepositoryProvider);
    try {
      if (_isEditing && initial != null) {
        await repo.update(
          initial.copyWith(text: _textC.text.trim(), tag: _tag),
        );
      } else {
        await repo.add(
          trainerId: widget.trainerUid,
          athleteId: widget.athleteId,
          text: _textC.text.trim(),
          tag: _tag,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(_isEditing
              ? 'Entrada actualizada.' // i18n: Fase W2
              : 'Entrada guardada.'), // i18n: Fase W2
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content:
              Text('No pudimos guardar la entrada.'), // i18n: Fase W2
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Dialog(
      backgroundColor: palette.bg,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isEditing
                      ? 'Editar entrada' // i18n: Fase W2
                      : 'Nueva entrada de seguimiento', // i18n: Fase W2
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<FollowUpTag>(
                  initialValue: _tag,
                  onChanged: (v) {
                    if (v != null) setState(() => _tag = v);
                  },
                  decoration: InputDecoration(
                    labelText: 'Categoría', // i18n: Fase W2
                    labelStyle: TextStyle(color: palette.textMuted),
                    filled: true,
                    fillColor: palette.bgCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: palette.border),
                    ),
                  ),
                  style: TextStyle(color: palette.textPrimary, fontSize: 14),
                  dropdownColor: palette.bgCard,
                  items: [
                    for (final t in FollowUpTag.values)
                      DropdownMenuItem(
                        value: t,
                        child: Text(_TagChip._labelAndColor(t, palette).$1),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _textC,
                  maxLines: 6,
                  minLines: 4,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Texto', // i18n: Fase W2
                    hintText:
                        'Ej: Cambio a bloque de fuerza, foco en press banca…', // i18n: Fase W2
                    labelStyle: TextStyle(color: palette.textMuted),
                    hintStyle: TextStyle(
                      color: palette.textMuted.withValues(alpha: 0.6),
                    ),
                    filled: true,
                    fillColor: palette.bgCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: palette.border),
                    ),
                  ),
                  style: TextStyle(color: palette.textPrimary, fontSize: 14),
                  validator: (v) {
                    final s = v?.trim() ?? '';
                    if (s.isEmpty) return 'Escribí algo'; // i18n: Fase W2
                    if (s.length > 4900) {
                      return 'Muy largo (max 4900 caracteres)'; // i18n: Fase W2
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'), // i18n: Fase W2
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: palette.accent,
                        foregroundColor: palette.bg,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: const StadiumBorder(),
                      ),
                      child: _saving
                          ? SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: palette.bg,
                              ),
                            )
                          : const Text('GUARDAR'), // i18n: Fase W2
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── _NutricionTab ────────────────────────────────────────────────────────────

/// Coach Hub web — Tab «Nutrición» del alumno detail (W2+).
///
/// El PF arma un plan de alimentación estructurado por comidas (desayuno,
/// almuerzo, cena…), cada una con grupos de alimentos (hidratos, proteínas,
/// vegetales…) y cada grupo con opciones que el alumno elige.
///
/// Modelo: `NutritionPlan → Meal → FoodGroup → FoodOption`. Ver
/// `nutrition_plan.dart` para detalle. En este MVP solo el PF arma el plan;
/// el alumno NO lo ve todavía en mobile (feature scoped aparte).
///
/// Comportamiento:
/// - Al abrir por primera vez muestra 6 comidas preset (desayuno, media
///   mañana, almuerzo, merienda, colación, cena) con grupos vacíos.
/// - El PF edita libremente y guarda con botón explícito «GUARDAR PLAN».
/// - Cambios locales viven en `_draft` — el stream de Firestore se lee al
///   entrar y cuando el PF guarda vuelve a persistir todo el doc.
/// - Sin auto-save (evitamos writes innecesarios y forms rotos).
class _NutricionTab extends ConsumerStatefulWidget {
  const _NutricionTab({required this.athleteId});

  final String athleteId;

  @override
  ConsumerState<_NutricionTab> createState() => _NutricionTabState();
}

class _NutricionTabState extends ConsumerState<_NutricionTab> {
  NutritionPlan? _draft;
  bool _loadedOnce = false;
  bool _saving = false;
  int _idCounter = 0;

  String _newId(String prefix) {
    _idCounter++;
    // Sin Date.now() porque en tests / hot reload no queremos ids
    // dependientes de tiempo real. El id solo tiene que ser único en la
    // sesión — Firestore acepta cualquier string.
    return '$prefix-$_idCounter';
  }

  void _seedIfNeeded(NutritionPlan? persisted, String trainerUid) {
    if (_loadedOnce) return;
    _loadedOnce = true;
    if (persisted != null) {
      _draft = persisted;
    } else {
      _draft = NutritionPlan(
        id: '${trainerUid}_${widget.athleteId}',
        trainerId: trainerUid,
        athleteId: widget.athleteId,
        title: '',
        meals: defaultPresetMeals(),
        updatedAt: DateTime(2000),
      );
    }
  }

  @override
  void didUpdateWidget(covariant _NutricionTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset cross-alumno para que el swap no muestre el plan del anterior.
    if (oldWidget.athleteId != widget.athleteId) {
      _draft = null;
      _loadedOnce = false;
      _idCounter = 0;
    }
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null || _saving) return;
    final messenger = ScaffoldMessenger.of(context);
    final clean = draft.sanitizeForSave();
    if (clean.meals.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'El plan está vacío. Agregá al menos una comida con nombre.', // i18n: Fase W2
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(nutritionPlanRepositoryProvider).save(clean);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Plan guardado.'), // i18n: Fase W2
          duration: Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No pudimos guardar el plan.'), // i18n: Fase W2
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Draft mutators ─────────────────────────────────────────────────────
  void _updateTitle(String title) {
    setState(() => _draft = _draft!.copyWith(title: title));
  }

  void _addMeal() {
    setState(() {
      _draft = _draft!.copyWith(meals: [
        ..._draft!.meals,
        Meal(
          id: _newId('meal'),
          // Vacío intencional — el placeholder "Nueva comida" se muestra
          // como hintText del TextFormField. Sin nombre real, el sanitize
          // dropea la comida al guardar si el PF no la completa.
          name: '',
          time: '',
          groups: const [],
        ),
      ]);
    });
  }

  void _removeMeal(String mealId) {
    setState(() {
      _draft = _draft!.copyWith(
        meals: _draft!.meals.where((m) => m.id != mealId).toList(),
      );
    });
  }

  void _updateMeal(String mealId, Meal updated) {
    setState(() {
      _draft = _draft!.copyWith(
        meals: _draft!.meals
            .map((m) => m.id == mealId ? updated : m)
            .toList(growable: false),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final trainerUid = ref.watch(currentUidProvider);
    if (trainerUid == null) return const SizedBox.shrink();
    final planAsync = ref.watch(
      nutritionPlanProvider(
        (trainerId: trainerUid, athleteId: widget.athleteId),
      ),
    );

    if (planAsync.hasValue) {
      _seedIfNeeded(planAsync.requireValue, trainerUid);
    } else if (planAsync.hasError && !_loadedOnce) {
      // Error al leer — dejamos que el PF arme el plan igual (arranca desde
      // presets). El save intentará persistir; si sigue fallando el error
      // se muestra en el snackbar.
      _seedIfNeeded(null, trainerUid);
    }

    if (_draft == null) {
      return Center(child: CircularProgressIndicator(color: palette.accent));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Plan de alimentación', // i18n: Fase W2
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Armá el plan por comidas, grupos y opciones. Solo vos lo ves.', // i18n: Fase W2
                      style: TextStyle(
                          color: palette.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.bg,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  shape: const StadiumBorder(),
                ),
                child: _saving
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: palette.bg,
                        ),
                      )
                    : const Text('GUARDAR PLAN'), // i18n: Fase W2
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              // Small top padding — el label flotante del TextFormField
              // extiende ~8px arriba del border cuando el field tiene
              // valor. Sin este padding el label queda clippeado por el
              // SingleChildScrollView al scrollear.
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    initialValue: _draft!.title,
                    decoration: InputDecoration(
                      labelText: 'Título del plan (opcional)', // i18n: Fase W2
                      hintText:
                          'Ej: Progresión 4 - Semana 9 en adelante', // i18n: Fase W2
                      labelStyle: TextStyle(color: palette.textMuted),
                      hintStyle: TextStyle(
                        color: palette.textMuted.withValues(alpha: 0.6),
                      ),
                      filled: true,
                      fillColor: palette.bgCard,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: palette.border),
                      ),
                    ),
                    style: TextStyle(
                        color: palette.textPrimary, fontSize: 14),
                    onChanged: _updateTitle,
                  ),
                  const SizedBox(height: 16),
                  for (final meal in _draft!.meals)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _MealEditor(
                        meal: meal,
                        palette: palette,
                        newIdFor: _newId,
                        onChanged: (u) => _updateMeal(meal.id, u),
                        onDelete: () => _removeMeal(meal.id),
                      ),
                    ),
                  const SizedBox(height: 4),
                  OutlinedButton.icon(
                    onPressed: _addMeal,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('AGREGAR COMIDA'), // i18n: Fase W2
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.accent,
                      side: BorderSide(color: palette.accent),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      shape: const StadiumBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Editor de una comida (nombre + hora + grupos). Se colapsa con un ExpansionTile
/// para que el PF pueda tener muchas comidas y no perder el foco.
class _MealEditor extends StatelessWidget {
  const _MealEditor({
    required this.meal,
    required this.palette,
    required this.newIdFor,
    required this.onChanged,
    required this.onDelete,
  });

  final Meal meal;
  final AppPalette palette;
  final String Function(String prefix) newIdFor;
  final ValueChanged<Meal> onChanged;
  final VoidCallback onDelete;

  void _updateGroup(FoodGroup updated) {
    onChanged(meal.copyWith(
      groups: meal.groups
          .map((g) => g.id == updated.id ? updated : g)
          .toList(growable: false),
    ));
  }

  void _removeGroup(String groupId) {
    onChanged(meal.copyWith(
      groups: meal.groups.where((g) => g.id != groupId).toList(),
    ));
  }

  void _addGroup() {
    onChanged(meal.copyWith(groups: [
      ...meal.groups,
      FoodGroup(
        id: newIdFor('group'),
        // Vacío intencional — placeholder "Nuevo grupo" en el hintText del
        // TextFormField. Sin nombre real, el sanitize dropea el grupo.
        name: '',
        selectionMode: SelectionMode.chooseOne,
        options: const [],
      ),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Theme(
        // Quitar los divisores default y el splash raro del ExpansionTile.
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          iconColor: palette.textMuted,
          collapsedIconColor: palette.textMuted,
          title: Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: meal.name,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Nombre de la comida', // i18n: Fase W2
                    hintStyle: TextStyle(
                      color: palette.textMuted.withValues(alpha: 0.6),
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  onChanged: (v) => onChanged(meal.copyWith(name: v)),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: TextFormField(
                  initialValue: meal.time ?? '',
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Hora', // i18n: Fase W2
                    hintStyle: TextStyle(
                      color: palette.textMuted.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                    prefixIcon:
                        Icon(Icons.schedule, size: 14, color: palette.textMuted),
                    prefixIconConstraints:
                        const BoxConstraints(minWidth: 22, minHeight: 22),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style:
                      TextStyle(color: palette.textPrimary, fontSize: 12),
                  onChanged: (v) => onChanged(meal.copyWith(time: v)),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Eliminar comida', // i18n: Fase W2
                onPressed: onDelete,
                icon: Icon(TreinoIcon.trash, size: 16, color: palette.danger),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
          children: [
            for (final group in meal.groups)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _GroupEditor(
                  group: group,
                  palette: palette,
                  newIdFor: newIdFor,
                  onChanged: _updateGroup,
                  onDelete: () => _removeGroup(group.id),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addGroup,
                icon: const Icon(Icons.add, size: 14),
                label: const Text('AGREGAR GRUPO'), // i18n: Fase W2
                style: TextButton.styleFrom(
                  foregroundColor: palette.accent,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Editor de un grupo de alimentos dentro de una comida.
class _GroupEditor extends StatelessWidget {
  const _GroupEditor({
    required this.group,
    required this.palette,
    required this.newIdFor,
    required this.onChanged,
    required this.onDelete,
  });

  final FoodGroup group;
  final AppPalette palette;
  final String Function(String prefix) newIdFor;
  final ValueChanged<FoodGroup> onChanged;
  final VoidCallback onDelete;

  void _updateOption(FoodOption updated) {
    onChanged(group.copyWith(
      options: group.options
          .map((o) => o.id == updated.id ? updated : o)
          .toList(growable: false),
    ));
  }

  void _removeOption(String optionId) {
    onChanged(group.copyWith(
      options: group.options.where((o) => o.id != optionId).toList(),
    ));
  }

  void _addOption() {
    onChanged(group.copyWith(options: [
      ...group.options,
      FoodOption(id: newIdFor('opt'), name: ''),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.bg,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: group.name,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Nombre del grupo', // i18n: Fase W2
                    hintStyle: TextStyle(
                      color: palette.textMuted.withValues(alpha: 0.6),
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                  onChanged: (v) => onChanged(group.copyWith(name: v)),
                ),
              ),
              const SizedBox(width: 8),
              _SelectionModeSelector(
                mode: group.selectionMode,
                palette: palette,
                onChanged: (m) =>
                    onChanged(group.copyWith(selectionMode: m)),
              ),
              IconButton(
                tooltip: 'Eliminar grupo', // i18n: Fase W2
                onPressed: onDelete,
                icon: Icon(TreinoIcon.trash,
                    size: 14, color: palette.danger),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 26, minHeight: 26),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final option in group.options)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _OptionRow(
                option: option,
                palette: palette,
                onChanged: _updateOption,
                onDelete: () => _removeOption(option.id),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addOption,
              icon: const Icon(Icons.add, size: 12),
              label: const Text('AGREGAR OPCIÓN'), // i18n: Fase W2
              style: TextButton.styleFrom(
                foregroundColor: palette.accent,
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                textStyle: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Toggle compacto entre modo de selección `chooseOne` y `all` — se muestra
/// como dos pills side-by-side.
class _SelectionModeSelector extends StatelessWidget {
  const _SelectionModeSelector({
    required this.mode,
    required this.palette,
    required this.onChanged,
  });

  final SelectionMode mode;
  final AppPalette palette;
  final ValueChanged<SelectionMode> onChanged;

  Widget _pill(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: active
              ? palette.accent.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(
            color: active ? palette.accent : palette.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? palette.accent : palette.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _pill(
          'ELEGIR UNA', // i18n: Fase W2
          mode == SelectionMode.chooseOne,
          () => onChanged(SelectionMode.chooseOne),
        ),
        const SizedBox(width: 4),
        _pill(
          'TODAS', // i18n: Fase W2
          mode == SelectionMode.all,
          () => onChanged(SelectionMode.all),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// Fila de una opción del grupo: nombre + cantidad + unidad + notas.
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.palette,
    required this.onChanged,
    required this.onDelete,
  });

  final FoodOption option;
  final AppPalette palette;
  final ValueChanged<FoodOption> onChanged;
  final VoidCallback onDelete;

  InputDecoration _dec(String hint) => InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: TextStyle(
          color: palette.textMuted.withValues(alpha: 0.6),
          fontSize: 12,
        ),
        filled: true,
        fillColor: palette.bgCard,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: palette.border),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final textStyle =
        TextStyle(color: palette.textPrimary, fontSize: 12);
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: TextFormField(
            initialValue: option.name,
            decoration: _dec('Alimento (ej: 5 discos de arroz)'), // i18n: Fase W2
            style: textStyle,
            onChanged: (v) => onChanged(option.copyWith(name: v)),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 2,
          child: TextFormField(
            initialValue: option.quantity ?? '',
            decoration: _dec('Cant.'), // i18n: Fase W2
            style: textStyle,
            onChanged: (v) => onChanged(
                option.copyWith(quantity: v.isEmpty ? null : v)),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 3,
          child: TextFormField(
            initialValue: option.unit ?? '',
            decoration: _dec('Unidad (grs, ml…)'), // i18n: Fase W2
            style: textStyle,
            onChanged: (v) =>
                onChanged(option.copyWith(unit: v.isEmpty ? null : v)),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          flex: 4,
          child: TextFormField(
            initialValue: option.notes ?? '',
            decoration: _dec('Notas (marca, aclaraciones…)'), // i18n: Fase W2
            style: textStyle,
            onChanged: (v) =>
                onChanged(option.copyWith(notes: v.isEmpty ? null : v)),
          ),
        ),
        IconButton(
          tooltip: 'Eliminar opción', // i18n: Fase W2
          onPressed: onDelete,
          icon: Icon(TreinoIcon.trash, size: 12, color: palette.danger),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        ),
      ],
    );
  }
}
