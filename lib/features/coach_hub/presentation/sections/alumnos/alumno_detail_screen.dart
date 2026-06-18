import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/gyms/application/gym_providers.dart';
import 'package:treino/features/measurements/application/measurement_providers.dart';
import 'package:treino/features/measurements/presentation/widgets/measurement_progress_chart.dart';
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart';
import 'package:treino/features/payments/application/payment_providers.dart';
import 'package:treino/features/payments/domain/athlete_billing.dart'
    show BillingCadence;
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_status.dart';
import 'package:treino/features/workout/domain/session.dart';

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
  ];
  static const _resumenIndex = 0;
  static const _entrenamientoIndex = 1;
  static const _progresoIndex = 3;
  static const _pagosIndex = 4;

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
                  else if (i == _progresoIndex)
                    _ProgresoTab(athleteId: athleteId)
                  else if (i == _pagosIndex)
                    _PagosTab(athleteId: athleteId)
                  else
                    _TabPlaceholder(label: _tabs[i]),
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
    required this.palette,
  });

  final UserPublicProfile? profile;
  final TrainerLink? link;
  final AlumnoEstado? estado;
  final String? gymName;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final name = profile?.displayName ?? 'Atleta'; // i18n: Fase W2
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final sesiones = profile?.workoutsCount ?? 0;
    final racha = profile?.racha ?? 0;
    final avatarUrl = profile?.avatarUrl;
    final desde = link?.acceptedAt;

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
                                estado!.label,
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
                            'Desde ${_fmtDate(desde)}', // i18n: Fase W2
                            style: TextStyle(
                                color: palette.textMuted, fontSize: 13),
                          ),
                      ],
                    ),
                  ],
                ),
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

class _TabPlaceholder extends StatelessWidget {
  const _TabPlaceholder({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Próximamente.', // i18n: Fase W2
            style: TextStyle(color: palette.textMuted, fontSize: 15),
          ),
        ],
      ),
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
    return measAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => _muted(
          palette, 'No se pudieron cargar las mediciones.'), // i18n: Fase W2
      data: (ms) {
        if (ms.isEmpty) {
          return _muted(
              palette, 'Sin mediciones cargadas todavía.'); // i18n: Fase W2
        }
        final latest = ms.last;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              const SizedBox(height: 14),
              Text(
                'Próximamente: rendimiento y evolución de cargas.', // i18n: Fase W2
                style: TextStyle(color: palette.textMuted, fontSize: 12),
              ),
            ],
          ),
        );
      },
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

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

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

/// Monto en pesos con separador de miles es-AR (28000 → "$28.000").
String _fmtArs(int amount) {
  final digits = amount.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buf.write('.');
    buf.write(digits[i]);
  }
  return '${amount < 0 ? '-' : ''}\$$buf';
}

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
                onPressed: () => _registrarPago(context, ref, athleteId),
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
          _EstadoCuentaCard(
            palette: palette,
            pending: pending,
            onMarcarPagado: (c) => _marcarPagado(context, ref, c),
          ),
          const SizedBox(height: 20),
          _sectionLabel(palette, 'HISTORIAL DE PAGOS'), // i18n: Fase W2
          const SizedBox(height: 10),
          if (history.isEmpty)
            _muted(palette, 'Sin pagos registrados todavía.') // i18n: Fase W2
          else
            _PagosTable(payments: history, palette: palette),
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

class _EstadoCuentaCard extends StatefulWidget {
  const _EstadoCuentaCard({
    required this.palette,
    required this.pending,
    required this.onMarcarPagado,
  });

  final AppPalette palette;
  final List<CobroPendiente> pending;
  final Future<void> Function(CobroPendiente) onMarcarPagado;

  @override
  State<_EstadoCuentaCard> createState() => _EstadoCuentaCardState();
}

class _EstadoCuentaCardState extends State<_EstadoCuentaCard> {
  // Cobros con una escritura en vuelo. Deshabilita "Marcar pagado" mientras el
  // settle viaja a Firestore (write → snapshot → providers → rebuild oculta la
  // fila): sin esto, volver a tocar el botón en esa ventana doble-cobra.
  final _inFlight = <String>{};

  String _key(CobroPendiente c) =>
      '${c.athleteId}|${c.cadence.name}|${c.concept}|${c.amountArs}';

  Future<void> _tap(CobroPendiente c) async {
    final k = _key(c);
    if (_inFlight.contains(k)) return;
    setState(() => _inFlight.add(k));
    try {
      await widget.onMarcarPagado(c);
    } finally {
      if (mounted) setState(() => _inFlight.remove(k));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final pending = widget.pending;
    final Widget inner;
    if (pending.isEmpty) {
      inner = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sin cobros pendientes', // i18n: Fase W2
              style: TextStyle(color: palette.textMuted, fontSize: 12)),
          const SizedBox(height: 4),
          Text('Al día', // i18n: Fase W2
              style: TextStyle(
                  color: palette.accent,
                  fontSize: 24,
                  fontWeight: FontWeight.w700)),
        ],
      );
    } else {
      final total = pending.fold<int>(0, (sum, c) => sum + c.amountArs);
      inner = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pendiente de cobro', // i18n: Fase W2
              style: TextStyle(color: palette.textMuted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(_fmtArs(total),
              style: TextStyle(
                  color: palette.warning,
                  fontSize: 24,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          for (final c in pending)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.concept,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: palette.textPrimary, fontSize: 14)),
                        Text(_fmtArs(c.amountArs),
                            style: TextStyle(
                                color: palette.textMuted, fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed:
                        _inFlight.contains(_key(c)) ? null : () => _tap(c),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: palette.accent,
                      side: BorderSide(color: palette.border),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Marcar pagado', // i18n: Fase W2
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: inner,
    );
  }
}

void _pagoSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

/// Construye un Payment pagado para settlear un cobro recurrente. El [periodKey]
/// debe matchear el que computa `pagosPorCobrarProvider` (month/ISO-week) para
/// que el cobro desaparezca tras marcarlo; `null` para porSesión (sin período).
Payment _paidPaymentFor(
  String trainerId,
  CobroPendiente cobro,
  DateTime now,
  String? periodKey,
) =>
    Payment(
      id: '',
      trainerId: trainerId,
      athleteId: cobro.athleteId,
      amountArs: cobro.amountArs,
      concept: cobro.concept,
      status: PaymentStatus.paid,
      periodKey: periodKey,
      createdAt: now,
      paidAt: now,
    );

Future<void> _marcarPagado(
    BuildContext context, WidgetRef ref, CobroPendiente cobro) async {
  final palette = AppPalette.of(context);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: palette.bgCard,
      title: Text('¿Marcar como cobrado?', // i18n: Fase W2
          style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 18)),
      content: Text('${cobro.concept} — ${_fmtArs(cobro.amountArs)}',
          style: TextStyle(color: palette.textMuted, fontSize: 14)),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancelar', // i18n: Fase W2
                style: TextStyle(color: palette.textMuted))),
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Cobrado', // i18n: Fase W2
                style: TextStyle(
                    color: palette.accent, fontWeight: FontWeight.w700))),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final trainerId = ref.read(currentUidProvider);
  if (trainerId == null) return;
  final repo = ref.read(paymentRepositoryProvider);
  final now = DateTime.now().toUtc();
  try {
    switch (cobro.cadence) {
      case BillingCadence.suelto:
        await repo.markManyPaid(cobro.pendingPaymentIds, now);
      case BillingCadence.mensual:
        await repo.add(_paidPaymentFor(trainerId, cobro, now,
            '${now.year}-${now.month.toString().padLeft(2, '0')}'));
      case BillingCadence.semanal:
        await repo
            .add(_paidPaymentFor(trainerId, cobro, now, isoWeekPeriodKey(now)));
      case BillingCadence.porSesion:
        await repo.add(_paidPaymentFor(trainerId, cobro, now, null));
    }
    if (context.mounted) {
      _pagoSnack(context, 'Cobro registrado.'); // i18n: Fase W2
    }
  } catch (_) {
    if (context.mounted) {
      _pagoSnack(
          context, 'No pudimos guardar. Intentá de nuevo.'); // i18n: Fase W2
    }
  }
}

Future<void> _registrarPago(
    BuildContext context, WidgetRef ref, String athleteId) async {
  final result = await showDialog<({int amount, String concept})>(
    context: context,
    builder: (_) => const _RegistrarPagoDialog(),
  );
  if (result == null) return;

  final trainerId = ref.read(currentUidProvider);
  if (trainerId == null) return;
  final now = DateTime.now().toUtc();
  try {
    await ref.read(paymentRepositoryProvider).add(Payment(
          id: '',
          trainerId: trainerId,
          athleteId: athleteId,
          amountArs: result.amount,
          concept: result.concept,
          status: PaymentStatus.paid,
          createdAt: now,
          paidAt: now,
        ));
    if (context.mounted) {
      _pagoSnack(context, 'Pago registrado.'); // i18n: Fase W2
    }
  } catch (_) {
    if (context.mounted) {
      _pagoSnack(
          context, 'No pudimos guardar. Intentá de nuevo.'); // i18n: Fase W2
    }
  }
}

/// Diálogo de alta de un pago ad-hoc (monto + concepto). Devuelve el record o
/// `null` si se cancela. Copy hardcodeada (CoachHubApp no tiene l10n delegates).
class _RegistrarPagoDialog extends StatefulWidget {
  const _RegistrarPagoDialog();

  @override
  State<_RegistrarPagoDialog> createState() => _RegistrarPagoDialogState();
}

class _RegistrarPagoDialogState extends State<_RegistrarPagoDialog> {
  final _monto = TextEditingController();
  final _concepto = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _monto.dispose();
    _concepto.dispose();
    super.dispose();
  }

  void _submit() {
    final amount = int.tryParse(_monto.text.trim());
    final concept = _concepto.text.trim();
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Ingresá un monto válido.'); // i18n: Fase W2
      return;
    }
    if (concept.isEmpty) {
      setState(() => _error = 'Completá todos los campos.'); // i18n: Fase W2
      return;
    }
    Navigator.of(context).pop((amount: amount, concept: concept));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    InputDecoration deco(String label, String hint) => InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(color: palette.textMuted),
          hintStyle: TextStyle(color: palette.textMuted),
          enabledBorder:
              OutlineInputBorder(borderSide: BorderSide(color: palette.border)),
          focusedBorder:
              OutlineInputBorder(borderSide: BorderSide(color: palette.accent)),
        );
    return AlertDialog(
      backgroundColor: palette.bgCard,
      title: Text('Registrar pago', // i18n: Fase W2
          style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 18)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _monto,
            keyboardType: TextInputType.number,
            style: TextStyle(color: palette.textPrimary),
            decoration: deco('Monto (ARS)', 'Ej: 5000'), // i18n: Fase W2
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _concepto,
            style: TextStyle(color: palette.textPrimary),
            decoration: deco('Concepto', 'Ej: Clase suelta'), // i18n: Fase W2
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: TextStyle(color: palette.danger, fontSize: 12)),
          ],
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancelar', // i18n: Fase W2
                style: TextStyle(color: palette.textMuted))),
        TextButton(
            onPressed: _submit,
            child: Text('Registrar', // i18n: Fase W2
                style: TextStyle(
                    color: palette.accent, fontWeight: FontWeight.w700))),
      ],
    );
  }
}

class _PagosTable extends StatelessWidget {
  const _PagosTable({required this.payments, required this.palette});
  final List<Payment> payments;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final h = TextStyle(
        color: palette.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5);
    final c = TextStyle(color: palette.textPrimary, fontSize: 13);
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
                Expanded(flex: 4, child: Text('CONCEPTO', style: h)),
                Expanded(
                  flex: 3,
                  child: Text('MONTO', style: h, textAlign: TextAlign.right),
                ),
                Expanded(
                  flex: 3,
                  child: Text('ESTADO', style: h, textAlign: TextAlign.right),
                ),
              ],
            ),
          ),
          for (final p in payments)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(_fmtDate(p.createdAt), style: c),
                  ),
                  Expanded(
                    flex: 4,
                    child: Text(p.concept,
                        overflow: TextOverflow.ellipsis, style: c),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(_fmtArs(p.amountArs),
                        style: c, textAlign: TextAlign.right),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      p.status == PaymentStatus.paid
                          ? 'Pagado'
                          : 'Pendiente', // i18n: Fase W2
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: p.status == PaymentStatus.paid
                            ? palette.accent
                            : palette.warning,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Tab Entrenamiento (W2 PR3): rutina activa + historial de sesiones.
///
/// Reusa `assignedRoutinesProvider` y `sessionsByUidProvider` (data ya
/// trainer-readable). La evolución por ejercicio se difiere: depende de
/// `setLogs`, que es owner-only en firestore.rules.
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
                palette, 'No se pudo cargar el historial.'), // i18n: Fase W2
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
              return _HistorialTable(sessions: finished, palette: palette);
            },
          ),
          const SizedBox(height: 14),
          Text(
            'Próximamente: evolución por ejercicio (PR, volumen, frecuencia).', // i18n: Fase W2
            style: TextStyle(color: palette.textMuted, fontSize: 12),
          ),
        ],
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
  const _HistorialTable({required this.sessions, required this.palette});
  final List<Session> sessions;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final h = TextStyle(
        color: palette.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5);
    final c = TextStyle(color: palette.textPrimary, fontSize: 13);
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
              ],
            ),
          ),
          for (final s in sessions)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(
                      s.finishedAt != null ? _fmtDate(s.finishedAt!) : '—',
                      style: c,
                    ),
                  ),
                  Expanded(
                    flex: 4,
                    child: Text(s.routineName,
                        overflow: TextOverflow.ellipsis, style: c),
                  ),
                  Expanded(
                    flex: 2,
                    child:
                        Text('${s.durationMin} min', style: c), // i18n: Fase W2
                  ),
                  Expanded(
                    flex: 2,
                    child:
                        Text('${s.totalVolumeKg.round()} kg', // i18n: Fase W2
                            style: c,
                            textAlign: TextAlign.right),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
