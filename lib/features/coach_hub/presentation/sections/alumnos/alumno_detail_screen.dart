import 'dart:convert' show utf8;
import 'dart:typed_data' show Uint8List;

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
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
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/chat/widgets/chat_detail_pane.dart';
import 'package:treino/features/gyms/application/gym_providers.dart';
import 'package:treino/features/insights/domain/chart_period.dart';
import 'package:treino/features/insights/presentation/widgets/daily_heatmap_section.dart';
import 'package:treino/features/insights/presentation/widgets/day_strip_labels.dart';
import 'package:treino/features/measurements/application/measurement_providers.dart';
import 'package:treino/features/measurements/domain/measurement.dart';
import 'package:treino/features/measurements/presentation/widgets/measurement_progress_chart.dart';
import 'package:treino/features/payments/application/billing_providers.dart';
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart';
import 'package:treino/features/payments/application/payment_providers.dart';
import 'package:treino/features/performance/application/performance_test_providers.dart';
import 'package:treino/features/performance/domain/performance_test.dart';
import 'package:treino/features/performance/presentation/widgets/performance_progress_chart.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/exercise_frequency_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_status.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_progression_chart.dart'
    show ExerciseProgressionChartLabels;
import 'package:treino/features/workout/presentation/widgets/exercise_progression_section.dart';
import 'package:treino/features/workout/presentation/widgets/most_frequent_exercises_list.dart';
import 'package:treino/features/workout/presentation/widgets/personal_records_list.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show userProfileProvider;
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../infrastructure/browser_download.dart';
import '../pagos/widgets/estado_cuenta_card.dart';
import '../pagos/widgets/marcar_pagado_actions.dart';
import '../pagos/widgets/pagos_table.dart';
import '../pagos/widgets/payment_format.dart';
import 'alumnos_screen.dart' show estadoForLink;
import 'progreso_metrics.dart';
import 'resumen_metrics.dart';
import 'widgets/adherencia_heatmap.dart';
import 'widgets/alumno_breadcrumb.dart';
import 'widgets/alumno_chrome_skeleton.dart';
import 'widgets/alumno_header.dart';
import 'widgets/alumno_kpi_strip.dart';
import 'widgets/alumno_tabs.dart';
import 'widgets/datos_personales_card.dart';
import 'widgets/historial_sesiones_table.dart';
import 'widgets/medicion_dialog.dart';
import 'widgets/medicion_list.dart';
import 'widgets/mediciones_toggle.dart';
import 'widgets/nota_card.dart';
import 'widgets/plan_nutricion_card.dart';
import 'widgets/progreso_kpi_strip.dart';
import 'widgets/prox_sesion_card.dart';
import 'widgets/rendimiento_dialog.dart';
import 'widgets/rendimiento_list.dart';
import 'widgets/resumen_kpi_strip.dart';
import 'widgets/rutina_activa_card.dart';
import 'widgets/ultima_sesion_card.dart';

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
    final profileAsync = ref.watch(userPublicProfileProvider(athleteId));
    final profile = profileAsync.valueOrNull;
    // Mismo criterio que el roster: el link más reciente NO-pending del alumno
    // (el stream viene requestedAt DESC). Sin el filtro de pending, un alumno
    // re-vinculado mostraría estados contradictorios entre roster y detalle.
    final link = ref
        .watch(trainerLinksStreamProvider)
        .valueOrNull
        ?.where((l) =>
            l.athleteId == athleteId && l.status != TrainerLinkStatus.pending)
        .firstOrNull;
    final cobrosPendientes =
        ref.watch(pagosPorCobrarProvider).valueOrNull ?? const [];
    final conDeudaIds = <String>{for (final c in cobrosPendientes) c.athleteId};
    final estado = link == null ? null : estadoForLink(link, conDeudaIds);
    final gymId = profile?.gymId;
    final gymName = gymId == null
        ? null
        : ref.watch(gymByIdProvider(gymId)).valueOrNull?.name;
    final billing = ref.watch(athleteBillingProvider(athleteId)).valueOrNull;
    final proxCobro =
        billing == null ? null : nextDueDate(billing, DateTime.now().toUtc());
    final athleteCobros =
        cobrosPendientes.where((c) => c.athleteId == athleteId);
    final deudaTotal = athleteCobros.isEmpty
        ? null
        : athleteCobros.fold<int>(0, (sum, c) => sum + c.amountArs);
    // Chrome (breadcrumb+header+KPI strip) cross-fadea sólo en la carga
    // INICIAL del perfil — link/gym/billing conservan su propio degrade
    // silencioso vía valueOrNull (mismo criterio que antes de WU-04), así que
    // no gatean el skeleton (evita 4 queries adicionales bloqueando el chrome
    // completo por una que tarde más).
    final chromeLoading = profileAsync.isLoading && !profileAsync.hasValue;
    final chromeStateKey = chromeLoading ? 'loading' : 'data';

    return DefaultTabController(
      length: _tabs.length,
      initialIndex: _resumenIndex,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s20,
              AppSpacing.s18,
              AppSpacing.s20,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TreinoStateSwitcher(
                  childKey: ValueKey('alumno_chrome_$chromeStateKey'),
                  child: chromeLoading
                      ? AlumnoChromeSkeleton(palette: palette)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AlumnoBreadcrumb(
                              palette: palette,
                              athleteName: profile?.displayName,
                            ),
                            const SizedBox(height: AppSpacing.s12),
                            AlumnoHeader(
                              profile: profile,
                              link: link,
                              estado: estado,
                              gymName: gymName,
                              billing: billing,
                              onPago: () =>
                                  registrarPago(context, ref, athleteId),
                              palette: palette,
                            ),
                            const SizedBox(height: AppSpacing.s12),
                            AlumnoKpiStrip(
                              sesiones: profile?.workoutsCount ?? 0,
                              racha: profile?.racha ?? 0,
                              vencimiento: proxCobro == null
                                  ? null
                                  : fmtDayMonth(proxCobro),
                              deuda: deudaTotal == null
                                  ? null
                                  : fmtArs(deudaTotal),
                            ),
                          ],
                        ),
                ),
                const SizedBox(height: AppSpacing.s14),
                AlumnoTabs(palette: palette, labels: _tabs),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
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

/// Tab «Progreso» del detalle de Alumno — Fase 3 WU-06b (rediseño kit v2).
///
/// Fuentes independientes (antropometría + rendimiento): gateadas juntas vía
/// `TreinoStateSwitcher` (loading shimmer / error / data), mismo criterio que
/// el original — spinner hasta que ambas tengan valor, error si alguna falla.
///
/// Honestidad de datos (ADR-A3-01 / patrón ADR-D2 fase 2): el mockup pide un
/// único chart "EVOLUCIÓN DE CARGAS" con dropdown de ejercicio — NO se
/// fabrica: se conservan los DOS charts reales ya cableados
/// (`MeasurementProgressChart` para antropometría, `PerformanceProgressChart`
/// para 1RM/rendimiento, éste con su propio selector + delta real por
/// métrica). Se agrega arriba un strip de 4 `KpiCard` (peso/%grasa/cintura/
/// 1RM con delta, [ProgresoKpiStrip]/[ProgresoKpis] — cálculo puro) que
/// resume ambas fuentes sin inventar ninguna serie nueva.
class _ProgresoTab extends ConsumerWidget {
  const _ProgresoTab({required this.athleteId});
  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final measAsync = ref.watch(measurementsForAthleteProvider(athleteId));
    final perfAsync = ref.watch(performanceTestsForAthleteProvider(athleteId));
    final stateKey = _progresoStateKeyOf(measAsync, perfAsync);

    return TreinoStateSwitcher(
      childKey: ValueKey('progreso_tab_$stateKey'),
      child: switch (stateKey) {
        'loading' => const _ProgresoTabSkeleton(),
        'error' => const TreinoEmptyState(
            icon: TreinoIcon.errorState,
            title: 'No se pudo cargar el progreso.', // i18n: Fase W2
          ),
        _ => _ProgresoTabData(
            measurements: measAsync.requireValue,
            tests: perfAsync.requireValue,
          ),
      },
    );
  }
}

/// `error` si alguna fuente falló; `loading` mientras ninguna de las dos
/// tenga valor todavía; `data` en cualquier otro caso.
String _progresoStateKeyOf(
  AsyncValue<Object?> meas,
  AsyncValue<Object?> perf,
) {
  if (meas.hasError || perf.hasError) return 'error';
  if ((meas.isLoading && !meas.hasValue) ||
      (perf.isLoading && !perf.hasValue)) {
    return 'loading';
  }
  return 'data';
}

class _ProgresoTabSkeleton extends StatelessWidget {
  const _ProgresoTabSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: ProgresoKpiStrip(),
    );
  }
}

class _ProgresoTabData extends StatelessWidget {
  const _ProgresoTabData({required this.measurements, required this.tests});

  final List<Measurement> measurements;
  final List<PerformanceTest> tests;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    if (measurements.isEmpty && tests.isEmpty) {
      return const TreinoEmptyState(
        icon: TreinoIcon.emptyState,
        title: 'Sin datos de progreso todavía.', // i18n: Fase W2
      );
    }

    final latest = measurements.isEmpty ? null : measurements.last;
    final kpis = ProgresoKpis.compute(measurements: measurements, tests: tests);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(0),
            child: ProgresoKpiStrip(kpis: kpis),
          ),
          if (latest != null) ...[
            const SizedBox(height: 20),
            TreinoFadeSlideIn(
              delay: AppMotion.stagger(1),
              child: _sectionLabel(palette, 'ANTROPOMETRÍA'), // i18n: Fase W2
            ),
            const SizedBox(height: 10),
            if (measurements.length >= 2)
              // El chart trae su propia card + heading; no lo re-envolvemos.
              MeasurementProgressChart(measurements: measurements),
          ],
          // ── Rendimiento (W2 PR8) ──────────────────────────────────────────
          // Ambos casos lideran con la misma sección «RENDIMIENTO» (consistencia
          // con el módulo coach legacy). Con ≥2 tests el chart agrega ABAJO su
          // propia card interna (heading l10n «PROGRESO») — es el chart real de
          // "evolución de cargas" (1RM y demás métricas), con delta propio.
          if (tests.isNotEmpty) ...[
            const SizedBox(height: 20),
            TreinoFadeSlideIn(
              delay: AppMotion.stagger(2),
              child: _sectionLabel(palette, 'RENDIMIENTO'), // i18n: Fase W2
            ),
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

/// Tab Resumen (Fase 3 WU-05): 4 `KpiCard` (vía [ResumenKpiStrip]) + última
/// sesión + heatmap de adherencia de 12 semanas + columna derecha (datos
/// personales, nota fijada, próxima sesión). Extraído a
/// `widgets/*.dart` (ADR-A3-04) — este composition root sólo orquesta el
/// gate async del bloque de métricas ([ResumenMetrics]) y compone los
/// cards, cada uno resolviendo su propio estado con `TreinoStateSwitcher`.
///
/// Layout responsive: 2 columnas en desktop (>=900px) — izquierda: KPI
/// strip + última sesión + heatmap; derecha: datos personales + nota fijada
/// + próxima sesión — 1 columna apilada en compact.
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

    // El bloque de métricas (KPI strip + heatmap) combina tres fuentes async:
    // skeleton hasta que las tres tengan valor, y un único error si
    // measurements/routines fallan. Si leyéramos routines/measurements con
    // valueOrNull, un error o un load lento se disfrazaría de «sin plan / sin
    // datos» — data trainer-facing engañosa. Las SESIONES, en cambio,
    // dependen de `session_shares`, que el CF borra cuando el link no está
    // `active` (p.ej. pausado) → un permission-denied ahí NO es un error del
    // resumen: cada card dependiente de sesiones (última sesión) resuelve su
    // propio estado vacío vía `sessionsAsync` (ver `UltimaSessionCard`).
    final String metricsStateKey;
    final Widget metricsBlock;
    if (sessionsAsync.isLoading ||
        measAsync.isLoading ||
        routinesAsync.isLoading) {
      metricsStateKey = 'loading';
      metricsBlock = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const ResumenKpiStrip(),
          const SizedBox(height: AppSpacing.s20),
          _sectionLabel(palette, 'ADHERENCIA · 12 SEMANAS'), // i18n: Fase W2
          const SizedBox(height: AppSpacing.s8 + 2),
          AdherenciaHeatmapSkeleton(palette: palette),
        ],
      );
    } else if (measAsync.hasError || routinesAsync.hasError) {
      metricsStateKey = 'error';
      metricsBlock =
          _muted(palette, 'No se pudo cargar el resumen.'); // i18n: Fase W2
    } else {
      metricsStateKey = 'data';
      final routines = routinesAsync.requireValue;
      final actives = routines.where((r) => r.status == RoutineStatus.active);
      final active =
          actives.where((r) => r.assignedBy == trainerUid).firstOrNull ??
              actives.firstOrNull;
      final sessions = sessionsAsync.valueOrNull ?? const [];
      final m = ResumenMetrics.compute(
        sessions: sessions,
        measurements: measAsync.requireValue,
        weeklyTarget: active?.days.length ?? 0,
        now: DateTime.now(),
      );
      metricsBlock = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(0),
            child: ResumenKpiStrip(metrics: m),
          ),
          const SizedBox(height: AppSpacing.s20),
          _sectionLabel(palette, 'ADHERENCIA · 12 SEMANAS'), // i18n: Fase W2
          const SizedBox(height: AppSpacing.s8 + 2),
          AdherenciaHeatmap(data: m.heatmap, palette: palette),
        ],
      );
    }

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TreinoStateSwitcher(
          childKey: ValueKey('resumen_metrics_$metricsStateKey'),
          child: metricsBlock,
        ),
        const SizedBox(height: AppSpacing.s20),
        _sectionLabel(
            palette, 'ÚLTIMA SESIÓN · POR EJERCICIO'), // i18n: Fase W2
        const SizedBox(height: AppSpacing.s8 + 2),
        UltimaSessionCard(
          palette: palette,
          athleteId: athleteId,
          sessionsAsync: sessionsAsync,
        ),
      ],
    );

    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionLabel(palette, 'DATOS PERSONALES'), // i18n
        const SizedBox(height: AppSpacing.s8 + 2),
        DatosPersonalesCard(palette: palette, athleteId: athleteId),
        const SizedBox(height: AppSpacing.s20),
        _sectionLabel(palette, 'NOTA FIJADA'), // i18n: Fase W2
        const SizedBox(height: AppSpacing.s8 + 2),
        if (trainerUid != null)
          NoteCard(
            palette: palette,
            trainerId: trainerUid,
            athleteId: athleteId,
          ),
        const SizedBox(height: AppSpacing.s20),
        _sectionLabel(palette, 'PRÓXIMA SESIÓN'), // i18n: Fase W2
        const SizedBox(height: AppSpacing.s8 + 2),
        ProxSesionCard(palette: palette, athleteId: athleteId),
      ],
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s20,
        AppSpacing.hairline,
        AppSpacing.s20,
        AppSpacing.s20,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [left, const SizedBox(height: AppSpacing.s20), right],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 7, child: left),
              const SizedBox(width: AppSpacing.s20),
              SizedBox(width: 320, child: right),
            ],
          );
        },
      ),
    );
  }
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
/// Construye un CSV (RFC-4180) del historial de pagos del alumno. // i18n
///
/// Neutraliza inyección de fórmulas (CSV injection): una celda que arranca con
/// = + - @ (o tab/CR) la interpretan Excel/Sheets como FÓRMULA. `concept` es
/// texto libre, así que prefijamos esas celdas con comilla simple para forzar
/// que se traten como texto literal.
@visibleForTesting
String buildPagosCsv(List<Payment> payments) {
  String esc(String s) {
    // CSV-injection guard (OWASP): prefix a formula-trigger lead with a quote.
    final v = s.isNotEmpty && '=+-@\t\r'.contains(s[0]) ? "'$s" : s;
    return '"${v.replaceAll('"', '""')}"';
  }

  final rows = <String>['FECHA,CONCEPTO,MONTO,ESTADO,PERÍODO'];
  for (final p in payments) {
    final d = p.createdAt.toLocal();
    final fecha = '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
    final estado =
        p.status == PaymentStatus.paid ? 'Pagado' : 'Pendiente'; // i18n
    rows.add([
      esc(fecha),
      esc(p.concept),
      esc(p.amountArs.toString()),
      esc(estado),
      esc(p.periodKey ?? ''),
    ].join(','));
  }
  return rows.join('\r\n');
}

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
            PagosTable(
              payments: history,
              palette: palette,
              onRecordar: (p) => recordar(
                context,
                ref,
                p,
                ref.read(userProfileProvider).valueOrNull?.paymentAlias,
              ),
            ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () {
                final name = ref
                        .read(userPublicProfileProvider(athleteId))
                        .valueOrNull
                        ?.displayName ??
                    'alumno';
                triggerBrowserDownload(
                  bytes:
                      Uint8List.fromList(utf8.encode(buildPagosCsv(history))),
                  filename: 'pagos_${name.replaceAll(' ', '_')}.csv',
                  mimeType: 'text/csv',
                );
              },
              child: Text(
                'Exportar CSV', // i18n: Fase W2
                style: TextStyle(
                  color: palette.accent,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tab Entrenamiento (Fase 3 WU-07a, rediseño kit v2): rutina activa +
/// historial de sesiones + evolución por ejercicio. Reusa
/// `assignedRoutinesProvider`, `sessionsByUidProvider`,
/// `athleteExerciseListProvider` y `exerciseProgressionProvider` — 100%
/// lógica de negocio preservada (ADR-A3-04), sólo cambia presentación/motion.
///
/// Rutina activa e historial extraídos a `widgets/rutina_activa_card.dart` /
/// `widgets/historial_sesiones_table.dart` (ADR-A3-02: la tabla ahora corre
/// sobre `CoachHubDataTable`; ver ADR-A3-10 sobre el expand-en-panel de sets
/// reales, antes inline por fila). El chart «EVOLUCIÓN POR EJERCICIO»
/// ([_ProgressionTabSection]) YA es real (mismo criterio de honestidad que
/// WU-06b) — no se fabrica ningún dato nuevo, sólo se envuelve en motion.
class _EntrenamientoTab extends ConsumerWidget {
  const _EntrenamientoTab({required this.athleteId});
  final String athleteId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final trainerUid = ref.watch(currentUidProvider);
    final routinesAsync = ref.watch(assignedRoutinesProvider(athleteId));
    final sessionsAsync = ref.watch(sessionsByUidProvider(athleteId));

    final routineStateKey = _asyncStateKeyOf(routinesAsync);
    final routines = routinesAsync.valueOrNull ?? const <Routine>[];
    final actives = routines.where((r) => r.status == RoutineStatus.active);
    final activeRoutine =
        actives.where((r) => r.assignedBy == trainerUid).firstOrNull ??
            actives.firstOrNull;

    final sessionsStateKey = _asyncStateKeyOf(sessionsAsync);
    // isCompletedSession excluye sesiones abandonadas (status=finished pero
    // wasFullyCompleted=false) para no divergir del historial del propio
    // alumno ni de los contadores públicos.
    final finished = (sessionsAsync.valueOrNull ?? const <Session>[])
        .where(isCompletedSession)
        .take(20)
        .toList();
    final sessionsError = sessionsAsync.error;
    final sessionsErrorMessage = sessionsError is FirebaseException &&
            sessionsError.code == 'permission-denied'
        ? 'El alumno no compartió su historial.' // i18n: Fase W2
        : 'No se pudo cargar el historial.'; // i18n: Fase W2

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s20,
        AppSpacing.hairline,
        AppSpacing.s20,
        AppSpacing.s20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                        child: _sectionLabel(palette, 'RUTINA ACTIVA')), // i18n
                    TextButton.icon(
                      onPressed: () =>
                          context.push('/routine-editor/$athleteId'), // i18n
                      icon: Icon(TreinoIcon.plus,
                          size: 16, color: palette.accent),
                      label: Text(
                        'Asignar rutina', // i18n: Fase W2
                        style: TextStyle(
                          color: palette.accent,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s8 + 2),
                TreinoStateSwitcher(
                  childKey: ValueKey('rutina_activa_$routineStateKey'),
                  child: switch (routineStateKey) {
                    'loading' => RutinaActivaCardSkeleton(palette: palette),
                    'error' => const TreinoEmptyState(
                        icon: TreinoIcon.errorState,
                        title: 'No se pudo cargar la rutina.', // i18n
                      ),
                    _ => activeRoutine == null
                        ? const TreinoEmptyState(
                            icon: TreinoIcon.emptyState,
                            title: 'Sin rutina activa asignada.', // i18n
                          )
                        : RutinaActivaCard(
                            routine: activeRoutine,
                            palette: palette,
                            athleteId: athleteId,
                          ),
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s20),
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel(palette, 'HISTORIAL DE SESIONES'), // i18n
                const SizedBox(height: AppSpacing.s8 + 2),
                TreinoStateSwitcher(
                  childKey:
                      ValueKey('entrenamiento_historial_$sessionsStateKey'),
                  child: HistorialSesionesTable(
                    sessions: finished,
                    athleteId: athleteId,
                    palette: palette,
                    loading: sessionsStateKey == 'loading',
                    errorMessage: sessionsStateKey == 'error'
                        ? sessionsErrorMessage
                        : null,
                    onRetry: () =>
                        ref.invalidate(sessionsByUidProvider(athleteId)),
                    emptyMessage:
                        'Sin sesiones registradas todavía.', // i18n: Fase W2
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s20 + 4),
          _DailyHeatmapTabSection(athleteId: athleteId),
          const SizedBox(height: AppSpacing.s20 + 4),
          _ProgressionTabSection(athleteId: athleteId, palette: palette),
        ],
      ),
    );
  }
}

/// `error` si la fuente falló; `loading` mientras no tenga valor todavía;
/// `data` en cualquier otro caso. Generaliza el criterio de
/// `_progresoStateKeyOf` para gates de una sola fuente async.
String _asyncStateKeyOf(AsyncValue<Object?> value) {
  if (value.hasError) return 'error';
  if (value.isLoading && !value.hasValue) return 'loading';
  return 'data';
}

// ── Músculos del día (PR2b) ───────────────────────────────────────────────────

/// Web-surface daily heat-map section.
///
/// Thin wrapper around the shared [DailyHeatmapSection] (AD5 dedupe — see
/// daily_heatmap_section.dart) with hardcoded Spanish labels, same pattern as
/// [_ProgressionTabSection].
///
/// All user-visible strings are hardcoded Spanish — the web Coach Hub does
/// NOT use AppL10n. Marked `// i18n: Fase W2` for future extraction.
///
/// Firestore access: trainer READ on `users/{uid}/sessions`+`setLogs` is
/// already granted by firestore.rules:786-807 (same predicate the mobile
/// coach shell relies on) — no rules change needed.
class _DailyHeatmapTabSection extends StatelessWidget {
  const _DailyHeatmapTabSection({required this.athleteId});

  final String athleteId;

  @override
  Widget build(BuildContext context) {
    return DailyHeatmapSection(
      athleteId: athleteId,
      labels: const DailyHeatmapSectionLabels(
        sectionTitle: 'MÚSCULOS DEL DÍA', // i18n: Fase W2
        dayStripLabels: DayStripLabels(
          todayLabel: 'HOY', // i18n: Fase W2
          emptyDayHint: 'No entrenó este día.', // i18n: Fase W2
        ),
      ),
    );
  }
}

// ── Evolución por ejercicio (PR2) ─────────────────────────────────────────────

/// Web-surface exercise-progression section.
///
/// Thin wrapper around the shared [ExerciseProgressionSection] (AD1 dedupe —
/// see exercise_progression_section.dart) with hardcoded Spanish labels.
///
/// All user-visible strings are hardcoded Spanish — the web Coach Hub does NOT
/// use AppL10n. Marked `// i18n: Fase W2` for future extraction.
///
/// Firestore access: trainer READ on setLogs is granted by firestore.rules:507-520
/// (mirrors the session-share predicate: owner OR linked trainer).
///
/// [PR4] Also owns the [_exerciseSelection] notifier shared with
/// [_MostFrequentExercisesTabSection] below it — tapping a row there selects
/// the exercise here (navigable to the existing exercise progression/detail).
class _ProgressionTabSection extends StatefulWidget {
  const _ProgressionTabSection({
    required this.athleteId,
    required this.palette,
  });

  final String athleteId;
  final AppPalette palette;

  @override
  State<_ProgressionTabSection> createState() => _ProgressionTabSectionState();
}

class _ProgressionTabSectionState extends State<_ProgressionTabSection> {
  final _exerciseSelection = ValueNotifier<String?>(null);

  @override
  void dispose() {
    _exerciseSelection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExerciseProgressionSection(
          athleteId: widget.athleteId,
          externalExerciseSelection: _exerciseSelection,
          labels: ExerciseProgressionSectionLabels(
            sectionTitle: 'EVOLUCIÓN POR EJERCICIO', // i18n: Fase W2
            loadingText: 'Cargando…', // i18n: Fase W2
            exerciseListErrorText:
                'No se pudo cargar la evolución.', // i18n: Fase W2
            emptyStateText: 'Sin registros de series todavía.', // i18n: Fase W2
            chartLabels: ExerciseProgressionChartLabels(
              heaviestWeightLabel: 'Peso máximo', // i18n: Fase W2
              oneRepMaxLabel: '1RM', // i18n: Fase W2
              bestSetVolumeLabel: 'Mejor serie', // i18n: Fase W2
              bestSessionVolumeLabel: 'Volumen', // i18n: Fase W2
              volumeUnit: 'kg·reps', // i18n: Fase W2
              weightUnit: 'kg', // i18n: Fase W2
              frequencyLabel: (n) => n == 1
                  ? '1 sesión en las últimas 8 semanas' // i18n: Fase W2
                  : '$n sesiones en las últimas 8 semanas', // i18n: Fase W2
              singlePointHint:
                  'Necesitás al menos 2 sesiones para ver la evolución.', // i18n: Fase W2
              emptyHint:
                  'Sin datos suficientes para este ejercicio.', // i18n: Fase W2
            ),
            periodLabels: const ChartPeriodLabels(
              last30dLabel: 'Últimos 30 días', // i18n: Fase W2
              thisWeekLabel: 'Esta semana', // i18n: Fase W2
              monthLabel: 'Este mes', // i18n: Fase W2
            ),
            localeName: 'es_AR', // hardcoded for web Coach Hub (i18n: Fase W2)
            personalRecordsLabels: const PersonalRecordsListLabels(
              sectionTitle: 'RÉCORDS PERSONALES', // i18n: Fase W2
              heaviestWeightLabel: 'Peso máximo', // i18n: Fase W2
              oneRepMaxLabel: '1RM', // i18n: Fase W2
              bestSetVolumeLabel: 'Mejor serie', // i18n: Fase W2
              bestSessionVolumeLabel: 'Volumen', // i18n: Fase W2
              volumeUnit: 'kg·reps', // i18n: Fase W2
              weightUnit: 'kg', // i18n: Fase W2
              emptyText:
                  'Sin datos suficientes para este ejercicio.', // i18n: Fase W2
              localeName: 'es_AR', // i18n: Fase W2
            ),
          ),
        ),
        const SizedBox(height: 24),
        _MostFrequentExercisesTabSection(
          athleteId: widget.athleteId,
          onSelectExercise: (id) => _exerciseSelection.value = id,
        ),
      ],
    );
  }
}

/// [PR4] Web-surface most-frequent-exercises section shown below
/// [_ProgressionTabSection]. Hardcoded Spanish labels — same convention as
/// the rest of this file (`// i18n: Fase W2`).
class _MostFrequentExercisesTabSection extends ConsumerStatefulWidget {
  const _MostFrequentExercisesTabSection({
    required this.athleteId,
    required this.onSelectExercise,
  });

  final String athleteId;
  final void Function(String exerciseId) onSelectExercise;

  @override
  ConsumerState<_MostFrequentExercisesTabSection> createState() =>
      _MostFrequentExercisesTabSectionState();
}

class _MostFrequentExercisesTabSectionState
    extends ConsumerState<_MostFrequentExercisesTabSection> {
  ChartPeriod _selectedPeriod = ChartPeriod.defaultPeriod;

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(exerciseFrequencyProvider(
        (athleteUid: widget.athleteId, period: _selectedPeriod)));

    return entriesAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (entries) => MostFrequentExercisesList(
        entries: entries,
        selectedPeriod: _selectedPeriod,
        onSelectExercise: widget.onSelectExercise,
        onSelectPeriod: (p) => setState(() => _selectedPeriod = p),
        labels: MostFrequentExercisesListLabels(
          sectionTitle: 'EJERCICIOS MÁS FRECUENTES', // i18n: Fase W2
          sessionCountLabel: (n) => n == 1
              ? '1 sesión' // i18n: Fase W2
              : '$n sesiones', // i18n: Fase W2
          emptyText: 'No hay datos todavía.', // i18n: Fase W2
          periodLabels: const ChartPeriodLabels(
            last30dLabel: 'Últimos 30 días', // i18n: Fase W2
            thisWeekLabel: 'Esta semana', // i18n: Fase W2
            monthLabel: 'Este mes', // i18n: Fase W2
          ),
        ),
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
/// Reusa el mismo `HistorialSesionesTable` (Fase 3 WU-07a,
/// `widgets/historial_sesiones_table.dart`) que Entrenamientos, activando el
/// flag `showStatusBadge`.
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
      // Un link pausado borra session_shares → permission-denied. No es un
      // fallo de carga: el alumno dejó de compartir. Lo decimos claro, igual
      // que Entrenamientos y el card de última sesión del Resumen.
      error: (e, _) => Center(
        child: Text(
          e is FirebaseException && e.code == 'permission-denied'
              ? 'El alumno no compartió su historial.' // i18n: Fase W2
              : 'No pudimos cargar el historial.', // i18n: Fase W2
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
              HistorialSesionesTable(
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
                      style: TextStyle(color: palette.textMuted, fontSize: 13),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
              icon:
                  Icon(TreinoIcon.download, size: 18, color: palette.textMuted),
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

/// Coach Hub web — Tab «Mediciones» del alumno detail — Fase 3 WU-06a.
///
/// Toggle segmentado antropométricas/rendimiento (`MedicionesToggle`,
/// `widgets/mediciones_toggle.dart`) + listas (`MedicionList`/
/// `RendimientoList`, `widgets/*_list.dart`) + dialogs de alta/edición
/// (`MedicionDialog`/`RendimientoDialog`, `widgets/*_dialog.dart`) vía
/// `showTreinoDialog`/`TreinoDialog` — kit v2 (ADR-A3-04). El confirm de
/// borrado queda inline (chico, mismo patrón que `_confirmAction` de
/// `alumnos_screen.dart`).
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
  MedicionView _view = MedicionView.antropometricas;

  Future<void> _openAntropoDialog({Measurement? initial}) async {
    final trainerUid = ref.read(currentUidProvider);
    if (trainerUid == null) return;
    await showTreinoDialog<void>(
      context,
      builder: (_) => MedicionDialog(
        athleteId: widget.athleteId,
        trainerUid: trainerUid,
        initial: initial,
      ),
    );
  }

  Future<void> _openRendimientoDialog({PerformanceTest? initial}) async {
    final trainerUid = ref.read(currentUidProvider);
    if (trainerUid == null) return;
    await showTreinoDialog<void>(
      context,
      builder: (_) => RendimientoDialog(
        athleteId: widget.athleteId,
        trainerUid: trainerUid,
        initial: initial,
      ),
    );
  }

  Future<void> _confirmDeleteMedicion(Measurement m) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showTreinoDialog<bool>(
      context,
      builder: (ctx) => TreinoDialog(
        title: '¿Eliminar medición?', // i18n: Fase W2
        body: Text(
          'La medición del ${fmtDate(m.recordedAt)} se va a borrar. '
          'No se puede deshacer.', // i18n: Fase W2
        ),
        destructive: true,
        primaryLabel: 'Confirmar', // i18n: Fase W2
        onPrimaryTap: () => Navigator.of(ctx).pop(true),
        secondaryLabel: 'Cancelar', // i18n: Fase W2
        onSecondaryTap: () => Navigator.of(ctx).pop(false),
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
    final confirmed = await showTreinoDialog<bool>(
      context,
      builder: (ctx) => TreinoDialog(
        title: '¿Eliminar prueba?', // i18n: Fase W2
        body: Text(
          'La prueba del ${fmtDate(t.recordedAt)} se va a borrar. '
          'No se puede deshacer.', // i18n: Fase W2
        ),
        destructive: true,
        primaryLabel: 'Confirmar', // i18n: Fase W2
        onPrimaryTap: () => Navigator.of(ctx).pop(true),
        secondaryLabel: 'Cancelar', // i18n: Fase W2
        onSecondaryTap: () => Navigator.of(ctx).pop(false),
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
    final isAntropo = _view == MedicionView.antropometricas;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s20,
        vertical: AppSpacing.s20,
      ),
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
                    const SizedBox(height: AppSpacing.hairline),
                    Text(
                      isAntropo
                          ? 'Peso, composición corporal y '
                              'circunferencias.' // i18n: Fase W2
                          : 'Saltos, sprints, 1RM y '
                              'resistencia.', // i18n: Fase W2
                      style: TextStyle(color: palette.textMuted, fontSize: 13),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: isAntropo
                    ? () => _openAntropoDialog()
                    : () => _openRendimientoDialog(),
                icon: const Icon(TreinoIcon.plus, size: 16),
                label: Text(isAntropo
                    ? 'NUEVA MEDICIÓN' // i18n: Fase W2
                    : 'NUEVA PRUEBA'), // i18n: Fase W2
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.bg,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s18,
                    vertical: AppSpacing.s12,
                  ),
                  shape: const StadiumBorder(),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s12),
          // ── Toggle segmented ────────────────────────────────────────────
          MedicionesToggle(
            view: _view,
            palette: palette,
            onChanged: (v) => setState(() => _view = v),
          ),
          const SizedBox(height: AppSpacing.s20),
          Expanded(
            child: isAntropo
                ? MedicionList(
                    athleteId: widget.athleteId,
                    palette: palette,
                    onDelete: _confirmDeleteMedicion,
                    onEdit: (m) => _openAntropoDialog(initial: m),
                  )
                : RendimientoList(
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
                      style: TextStyle(color: palette.textMuted, fontSize: 13),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
                        style:
                            TextStyle(color: palette.textMuted, fontSize: 14),
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
                icon: Icon(Icons.edit, size: 18, color: palette.textMuted),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              IconButton(
                tooltip: 'Eliminar', // i18n: Fase W2
                onPressed: onDelete,
                icon: Icon(TreinoIcon.trash, size: 18, color: palette.danger),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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

  static (String, Color) _labelAndColor(FollowUpTag tag, AppPalette palette) {
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
          content: Text('No pudimos guardar la entrada.'), // i18n: Fase W2
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

    final draft = _draft;
    final stateKey = draft == null ? 'loading' : 'data';

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s20,
        vertical: AppSpacing.s20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TreinoFadeSlideIn(
            delay: AppMotion.stagger(0),
            child: Row(
              children: [
                Expanded(child: _sectionLabel(palette, 'PLAN ACTIVO')),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: palette.accent,
                    foregroundColor: palette.bg,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s20,
                      vertical: AppSpacing.s12,
                    ),
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
          ),
          const SizedBox(height: AppSpacing.s14),
          Expanded(
            child: SingleChildScrollView(
              // Small top padding — el label flotante del TextFormField
              // extiende ~8px arriba del border cuando el field tiene
              // valor. Sin este padding el label queda clippeado por el
              // SingleChildScrollView al scrollear.
              padding: const EdgeInsets.only(top: AppSpacing.hairline + 4),
              child: TreinoStateSwitcher(
                childKey: ValueKey('plan_nutricion_$stateKey'),
                child: draft == null
                    ? PlanNutricionCardSkeleton(palette: palette)
                    : PlanNutricionCard(
                        draft: draft,
                        palette: palette,
                        newIdFor: _newId,
                        onTitleChanged: _updateTitle,
                        onMealChanged: _updateMeal,
                        onRemoveMeal: _removeMeal,
                        onAddMeal: _addMeal,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
