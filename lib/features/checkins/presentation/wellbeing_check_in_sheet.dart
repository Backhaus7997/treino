import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/motion/treino_tappable.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../workout/domain/muscle_group.dart';
import '../application/check_in_providers.dart';
import '../domain/check_in.dart';
import 'widgets/wellbeing_mood_row.dart';

/// Abre el paso de check-in de bienestar.
///
/// Lo usan los DOS puntos de captura, y es a propósito que sea el mismo sheet:
/// al terminar una sesión ([sessionId] cargado) y desde la tarjeta diaria de
/// Inicio ([sessionId] en `null`). Dos formularios distintos para el mismo
/// dato serían dos vocabularios divergiendo desde el día uno.
///
/// **Es saltable de verdad y no cuesta nada saltearlo.** El momento
/// post-entreno es cuando el usuario quiere irse: el sheet se cierra con el
/// gesto de arrastre, con el back del sistema, tocando fuera o con el botón
/// "ahora no", y la sesión ya quedó guardada mucho antes de llegar acá. Un
/// formulario obligatorio en este punto no genera datos: genera abandono del
/// registro de la sesión, que es el dato que hoy sí tenemos.
///
/// Devuelve `true` si el usuario guardó, y `null` si salió sin guardar.
///
/// [initialFeeling] precarga el nivel que el usuario ya tocó afuera, así el tap
/// que abre el sheet no se pierde. [existing] es el registro que este mismo
/// origen ya dejó: con él, guardar EDITA ese documento; sin él se crea uno
/// nuevo, que no pisa nada de lo ya registrado ese día.
Future<bool?> showWellbeingCheckInSheet(
  BuildContext context, {
  String? sessionId,
  CheckInFeeling? initialFeeling,
  CheckIn? existing,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => WellbeingCheckInSheet(
      sessionId: sessionId,
      initialFeeling: initialFeeling ?? existing?.feeling,
      existing: existing,
    ),
  );
}

/// Contenido del sheet. Público sólo para que los tests lo monten sin pasar por
/// una ruta modal.
class WellbeingCheckInSheet extends ConsumerStatefulWidget {
  const WellbeingCheckInSheet({
    super.key,
    this.sessionId,
    this.initialFeeling,
    this.existing,
  });

  /// Sesión que originó el registro, o `null` para el check-in diario.
  final String? sessionId;
  final CheckInFeeling? initialFeeling;
  final CheckIn? existing;

  @override
  ConsumerState<WellbeingCheckInSheet> createState() =>
      _WellbeingCheckInSheetState();
}

class _WellbeingCheckInSheetState extends ConsumerState<WellbeingCheckInSheet> {
  late CheckInFeeling? _feeling;
  late bool _hasPain;
  late Set<MuscleGroup> _painAreas;
  late final TextEditingController _noteController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _feeling = widget.initialFeeling ?? existing?.feeling;
    _hasPain = existing?.hasPain ?? false;
    _painAreas = {...?existing?.painAreas};
    _noteController = TextEditingController(text: existing?.note ?? '');
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final feeling = _feeling;
    if (feeling == null || _saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(checkInNotifierProvider.notifier).submit(
            feeling: feeling,
            hasPain: _hasPain,
            painAreas: _painAreas.toList(),
            note: _noteController.text,
            sessionId: widget.sessionId,
            existing: widget.existing,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      // El sheet queda abierto: lo que el usuario escribió no se pierde y
      // puede reintentar. Avisar el fallo es obligatorio — dar por guardado un
      // registro que no se guardó es peor que no ofrecer el registro.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppL10n.of(context).wellbeingSaveError)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;

    return Padding(
      // El teclado de la nota libre empuja el contenido en vez de taparlo.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: palette.bg,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                ),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      // Pasado al cerrar una sesión ("¿cómo te sentiste?"),
                      // presente desde Inicio ("¿cómo te sentís hoy?"): el
                      // check-in diario no pregunta por un entreno que puede
                      // no haber existido.
                      widget.sessionId == null
                          ? l10n.wellbeingDailyTitle
                          : l10n.wellbeingCheckInTitle,
                      style: GoogleFonts.barlowCondensed(
                        color: palette.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.wellbeingCheckInOptional,
                      style: GoogleFonts.barlow(
                        color: palette.textMuted,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _FeelingScale(
                      selected: _feeling,
                      onSelect: (f) => setState(() => _feeling = f),
                    ),
                    const SizedBox(height: 20),
                    Divider(height: 1, color: palette.border),
                    const SizedBox(height: 18),
                    Text(
                      l10n.wellbeingPainQuestion,
                      style: GoogleFonts.barlow(
                        color: palette.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _PainToggle(
                      hasPain: _hasPain,
                      onChanged: (v) => setState(() {
                        _hasPain = v;
                        if (!v) _painAreas.clear();
                      }),
                    ),
                    if (_hasPain) ...[
                      const SizedBox(height: 18),
                      Text(
                        l10n.wellbeingPainAreasQuestion,
                        style: GoogleFonts.barlow(
                          color: palette.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.wellbeingPainAreasHint,
                        style: GoogleFonts.barlow(
                          color: palette.textMuted,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _PainAreaChips(
                        selected: _painAreas,
                        onToggle: (g) => setState(() {
                          if (!_painAreas.remove(g)) _painAreas.add(g);
                        }),
                      ),
                      const SizedBox(height: 14),
                      // Texto neutro y terminal: la app NO interpreta el dato,
                      // no sugiere ejercicios "para el dolor" ni condiciona
                      // nada de la sesión a esta respuesta.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(TreinoIcon.infoCircle,
                              size: 16, color: palette.textMuted),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.wellbeingMedicalDisclaimer,
                              style: GoogleFonts.barlow(
                                color: palette.textMuted,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 18),
                    Divider(height: 1, color: palette.border),
                    const SizedBox(height: 18),
                    Text(
                      l10n.wellbeingNoteLabel,
                      style: GoogleFonts.barlow(
                        color: palette.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _noteController,
                      maxLines: 3,
                      maxLength: kCheckInNoteMaxLength,
                      // El contador de caracteres es ruido para un campo que
                      // casi nunca se acerca al tope; el tope sigue vigente.
                      buildCounter: (_,
                              {required currentLength,
                              required isFocused,
                              maxLength}) =>
                          null,
                      style: GoogleFonts.barlow(
                        color: palette.textPrimary,
                        fontSize: 15,
                      ),
                      decoration: InputDecoration(
                        hintText: l10n.wellbeingNoteHint,
                        hintStyle: GoogleFonts.barlow(
                          color: palette.textMuted,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      // Sin nivel elegido no hay nada que registrar: el
                      // resto de los campos son opcionales.
                      onPressed:
                          _feeling == null || _saving ? null : () => _save(),
                      child: _saving
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: palette.bg,
                              ),
                            )
                          : Text(l10n.wellbeingSaveButton),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      l10n.wellbeingSkipButton,
                      style: GoogleFonts.barlow(
                        color: palette.textMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Escala de sensación ──────────────────────────────────────────────────────

/// Los 5 niveles en fila. Emoji grande + etiqueta en texto: el emoji solo no
/// alcanza para quien no lo interpreta igual, y el segmento que más pidió esta
/// función (adultos mayores) es justo el que peor tolera la jerga visual.
class _FeelingScale extends StatelessWidget {
  const _FeelingScale({required this.selected, required this.onSelect});

  final CheckInFeeling? selected;
  final ValueChanged<CheckInFeeling> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final feeling in CheckInFeeling.displayOrder)
          Expanded(
            child: _FeelingOption(
              feeling: feeling,
              selected: feeling == selected,
              onTap: () => onSelect(feeling),
            ),
          ),
      ],
    );
  }
}

class _FeelingOption extends StatelessWidget {
  const _FeelingOption({
    required this.feeling,
    required this.selected,
    required this.onTap,
  });

  final CheckInFeeling feeling;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final label = feelingLabel(AppL10n.of(context), feeling);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: TreinoTappable(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          decoration: BoxDecoration(
            color: selected
                ? palette.accent.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: selected ? palette.accent : palette.border,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              WellbeingMoodGlyph(feeling.emoji, fontSize: 26),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: GoogleFonts.barlow(
                    color: selected ? palette.accent : palette.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Etiqueta localizada de un nivel. Vive acá (y no en el enum) porque el enum
/// es dominio y no conoce el locale.
String feelingLabel(AppL10n l10n, CheckInFeeling feeling) => switch (feeling) {
      CheckInFeeling.muyMal => l10n.wellbeingFeelingVeryBad,
      CheckInFeeling.mal => l10n.wellbeingFeelingBad,
      CheckInFeeling.normal => l10n.wellbeingFeelingNeutral,
      CheckInFeeling.bien => l10n.wellbeingFeelingGood,
      CheckInFeeling.muyBien => l10n.wellbeingFeelingGreat,
    };

// ── Dolor sí/no ──────────────────────────────────────────────────────────────

class _PainToggle extends StatelessWidget {
  const _PainToggle({required this.hasPain, required this.onChanged});

  final bool hasPain;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Row(
      children: [
        Expanded(
          child: _PainOption(
            label: l10n.wellbeingPainNo,
            selected: !hasPain,
            onTap: () => onChanged(false),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _PainOption(
            label: l10n.wellbeingPainYes,
            selected: hasPain,
            onTap: () => onChanged(true),
          ),
        ),
      ],
    );
  }
}

class _PainOption extends StatelessWidget {
  const _PainOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: TreinoTappable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? palette.accent.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(
              color: selected ? palette.accent : palette.border,
              width: 1.5,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.barlowCondensed(
              color: selected ? palette.accent : palette.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Zonas ────────────────────────────────────────────────────────────────────

/// Chips de zona sobre [kCheckInPainAreas] — la taxonomía de [MuscleGroup], la
/// misma del catálogo, el picker y el rollup de Insights. Acá NO se inventa un
/// vocabulario de zonas nuevo.
class _PainAreaChips extends StatelessWidget {
  const _PainAreaChips({required this.selected, required this.onToggle});

  final Set<MuscleGroup> selected;
  final ValueChanged<MuscleGroup> onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final group in kCheckInPainAreas)
          Semantics(
            button: true,
            selected: selected.contains(group),
            child: TreinoTappable(
              onTap: () => onToggle(group),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: selected.contains(group)
                      ? palette.accent.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(
                    color: selected.contains(group)
                        ? palette.accent
                        : palette.border,
                    width: 1.5,
                  ),
                ),
                child: Text(
                  group.label,
                  style: GoogleFonts.barlow(
                    color: selected.contains(group)
                        ? palette.accent
                        : palette.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
