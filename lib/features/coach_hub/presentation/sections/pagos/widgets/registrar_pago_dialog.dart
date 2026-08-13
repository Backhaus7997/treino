/// Diálogo de alta de un pago ad-hoc (alumno + monto + concepto + estado) para
/// la sección Pagos.
///
/// Extraído de `alumno_detail_screen.dart` (PR1 — refactor puro) y luego
/// extendido para el botón global "Registrar pago" del header, que no está
/// parado sobre ningún alumno: ahora colecta también el alumno destino y
/// soporta un cobro ya cobrado o uno pendiente (con fecha de vencimiento
/// opcional). Devuelve un [RegistrarPagoResult] o `null` si se cancela.
///
/// Arquitectura: este diálogo SOLO colecta y valida — no toca el repositorio
/// de pagos. La persistencia queda en el caller (`pagos_web_screen.dart`),
/// igual que antes de esta extensión.
///
/// Sección: coach_hub/pagos — contrato: sin Scaffold, sin HEX, es-AR + // i18n.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/core/utils/argentina_time.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart'
    show trainerLinksStreamProvider;
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart'
    show userPublicProfilesBatchProvider;

import 'thousands_input_formatter.dart';

/// Resultado del diálogo: todo lo que el caller necesita para construir el
/// [Payment]. `dueAt` ya viene normalizado (ART 23:59:59 → instante UTC) —
/// ver [_RegistrarPagoDialogState._pickDueDate] y el mismo cálculo que usa
/// mobile en `trainer_dashboard_tab.dart`.
typedef RegistrarPagoResult = ({
  String athleteId,
  int amount,
  String concept,
  PaymentStatus status,
  DateTime? dueAt,
});

/// Diálogo de alta de un pago ad-hoc ligado a un alumno. Devuelve el record o
/// `null` si se cancela. Copy hardcodeada (CoachHubApp no tiene l10n delegates).
///
/// [athleteId]: cuando viene seteado (abierto desde el detalle de un alumno),
/// el diálogo fija el alumno y NO renderiza el dropdown — ni siquiera
/// escucha `trainerLinksStreamProvider`/`userPublicProfilesBatchProvider`.
/// Cuando es `null` (botón global del header), se muestra el dropdown como
/// hasta ahora.
class RegistrarPagoDialog extends ConsumerStatefulWidget {
  const RegistrarPagoDialog({super.key, this.athleteId});

  final String? athleteId;

  @override
  ConsumerState<RegistrarPagoDialog> createState() =>
      _RegistrarPagoDialogState();
}

class _RegistrarPagoDialogState extends ConsumerState<RegistrarPagoDialog> {
  final _monto = TextEditingController();
  final _concepto = TextEditingController();
  String? _selectedAthleteId;
  PaymentStatus _status = PaymentStatus.paid;
  DateTime? _dueDate;
  String? _error;

  @override
  void dispose() {
    _monto.dispose();
    _concepto.dispose();
    super.dispose();
  }

  /// dd/MM/yyyy — mismo idioma que payment_format.dart's fmtFecha.
  static String _formatDueDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pickDueDate() async {
    // "Hoy" como día calendario ART: entre 21:00–23:59 ART el día UTC ya es
    // mañana, así que un floor derivado de UTC bloquearía elegir hoy.
    final todayArt = argentinaNow();
    final floor = DateTime(todayArt.year, todayArt.month, todayArt.day);
    final initial = _dueDate ?? floor;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(floor) ? floor : initial,
      firstDate: floor,
      lastDate: floor.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _dueDate = picked);
    }
  }

  /// Alumno efectivo: el fijo pasado por el caller, o el elegido en el
  /// dropdown. Cuando `widget.athleteId != null` el dropdown ni se renderiza
  /// — la validación de alumno queda siempre satisfecha en ese modo.
  void _submit() {
    final athleteId = widget.athleteId ?? _selectedAthleteId;
    final amount = parseGroupedInt(_monto.text);
    final concept = _concepto.text.trim();
    if (athleteId == null) {
      setState(() => _error = 'Elegí un alumno.'); // i18n
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Ingresá un monto válido.'); // i18n
      return;
    }
    if (concept.isEmpty) {
      setState(() => _error = 'Completá todos los campos.'); // i18n
      return;
    }
    if (_status == PaymentStatus.pending && _dueDate == null) {
      setState(() => _error = 'Elegí una fecha de vencimiento.'); // i18n
      return;
    }
    // dueAt = fin del día calendario ART elegido, como instante UTC — misma
    // normalización que trainer_dashboard_tab.dart usa para el cobro suelto
    // pendiente (23:59:59 ART == +3h en UTC).
    final dueDate = _status == PaymentStatus.pending ? _dueDate : null;
    final dueAt = dueDate == null
        ? null
        : DateTime.utc(dueDate.year, dueDate.month, dueDate.day, 23, 59, 59)
            .add(argentinaUtcOffset);
    Navigator.of(context).pop((
      athleteId: athleteId,
      amount: amount,
      concept: concept,
      status: _status,
      dueAt: dueAt,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    // Solo escuchamos el stream de vínculos cuando el diálogo necesita
    // mostrar el dropdown (modo global, sin athleteId fijo) — si el caller
    // ya sabe el alumno, no hace falta este trabajo.
    final showAthletePicker = widget.athleteId == null;
    final linksAsync = showAthletePicker
        ? ref.watch(trainerLinksStreamProvider)
        : const AsyncValue<List<TrainerLink>>.data(<TrainerLink>[]);

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
      title: Text('Registrar pago', // i18n
          style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 18)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showAthletePicker) ...[
              Text('Alumno', // i18n
                  style: TextStyle(
                      color: palette.textMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 12)),
              const SizedBox(height: 6),
              _buildAthletePicker(palette, linksAsync, deco),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _monto,
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandsSeparatorInputFormatter()],
              style: TextStyle(color: palette.textPrimary),
              decoration: deco('Monto (ARS)', 'Ej: 5000'), // i18n
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _concepto,
              style: TextStyle(color: palette.textPrimary),
              decoration: deco('Concepto', 'Ej: Clase suelta'), // i18n
            ),
            const SizedBox(height: 12),
            Text('Estado', // i18n
                style: TextStyle(
                    color: palette.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 12)),
            const SizedBox(height: 6),
            _buildEstadoToggle(palette),
            if (_status == PaymentStatus.pending) ...[
              const SizedBox(height: 12),
              Text('Fecha de vencimiento', // i18n
                  style: TextStyle(
                      color: palette.textMuted,
                      fontWeight: FontWeight.w600,
                      fontSize: 12)),
              const SizedBox(height: 6),
              _buildDueDatePicker(palette),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: TextStyle(color: palette.danger, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancelar', // i18n
                style: TextStyle(color: palette.textMuted))),
        TextButton(
            onPressed: _submit,
            child: Text('Registrar', // i18n
                style: TextStyle(
                    color: palette.accent, fontWeight: FontWeight.w700))),
      ],
    );
  }

  /// Colapsa `trainerLinksStreamProvider` a un vínculo por alumno (el stream
  /// viene requestedAt DESC — nos quedamos con el primero visto) y excluye
  /// `pending`/`terminated`. NOTA: `rutinas_screen.dart` solo excluye
  /// `pending` — acá excluimos también `terminated` a propósito, porque este
  /// diálogo registra pagos nuevos y no tiene sentido cobrarle a un alumno
  /// cuyo vínculo ya terminó.
  Widget _buildAthletePicker(
    AppPalette palette,
    AsyncValue<List<TrainerLink>> linksAsync,
    InputDecoration Function(String, String) deco,
  ) {
    return linksAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      error: (_, __) => Text('No pudimos cargar los alumnos.', // i18n
          style: TextStyle(color: palette.danger, fontSize: 13)),
      data: (links) {
        final seen = <String>{};
        final athletes = <TrainerLink>[];
        for (final l in links) {
          if (l.status == TrainerLinkStatus.pending ||
              l.status == TrainerLinkStatus.terminated) {
            continue;
          }
          if (seen.add(l.athleteId)) athletes.add(l);
        }
        if (athletes.isEmpty) {
          return Text('No tenés alumnos vinculados.', // i18n
              style: TextStyle(color: palette.textMuted, fontSize: 13));
        }

        final athleteIds = athletes.map((l) => l.athleteId).toList()..sort();
        final batchKey = athleteIds.join(',');
        final profilesAsync =
            ref.watch(userPublicProfilesBatchProvider(batchKey));
        final profiles = profilesAsync.valueOrNull ?? const {};

        // Guard contra el assert de DropdownButtonFormField ("exactly one
        // item with value") si el stream re-emite y el alumno seleccionado
        // dejó de estar en la lista filtrada (p.ej. pasó a paused/terminated
        // entre re-emisiones). Usamos un valor local para el picker — nunca
        // seteamos state durante build — y sincronizamos `_selectedAthleteId`
        // post-frame para que `_submit` no pueda popear un id obsoleto.
        final validSelection = athletes.any(
          (a) => a.athleteId == _selectedAthleteId,
        )
            ? _selectedAthleteId
            : null;
        if (validSelection != _selectedAthleteId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _selectedAthleteId = validSelection);
          });
        }

        return DropdownButtonFormField<String>(
          initialValue: validSelection,
          isExpanded: true,
          dropdownColor: palette.bgCard,
          style: TextStyle(color: palette.textPrimary, fontSize: 14),
          decoration: deco('Alumno', 'Elegí un alumno'), // i18n
          hint: Text('Elegí un alumno', // i18n
              style: TextStyle(color: palette.textMuted)),
          items: athletes.map((l) {
            final name = profiles[l.athleteId]?.displayName;
            final label = (name == null || name.isEmpty) ? 'Alumno' : name;
            return DropdownMenuItem<String>(
              value: l.athleteId,
              child: Text(label, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: (id) => setState(() => _selectedAthleteId = id),
        );
      },
    );
  }

  Widget _buildEstadoToggle(AppPalette palette) {
    Widget chip(String label, PaymentStatus value) {
      final selected = _status == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() {
            _status = value;
            // Al volver a Cobrado, descartamos cualquier fecha elegida antes
            // — si el trainer alterna Pendiente → Cobrado → Pendiente, no
            // queremos que una fecha vieja resucite silenciosamente.
            if (value == PaymentStatus.paid) _dueDate = null;
          }),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? palette.accent : palette.bg,
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: selected ? palette.accent : palette.border),
            ),
            child: Text(label,
                style: TextStyle(
                  color: selected ? palette.bg : palette.textMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                )),
          ),
        ),
      );
    }

    return Row(
      children: [
        chip('Cobrado', PaymentStatus.paid), // i18n
        const SizedBox(width: 8),
        chip('Pendiente', PaymentStatus.pending), // i18n
      ],
    );
  }

  Widget _buildDueDatePicker(AppPalette palette) {
    return InkWell(
      onTap: _pickDueDate,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: palette.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            Icon(TreinoIcon.calendar, size: 16, color: palette.textMuted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _dueDate == null
                    ? 'Elegí una fecha' // i18n
                    : _formatDueDate(_dueDate!),
                style: TextStyle(
                  color: _dueDate == null
                      ? palette.textMuted
                      : palette.textPrimary,
                  fontSize: 13,
                ),
              ),
            ),
            if (_dueDate != null)
              GestureDetector(
                onTap: () => setState(() => _dueDate = null),
                behavior: HitTestBehavior.opaque,
                child:
                    Icon(TreinoIcon.close, size: 16, color: palette.textMuted),
              ),
          ],
        ),
      ),
    );
  }
}
