// NOTE: el Scaffold y el SafeArea los provee CoachHubScaffold (el shell).
// NO los agregues acá (ADR-CHW-005).
//
// PR2 — Nueva Sesión (create single appointment).
// Todas las strings están en español hardcodeado + comentario // i18n.
// NO se usa AppL10n en este archivo (constraint C-6).
//
// Diseño: ADR-AGW-3 (showDialog/AlertDialog, no bottom sheets).
//         ADR-AGW-5 (athlete picker = trainerLinksStreamProvider active).
//         ADR-AGW-6 (duration free 5..480 + preset chips {30,45,60,90,120}).
//         Recurring DEFERRED (fuera de scope PR2).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../app/theme/app_palette.dart';
import '../../../../coach/application/agenda_providers.dart';
import '../../../../coach/application/trainer_link_providers.dart';
import '../../../../coach/domain/trainer_link.dart';
import '../../../../coach/domain/trainer_link_status.dart';
import '../../../../profile/application/user_public_profile_providers.dart';
import '../../../../workout/application/session_providers.dart'
    show currentUidProvider;

// ─── NewSessionDialog ─────────────────────────────────────────────────────────

/// Dialog de creación de sesión — idioma web (AlertDialog, ADR-AGW-3).
///
/// Reemplaza [NewSessionSheet] para la vista web del Coach Hub.
/// Soporta: athlete picker (activos via [trainerLinksStreamProvider]),
/// date picker, time picker, duration free-text 5..480 + preset chips.
/// Al confirmar llama [appointmentRepositoryProvider.createByTrainer].
///
/// Retorna `true` vía [Navigator.pop] cuando la sesión fue registrada,
/// `null`/`false` cuando el usuario canceló.
class NewSessionDialog extends ConsumerStatefulWidget {
  const NewSessionDialog({
    super.key,
    this.initialDate,
  });

  /// Fecha inicial del date picker (por defecto hoy).
  final DateTime? initialDate;

  @override
  ConsumerState<NewSessionDialog> createState() => _NewSessionDialogState();
}

class _NewSessionDialogState extends ConsumerState<NewSessionDialog> {
  String? _selectedAthleteId;
  late DateTime _date;
  late TimeOfDay _time;

  final _durationController = TextEditingController(text: '60');
  final _noteController = TextEditingController();

  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = widget.initialDate ?? DateTime(now.year, now.month, now.day);
    // Evitar que initialDate sea en el pasado (queda abierto el guard en _submit).
    _time = TimeOfDay(hour: now.hour + 1 > 23 ? 23 : now.hour + 1, minute: 0);
  }

  @override
  void dispose() {
    _durationController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Parsea la duración del campo de texto. Valida 5..480.
  /// Devuelve null y setea [_errorMessage] si inválido.
  int? _parsedDuration() {
    final val = int.tryParse(_durationController.text.trim());
    if (val == null || val < 5 || val > 480) {
      setState(() => _errorMessage =
          'La duración debe ser entre 5 y 480 minutos.'); // i18n
      return null;
    }
    return val;
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(today) ? today : _date,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() {
        _date = picked;
        _errorMessage = null;
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time,
    );
    if (picked != null && mounted) {
      setState(() {
        _time = picked;
        _errorMessage = null;
      });
    }
  }

  String _formatDate(DateTime dt) {
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    return '$dd/$mm/${dt.year}';
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    final athleteId = _selectedAthleteId;
    if (athleteId == null) {
      setState(
          () => _errorMessage = 'Elegí un alumno antes de continuar.'); // i18n
      return;
    }

    // Guard: la combinación fecha+hora no puede ser en el pasado.
    final now = DateTime.now();
    final startsAt = DateTime.utc(
      _date.year,
      _date.month,
      _date.day,
      _time.hour,
      _time.minute,
    );
    final nowWall = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );
    if (!startsAt.isAfter(nowWall)) {
      setState(() => _errorMessage =
          'No podés registrar una sesión en el pasado.'); // i18n
      return;
    }

    final dur = _parsedDuration();
    if (dur == null) return; // errorMessage ya seteado

    final trainerId = ref.read(currentUidProvider);
    if (trainerId == null) {
      setState(() =>
          _errorMessage = 'Error de autenticación. Intentá de nuevo.'); // i18n
      return;
    }

    setState(() {
      _saving = true;
      _errorMessage = null;
    });

    try {
      final profile =
          await ref.read(userPublicProfileProvider(athleteId).future);
      final rawName = profile?.displayName?.trim() ?? '';
      final athleteDisplayName = rawName.isEmpty ? athleteId : rawName;

      final note = _noteController.text.trim();

      await ref.read(appointmentRepositoryProvider).createByTrainer(
            trainerId: trainerId,
            athleteId: athleteId,
            athleteDisplayName: athleteDisplayName,
            startsAt: startsAt,
            durationMin: dur,
            noteBefore: note.isEmpty ? null : note,
          );

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesión registrada.')), // i18n
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errorMessage =
            'No pudimos registrar la sesión. Probá de nuevo.'; // i18n
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final linksAsync = ref.watch(trainerLinksStreamProvider);
    final activeLinks = (linksAsync.valueOrNull ?? const <TrainerLink>[])
        .where((l) => l.status == TrainerLinkStatus.active)
        .toList();

    final hasActiveLinks = activeLinks.isNotEmpty;

    return AlertDialog(
      backgroundColor: palette.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      title: Text(
        'NUEVA SESIÓN', // i18n
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 20,
          letterSpacing: 1.2,
          color: palette.textPrimary,
        ),
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Athlete picker ────────────────────────────────────────
              _FieldLabel(label: 'ALUMNO', palette: palette), // i18n
              const SizedBox(height: 8),
              if (!hasActiveLinks)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'No tenés alumnos activos todavía.', // i18n
                    style: GoogleFonts.barlow(
                      fontSize: 13,
                      color: palette.textMuted,
                    ),
                  ),
                )
              else
                _AthleteDropdown(
                  links: activeLinks,
                  selectedId: _selectedAthleteId,
                  palette: palette,
                  onChanged: (id) => setState(() {
                    _selectedAthleteId = id;
                    _errorMessage = null;
                  }),
                ),
              const SizedBox(height: 14),

              // ── Fecha ─────────────────────────────────────────────────
              _FieldLabel(label: 'FECHA', palette: palette), // i18n
              const SizedBox(height: 8),
              _TappableField(
                palette: palette,
                text: _formatDate(_date),
                onTap: _pickDate,
              ),
              const SizedBox(height: 14),

              // ── Hora ──────────────────────────────────────────────────
              _FieldLabel(label: 'HORA', palette: palette), // i18n
              const SizedBox(height: 8),
              _TappableField(
                palette: palette,
                text: _time.format(context),
                onTap: _pickTime,
              ),
              const SizedBox(height: 14),

              // ── Duración ──────────────────────────────────────────────
              _FieldLabel(label: 'DURACIÓN (min)', palette: palette), // i18n
              const SizedBox(height: 8),
              _DurationSection(
                controller: _durationController,
                palette: palette,
                onChipTap: (val) => setState(() {
                  _durationController.text = val.toString();
                  _errorMessage = null;
                }),
              ),
              const SizedBox(height: 14),

              // ── Nota ──────────────────────────────────────────────────
              _FieldLabel(label: 'NOTA (opcional)', palette: palette), // i18n
              const SizedBox(height: 8),
              TextField(
                controller: _noteController,
                maxLines: 2,
                style: GoogleFonts.barlow(
                  fontSize: 14,
                  color: palette.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Ej: traer banda, primera sesión…', // i18n
                  hintStyle: GoogleFonts.barlow(
                    fontSize: 14,
                    color: palette.textMuted,
                  ),
                  filled: true,
                  fillColor: palette.bg,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: palette.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: palette.accent, width: 1.5),
                  ),
                ),
              ),

              // ── Error message ─────────────────────────────────────────
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: GoogleFonts.barlow(
                    fontSize: 13,
                    color: palette.danger,
                  ),
                ),
              ],

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(foregroundColor: palette.textMuted),
          child: Text(
            'Cancelar', // i18n
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: (_saving || !hasActiveLinks) ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: palette.accent,
            foregroundColor: palette.bg,
            shape: const StadiumBorder(),
            disabledBackgroundColor: palette.accent.withValues(alpha: 0.3),
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
                  'REGISTRAR SESIÓN', // i18n
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.8,
                  ),
                ),
        ),
      ],
    );
  }
}

// ─── _AthleteDropdown ─────────────────────────────────────────────────────────

/// Dropdown de selección de alumno activo.
/// Carga el displayName via [userPublicProfileProvider] con fallback a
/// "Alumno (xxxxxx)" (mirror de la lógica de new_session_sheet.dart:928-931).
class _AthleteDropdown extends ConsumerWidget {
  const _AthleteDropdown({
    required this.links,
    required this.selectedId,
    required this.palette,
    required this.onChanged,
  });

  final List<TrainerLink> links;
  final String? selectedId;
  final AppPalette palette;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DropdownButtonFormField<String>(
      initialValue: selectedId,
      hint: Text(
        'Seleccioná un alumno', // i18n
        style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
      ),
      dropdownColor: palette.bgCard,
      style: GoogleFonts.barlow(fontSize: 14, color: palette.textPrimary),
      decoration: InputDecoration(
        filled: true,
        fillColor: palette.bg,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.accent, width: 1.5),
        ),
      ),
      items: links.map((link) {
        final profileAsync =
            ref.watch(userPublicProfileProvider(link.athleteId));
        final rawName = profileAsync.valueOrNull?.displayName ?? '';
        final showName = rawName.isEmpty || _looksLikeUid(rawName)
            ? 'Alumno (${link.athleteId.substring(0, 6)})' // i18n
            : rawName;
        return DropdownMenuItem<String>(
          value: link.athleteId,
          child: Text(showName),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }

  bool _looksLikeUid(String s) {
    if (s.length < 20) return false;
    if (s.contains(' ')) return false;
    return RegExp(r'^[a-zA-Z0-9]+$').hasMatch(s);
  }
}

// ─── _DurationSection ─────────────────────────────────────────────────────────

/// Campo de duración libre (5..480 min) + chips de presets {30,45,60,90,120}.
/// Mirror de _DurationSection en new_session_sheet.dart (ADR-AGW-6).
const _kDurations = [30, 45, 60, 90, 120];

class _DurationSection extends StatefulWidget {
  const _DurationSection({
    required this.controller,
    required this.palette,
    required this.onChipTap,
  });

  final TextEditingController controller;
  final AppPalette palette;
  final ValueChanged<int> onChipTap;

  @override
  State<_DurationSection> createState() => _DurationSectionState();
}

class _DurationSectionState extends State<_DurationSection> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final parsed = int.tryParse(widget.controller.text.trim());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Input libre
        TextField(
          controller: widget.controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: GoogleFonts.barlow(fontSize: 14, color: palette.textPrimary),
          decoration: InputDecoration(
            hintText: '60', // i18n
            hintStyle:
                GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
            filled: true,
            fillColor: palette.bg,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: palette.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: palette.accent, width: 1.5),
            ),
            suffixText: 'min',
            suffixStyle:
                GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
          ),
        ),
        const SizedBox(height: 8),
        // Chips de presets
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _kDurations.map((min) {
            final isSelected = parsed == min;
            return ChoiceChip(
              label: Text(
                '$min', // i18n
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 0.5,
                  color: isSelected ? palette.bg : palette.textPrimary,
                ),
              ),
              selected: isSelected,
              selectedColor: palette.accent,
              backgroundColor: palette.bg,
              side: BorderSide(
                color: isSelected ? palette.accent : palette.border,
              ),
              onSelected: (_) => widget.onChipTap(min),
              showCheckmark: false,
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ─── _TappableField ───────────────────────────────────────────────────────────

/// Fila tappeable para fecha y hora.
class _TappableField extends StatelessWidget {
  const _TappableField({
    required this.palette,
    required this.text,
    required this.onTap,
  });

  final AppPalette palette;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: palette.bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: GoogleFonts.barlow(
                  fontSize: 14,
                  color: palette.textPrimary,
                ),
              ),
            ),
            Icon(Icons.edit_calendar_outlined,
                size: 16, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}

// ─── _FieldLabel ──────────────────────────────────────────────────────────────

/// Etiqueta de campo — barlow condensed caps.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, required this.palette});
  final String label;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.barlowCondensed(
        fontWeight: FontWeight.w700,
        fontSize: 11,
        letterSpacing: 1.2,
        color: palette.textMuted,
      ),
    );
  }
}
