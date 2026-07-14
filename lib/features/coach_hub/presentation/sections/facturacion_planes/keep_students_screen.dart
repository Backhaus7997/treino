import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../app/theme/app_palette.dart';

/// Un alumno candidato a conservar en el flujo keep-2. Vista mínima — el
/// wiring real (leer trainer_links + aplicar la selección vía CF) es PR5.
class KeepableStudent {
  const KeepableStudent({
    required this.athleteId,
    required this.displayName,
    this.avatarUrl,
  });

  final String athleteId;
  final String displayName;
  final String? avatarUrl;
}

/// Pantalla keep-2 (Fase 7, PR3 UI — trigger real en PR5).
///
/// Cuando el PF cae a Free por impago (7 días sin regularizar), conserva 2
/// alumnos y el resto queda bloqueado hasta que pague. Esta pantalla le deja
/// elegir CUÁLES 2, con un default pre-seleccionado (los más recientemente
/// activos — resuelto server-side). Misma armonía que el paywall: Mint
/// Magenta, Barlow Condensed, bordes redondeados.
///
/// [students] son los candidatos (activos/pausados con derecho). [keepLimit]
/// es cuántos puede conservar (2 en Free). [initialSelection] es el default.
class KeepStudentsScreen extends StatefulWidget {
  const KeepStudentsScreen({
    super.key,
    required this.students,
    this.keepLimit = 2,
    this.initialSelection = const {},
    this.onConfirm,
  });

  final List<KeepableStudent> students;
  final int keepLimit;
  final Set<String> initialSelection;

  /// Callback con los athleteIds elegidos. En PR5 dispara la CF
  /// `chooseKeptStudents`. Null en el preview.
  final void Function(Set<String> keptAthleteIds)? onConfirm;

  @override
  State<KeepStudentsScreen> createState() => _KeepStudentsScreenState();
}

class _KeepStudentsScreenState extends State<KeepStudentsScreen> {
  late final Set<String> _selected = {...widget.initialSelection};

  void _toggle(String athleteId) {
    setState(() {
      if (_selected.contains(athleteId)) {
        _selected.remove(athleteId);
      } else if (_selected.length < widget.keepLimit) {
        _selected.add(athleteId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final full = _selected.length >= widget.keepLimit;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 48),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.people_alt_outlined, size: 40, color: palette.accent),
              const SizedBox(height: 14),
              Text(
                'ELEGÍ QUÉ ALUMNOS CONSERVAR', // i18n: Fase W3
                textAlign: TextAlign.center,
                style: GoogleFonts.barlowCondensed(
                  color: palette.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tu plan pasó a Free por un pago pendiente. Podés conservar '
                '${widget.keepLimit} alumnos activos; el resto queda '
                'bloqueado hasta que regularices. No se elimina ninguno.',
                // i18n: Fase W3
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.textMuted, fontSize: 14),
              ),
              const SizedBox(height: 20),
              // Contador de selección.
              Text(
                '${_selected.length} / ${widget.keepLimit} elegidos', // i18n
                textAlign: TextAlign.center,
                style: GoogleFonts.barlowCondensed(
                  color: full ? palette.accent : palette.textMuted,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 16),
              for (final s in widget.students)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _StudentRow(
                    student: s,
                    selected: _selected.contains(s.athleteId),
                    // Deshabilita seleccionar más cuando está lleno (pero deja
                    // deseleccionar los ya elegidos).
                    disabled: full && !_selected.contains(s.athleteId),
                    palette: palette,
                    onTap: () => _toggle(s.athleteId),
                  ),
                ),
              const SizedBox(height: 12),
              _ConfirmButton(
                enabled: _selected.length == widget.keepLimit,
                palette: palette,
                onTap: () => widget.onConfirm?.call(_selected),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({
    required this.student,
    required this.selected,
    required this.disabled,
    required this.palette,
    required this.onTap,
  });

  final KeepableStudent student;
  final bool selected;
  final bool disabled;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: disabled ? 0.4 : 1,
      child: GestureDetector(
        onTap: disabled ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: palette.bgCard,
            border: Border.all(
              color: selected ? palette.accent : palette.border,
              width: selected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              // Avatar circular (inicial si no hay foto).
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.accent.withValues(alpha: 0.18),
                ),
                child: Text(
                  student.displayName.isNotEmpty
                      ? student.displayName[0].toUpperCase()
                      : '?',
                  style: GoogleFonts.barlowCondensed(
                    color: palette.accent,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  student.displayName,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Check mint cuando está seleccionado.
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 22,
                color: selected ? palette.accent : palette.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConfirmButton extends StatelessWidget {
  const _ConfirmButton({
    required this.enabled,
    required this.palette,
    required this.onTap,
  });

  final bool enabled;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.accent,
            borderRadius: BorderRadius.circular(9999),
          ),
          child: Text(
            'CONFIRMAR SELECCIÓN', // i18n: Fase W3
            style: GoogleFonts.barlowCondensed(
              color: palette.bg,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
    );
  }
}
