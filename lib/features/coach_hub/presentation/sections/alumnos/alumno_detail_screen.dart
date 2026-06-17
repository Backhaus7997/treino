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
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_status.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';

import 'alumnos_screen.dart' show AlumnoEstado, AlumnoEstadoX, estadoForLink;

/// Detalle del alumno (`/alumnos/:id`, Fase W2 PR2).
///
/// Header (identidad + estado + métricas denormalizadas) + tab bar de 9
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
    'Historial',
    'Chat',
    'Notas privadas',
    'Archivos',
    'Seguimiento',
  ];
  static const _entrenamientoIndex = 1;
  static const _progresoIndex = 3;

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
      initialIndex: _progresoIndex,
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
                  if (i == _entrenamientoIndex)
                    _EntrenamientoTab(athleteId: athleteId)
                  else if (i == _progresoIndex)
                    _ProgresoTab(athleteId: athleteId)
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
              value == null ? '—' : '${_trim(value!)} $unit',
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

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
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
              // Mismo filtro que el historial del atleta (historial_section.dart)
              // y los contadores públicos: las sesiones abandonadas se persisten
              // con status=finished pero wasFullyCompleted=false, así que se
              // excluyen para no mostrarle al entrenador filas que el alumno no
              // ve en su propio historial. // i18n: Fase W2
              final finished = sessions
                  .where((s) =>
                      s.status == SessionStatus.finished && s.wasFullyCompleted)
                  .take(20)
                  .toList();
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
