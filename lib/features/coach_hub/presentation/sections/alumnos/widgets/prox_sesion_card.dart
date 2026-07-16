import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_shimmer.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/features/coach/application/agenda_providers.dart';
import 'package:treino/features/coach/domain/appointment.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

/// Tarjeta de la próxima sesión confirmada del alumno — Fase 3 WU-05
/// (extraído de `_ProxSesionCard`, `alumno_detail_screen.dart`, ADR-A3-04).
///
/// Reutiliza [trainerAppointmentsStreamProvider] ya presente en
/// `agenda_providers.dart`. Filtra: confirmed + startsAt futuro, ordena ASC,
/// toma el primero. Sin sesiones → estado vacío.
class ProxSesionCard extends ConsumerWidget {
  const ProxSesionCard(
      {super.key, required this.palette, required this.athleteId});

  final AppPalette palette;
  final String athleteId;

  String _fmtDate(DateTime dt) {
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year.toString();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$d/$m/$y · $hh:$mm';
  }

  Widget _box(Widget child) => Container(
        padding: const EdgeInsets.all(AppSpacing.s14),
        decoration: BoxDecoration(
          color: palette.bgCard,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: child,
      );

  Widget _skeleton() => _box(
        TreinoShimmer(
          child: Column(
            key: const Key('prox_sesion_skeleton'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 14,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
              Container(
                height: 12,
                width: 80,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // La regla de `appointments` exige filtrar por trainerId — Firestore
    // rechaza un query por athleteId (watchForAthlete es del lado del
    // alumno, no del PF). Usamos el stream del trainer (mismo que el
    // dashboard) con ventana day-truncada ESTABLE y filtramos el alumno en
    // memoria: sin permission-denied y sin índice nuevo.
    final trainerId = ref.watch(currentUidProvider) ?? '';
    final now = DateTime.now().toUtc();
    final todayStart = DateTime.utc(now.year, now.month, now.day);
    final async = ref.watch(trainerAppointmentsStreamProvider(
      TrainerAppointmentsKey(
        trainerId: trainerId,
        fromDate: todayStart,
        toDate: todayStart.add(const Duration(days: 60)),
      ),
    ));

    final String stateKey;
    final Widget content;

    if (async.isLoading && !async.hasValue) {
      stateKey = 'loading';
      content = _skeleton();
    } else if (async.hasError) {
      stateKey = 'error';
      content = _box(Text('No se pudo cargar la agenda.',
          style: TextStyle(color: palette.textMuted, fontSize: 13)));
    } else {
      final appointments = async.valueOrNull ?? const <Appointment>[];
      final upcoming = appointments
          .where((a) =>
              a.athleteId == athleteId &&
              a.status == AppointmentStatus.confirmed &&
              a.startsAt.isAfter(now))
          .toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
      final next = upcoming.firstOrNull;
      stateKey = next == null ? 'empty' : 'data';

      content = _box(
        next == null
            ? Text(
                'Sin sesiones próximas.', // i18n: Fase W2
                style: TextStyle(color: palette.textMuted, fontSize: 13),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _fmtDate(next.startsAt), // i18n: Fase W2
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.hairline),
                  Text(
                    '${next.durationMin} min', // i18n: Fase W2
                    style: TextStyle(color: palette.textMuted, fontSize: 12),
                  ),
                  if (next.noteBefore != null &&
                      next.noteBefore!.trim().isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.s8 - 2),
                    Text(
                      next.noteBefore!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
      );
    }

    return TreinoStateSwitcher(
      childKey: ValueKey('prox_sesion_$stateKey'),
      child: content,
    );
  }
}
