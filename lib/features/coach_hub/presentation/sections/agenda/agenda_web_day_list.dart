// NOTE: el Scaffold y el SafeArea los provee CoachHubScaffold (el shell).
// NO los agregues acá (ADR-CHW-005).
//
// PR1 — Ver turnos (read-only agenda viewer).
// Slice 2b — cobro por LOTE: modo de selección múltiple (checkboxes,
// lockeado a UN alumno) + barra "Cobrar (N)" → BatchCobrarDialog.
// Todas las strings están en español hardcodeado + comentario // i18n.
// NO se usa AppL10n en este archivo (constraint C-6).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../../core/widgets/treino_icon.dart';
import '../../../../coach/application/agenda_providers.dart';
import '../../../../coach/domain/appointment.dart';
import '../../../../coach/presentation/agenda_formatters.dart';
import '../../../../payments/application/billing_providers.dart'
    show athleteBillingProvider;
import '../../../../profile/application/user_public_profile_providers.dart';
import 'agenda_web_helpers.dart';
import 'appointment_detail_dialog.dart';
import 'batch_cobrar_dialog.dart';

// ─── AgendaWebDayList ─────────────────────────────────────────────────────────

/// Un turno es elegible para el lote: ya viene filtrado a `confirmed` por
/// `dayAppts` — sólo falta que no esté cobrado todavía.
bool _isBillable(Appointment appt) => appt.paymentId == null;

bool _isSameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Lista vertical de turnos del día seleccionado.
///
/// Reemplaza DayTimeline (hour-grid) con tarjetas simples (ADR-AGW-4).
/// Filtra: status==confirmed && mismo día. Ordena por startsAt asc.
///
/// Slice 2b: soporta un modo de SELECCIÓN MÚLTIPLE (toggle "Seleccionar" o
/// long-press sobre una tarjeta) para cobrar varios turnos con un solo
/// Payment. Sólo turnos `confirmed` + no cobrados son seleccionables, y la
/// selección queda LOCKEADA al alumno del primer turno elegido — un Payment
/// es de un solo alumno (ver `AppointmentRepository.billAppointments`). El
/// lock se DERIVA de la selección vigente en cada build (no vive en un campo
/// aparte) para que se libere solo si esos turnos dejan de ser válidos
/// (cobrados/cancelados por otra vía mientras el trainer elegía). La
/// selección es SIEMPRE del día mostrado — cambiar de día la limpia
/// (cross-día queda para un follow-up).
class AgendaWebDayList extends ConsumerStatefulWidget {
  const AgendaWebDayList({
    super.key,
    required this.trainerId,
    required this.selectedDay,
    required this.rangeFrom,
    required this.rangeTo,
    this.fillHeight = false,
  });

  final String trainerId;
  final DateTime selectedDay;
  final DateTime rangeFrom;
  final DateTime rangeTo;

  /// true → ListView que llena el alto (panel desktop); false → Column
  /// shrink-wrap (dentro de la columna scrolleable del layout angosto).
  final bool fillHeight;

  @override
  ConsumerState<AgendaWebDayList> createState() => _AgendaWebDayListState();
}

class _AgendaWebDayListState extends ConsumerState<AgendaWebDayList> {
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  @override
  void didUpdateWidget(covariant AgendaWebDayList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Cambió el día mostrado → la selección (siempre de UN día) ya no
    // aplica. No hace falta setState acá: un cambio de prop ya dispara un
    // build de este widget.
    if (!_isSameCalendarDay(oldWidget.selectedDay, widget.selectedDay)) {
      _selectionMode = false;
      _selectedIds.clear();
    }
  }

  void _enterSelectionMode() => setState(() => _selectionMode = true);

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(Appointment appt) {
    setState(() {
      if (!_selectedIds.remove(appt.id)) {
        _selectedIds.add(appt.id);
      }
    });
  }

  void _handleLongPress(Appointment appt) {
    if (!_isBillable(appt)) return;
    setState(() {
      _selectionMode = true;
      _selectedIds.add(appt.id);
    });
  }

  /// Usa `this.context` (el del propio State) — nunca uno pasado por
  /// parámetro — así el `mounted` check de abajo lo cubre correctamente
  /// después del `await` (lint use_build_context_synchronously).
  Future<void> _openBatchCobrar(List<Appointment> selected) async {
    if (selected.isEmpty) return;
    final athleteId = selected.first.athleteId;
    final profile = ref.read(userPublicProfileProvider(athleteId)).valueOrNull;
    final rawName = profile?.displayName ?? selected.first.athleteDisplayName;
    final athleteName = (isRawUid(rawName) || rawName.trim().isEmpty)
        ? 'Alumno' // i18n
        : rawName;

    final billed = await showDialog<bool>(
      context: context,
      builder: (_) => BatchCobrarDialog(
        appointments: selected,
        trainerId: widget.trainerId,
        athleteName: athleteName,
      ),
    );
    if (billed == true && mounted) {
      _exitSelectionMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            selected.length == 1
                ? 'Turno cobrado.' // i18n
                : '${selected.length} turnos cobrados.', // i18n
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final apptAsync = ref.watch(
      trainerAppointmentsStreamProvider(
        TrainerAppointmentsKey(
          trainerId: widget.trainerId,
          fromDate: widget.rangeFrom,
          toDate: widget.rangeTo,
        ),
      ),
    );

    return apptAsync.when(
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: CircularProgressIndicator(color: palette.accent),
        ),
      ),
      error: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'Error al cargar los turnos.', // i18n
            style: TextStyle(color: palette.textMuted),
          ),
        ),
      ),
      data: (allAppts) {
        // Filtrar: confirmados del día seleccionado.
        final dayAppts = allAppts
            .where(
              (a) =>
                  a.status == AppointmentStatus.confirmed &&
                  a.startsAt.year == widget.selectedDay.year &&
                  a.startsAt.month == widget.selectedDay.month &&
                  a.startsAt.day == widget.selectedDay.day,
            )
            .toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

        if (dayAppts.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No hay sesiones este día.', // i18n
                style: TextStyle(color: palette.textMuted),
              ),
            ),
          );
        }

        // Selección EFECTIVA: intersección de lo tildado con lo que sigue
        // siendo válido en el stream vigente (por si algo se cobró/canceló
        // por otra vía mientras el trainer elegía). El lock al alumno se
        // DERIVA de acá — nunca de un campo de estado aparte — así se
        // libera solo si esa selección deja de existir.
        final effectiveSelected = dayAppts
            .where((a) => _selectedIds.contains(a.id) && _isBillable(a))
            .toList();
        final lockedAthleteId = effectiveSelected.isEmpty
            ? null
            : effectiveSelected.first.athleteId;

        // Pre-calienta la tarifa de referencia del alumno lockeado ANTES de
        // que el trainer llegue a BatchCobrarDialog — mismo gotcha que Slice
        // 2a (obs. #468): un StreamProvider recién suscripto sigue en
        // AsyncLoading el primer microtask, y BatchCobrarDialog prellena el
        // monto con un ref.read() síncrono al abrir.
        if (lockedAthleteId != null) {
          ref.watch(athleteBillingProvider(lockedAthleteId));
        }

        final cards = <Widget>[
          for (final appt in dayAppts)
            AppointmentCard(
              key: ValueKey(appt.id),
              appointment: appt,
              trainerId: widget.trainerId,
              selectionMode: _selectionMode,
              selected: _selectedIds.contains(appt.id) && _isBillable(appt),
              selectable: _isBillable(appt) &&
                  (lockedAthleteId == null ||
                      lockedAthleteId == appt.athleteId),
              onToggleSelected: () => _toggleSelected(appt),
              onLongPress: () => _handleLongPress(appt),
            ),
        ];

        final header = _SelectionHeaderRow(
          selectionMode: _selectionMode,
          selectedCount: effectiveSelected.length,
          onEnterSelection: _enterSelectionMode,
          onCancelSelection: _exitSelectionMode,
        );

        final bottomBar = effectiveSelected.isNotEmpty
            ? _CobrarLoteBar(
                count: effectiveSelected.length,
                onTap: () => _openBatchCobrar(effectiveSelected),
              )
            : const SizedBox.shrink();

        if (widget.fillHeight) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 8),
              Expanded(child: ListView(children: cards)),
              bottomBar,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 8),
            ...cards,
            bottomBar,
          ],
        );
      },
    );
  }
}

// ─── Selection header row (Slice 2b) ───────────────────────────────────────────

/// Toggle "Seleccionar" (modo apagado) / contador + "Cancelar" (modo
/// prendido).
class _SelectionHeaderRow extends StatelessWidget {
  const _SelectionHeaderRow({
    required this.selectionMode,
    required this.selectedCount,
    required this.onEnterSelection,
    required this.onCancelSelection,
  });

  final bool selectionMode;
  final int selectedCount;
  final VoidCallback onEnterSelection;
  final VoidCallback onCancelSelection;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    if (!selectionMode) {
      return Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: onEnterSelection,
          style: TextButton.styleFrom(
            foregroundColor: palette.textMuted,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            'Seleccionar', // i18n
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 0.6,
              color: palette.textMuted,
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            selectedCount == 0
                ? 'Elegí los turnos a cobrar' // i18n
                : '$selectedCount seleccionado${selectedCount == 1 ? '' : 's'}', // i18n
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 0.4,
              color: palette.textPrimary,
            ),
          ),
        ),
        TextButton(
          onPressed: onCancelSelection,
          style: TextButton.styleFrom(
            foregroundColor: palette.textMuted,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            'Cancelar', // i18n
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Bottom "Cobrar (N)" bar (Slice 2b) ────────────────────────────────────────

class _CobrarLoteBar extends StatelessWidget {
  const _CobrarLoteBar({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: palette.bg,
          minimumSize: const Size.fromHeight(48),
          shape: const StadiumBorder(),
        ),
        child: Text(
          'COBRAR ($count)', // i18n
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

// ─── AppointmentCard ──────────────────────────────────────────────────────────

/// Tarjeta de turno: hora, nombre del alumno, duración.
/// onTap abre [AppointmentDetailDialog] (ADR-AGW-3) — salvo en modo
/// selección (Slice 2b), donde onTap tildea/destildea en su lugar y
/// long-press queda inactivo (ya estás adentro del modo).
class AppointmentCard extends ConsumerWidget {
  const AppointmentCard({
    super.key,
    required this.appointment,
    required this.trainerId,
    this.selectionMode = false,
    this.selected = false,
    this.selectable = true,
    this.onToggleSelected,
    this.onLongPress,
  });

  final Appointment appointment;
  final String trainerId;

  // ── Slice 2b — selección múltiple para cobro por lote ──────────────────
  final bool selectionMode;
  final bool selected;

  /// false cuando el turno ya está cobrado, o cuando hay una selección
  /// activa lockeada a OTRO alumno.
  final bool selectable;
  final VoidCallback? onToggleSelected;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final appt = appointment;

    // Nombre del alumno: profile stream → fallback a athleteDisplayName → Alumno.
    final profileAsync = ref.watch(userPublicProfileProvider(appt.athleteId));
    final rawName =
        profileAsync.valueOrNull?.displayName ?? appt.athleteDisplayName;
    final athleteName = (isRawUid(rawName) || rawName.trim().isEmpty)
        ? 'Alumno'
        : rawName; // i18n

    final timeLabel = AgendaFormatters.formatTime(appt.startsAt);
    final durationLabel = '${appt.durationMin} min'; // i18n

    final billed = appt.paymentId != null;
    // Turnos ya cobrados nunca muestran checkbox (ya están definitivamente
    // afuera del lote) — se distinguen con el chip "Cobrado" de siempre.
    final showCheckbox = selectionMode && !billed;
    final dimmed = selectionMode && !billed && !selectable;

    return GestureDetector(
      onTap: selectionMode
          ? (selectable ? onToggleSelected : null)
          : () => _openDetail(context, ref),
      onLongPress: selectionMode ? null : onLongPress,
      child: Opacity(
        opacity: dimmed ? 0.45 : 1.0,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? palette.accent.withValues(alpha: 0.08)
                : palette.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? palette.accent : palette.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              if (showCheckbox) ...[
                // IgnorePointer: el toggle real lo maneja el GestureDetector
                // de toda la tarjeta (arriba) — evita 2 tap recognizers
                // compitiendo por el mismo gesto si tocás justo el checkbox.
                // onChanged no-null (cuando selectable) para que NO se pinte
                // gris "deshabilitado" — sólo lo pinta gris cuando de verdad
                // no es seleccionable (onChanged: null).
                IgnorePointer(
                  child: Checkbox(
                    value: selected,
                    onChanged: selectable ? (_) {} : null,
                    activeColor: palette.accent,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                timeLabel,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: palette.accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  athleteName,
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: palette.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                durationLabel,
                style: GoogleFonts.barlow(
                  fontSize: 13,
                  color: palette.textMuted,
                ),
              ),
              // "Cobrado" indicator (Slice 2a — Agenda→cobro bridge). // i18n
              if (billed) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Cobrado', // i18n
                  child: Icon(
                    TreinoIcon.money,
                    size: 14,
                    color: palette.accent,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, WidgetRef ref) {
    final now = DateTime.now().toUtc();
    final isPast = appointment.startsAt.isBefore(now);
    showDialog<void>(
      context: context,
      builder: (_) => AppointmentDetailDialog(
        appointment: appointment,
        trainerId: trainerId,
        isPast: isPast,
      ),
    );
  }
}
