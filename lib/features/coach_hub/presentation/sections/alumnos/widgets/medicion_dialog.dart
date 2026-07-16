import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/measurements/application/measurement_providers.dart';
import 'package:treino/features/measurements/domain/measurement.dart';

import 'medicion_form_fields.dart';

/// Dialog de alta/edición de una medición antropométrica — Fase 3 WU-06a.
///
/// Extraído de `_NuevaMedicionDialog` (`alumno_detail_screen.dart`,
/// ADR-A3-04) al kit v2: `TreinoDialog`/`showTreinoDialog` en vez del
/// `Dialog` bespoke. Todos los campos son opcionales — el PF loguea solo lo
/// que midió esa sesión. Composición corporal siempre expandida (la
/// sección más común); las circunferencias en 3 secciones colapsables para
/// no abrumar.
///
/// [initial] no-nulo → modo edición (preserva `id`/`recordedBy`/
/// `athleteId`/`recordedAt`, guarda con `MeasurementRepository.update`).
/// Nulo → modo crear (`.add`).
///
/// Uso: `showTreinoDialog<void>(context, builder: (_) => MedicionDialog(...))`.
class MedicionDialog extends ConsumerStatefulWidget {
  const MedicionDialog({
    super.key,
    required this.athleteId,
    required this.trainerUid,
    this.initial,
  });

  final String athleteId;
  final String trainerUid;
  final Measurement? initial;

  @override
  ConsumerState<MedicionDialog> createState() => _MedicionDialogState();
}

class _MedicionDialogState extends ConsumerState<MedicionDialog> {
  // `TreinoDialog` tiene maxWidth fijo (480, `TreinoDialogTokens`) sin
  // maxHeight — con ~20 campos opcionales el form no entra en el viewport,
  // así que se acota la zona scrolleable a una altura fija.
  static const double _formHeight = 480;

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
      _weightC,
      _fatC,
      _muscleC,
      _shouldersC,
      _chestC,
      _waistC,
      _hipsC,
      _glutesC,
      _bicepsLC,
      _bicepsRC,
      _bicepsFlexedLC,
      _bicepsFlexedRC,
      _forearmLC,
      _forearmRC,
      _upperThighLC,
      _upperThighRC,
      _midThighLC,
      _midThighRC,
      _calfLC,
      _calfRC,
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
          content: Text('No pudimos guardar la medición.'), // i18n: Fase W2
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return TreinoDialog(
      title: _isEditing
          ? 'Editar medición' // i18n: Fase W2
          : 'Nueva medición', // i18n: Fase W2
      loading: _saving,
      primaryLabel: 'GUARDAR', // i18n: Fase W2
      onPrimaryTap: _save,
      secondaryLabel: 'Cancelar', // i18n: Fase W2
      onSecondaryTap: _saving ? null : () => Navigator.of(context).pop(),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Cargá los campos que hayas medido. '
            'Todos son opcionales.', // i18n: Fase W2
            style: TextStyle(color: palette.textMuted, fontSize: 13),
          ),
          const SizedBox(height: AppSpacing.s12),
          SizedBox(
            height: _formHeight,
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MedicionFormSection(
                      title: 'COMPOSICIÓN CORPORAL', // i18n: Fase W2
                      palette: palette,
                      expanded: true,
                      onToggle: null,
                      children: [
                        MedicionFormField(
                            label: 'Peso',
                            suffix: 'kg',
                            controller: _weightC,
                            palette: palette),
                        MedicionFormField(
                            label: '% grasa',
                            suffix: '%',
                            controller: _fatC,
                            palette: palette),
                        MedicionFormField(
                            label: 'Masa muscular',
                            suffix: 'kg',
                            controller: _muscleC,
                            palette: palette),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    MedicionFormSection(
                      title: 'CIRCUNFERENCIAS TRUNK', // i18n: Fase W2
                      palette: palette,
                      expanded: _trunkExpanded,
                      onToggle: () =>
                          setState(() => _trunkExpanded = !_trunkExpanded),
                      children: [
                        MedicionFormField(
                            label: 'Hombros',
                            suffix: 'cm',
                            controller: _shouldersC,
                            palette: palette),
                        MedicionFormField(
                            label: 'Pecho',
                            suffix: 'cm',
                            controller: _chestC,
                            palette: palette),
                        MedicionFormField(
                            label: 'Cintura',
                            suffix: 'cm',
                            controller: _waistC,
                            palette: palette),
                        MedicionFormField(
                            label: 'Cadera',
                            suffix: 'cm',
                            controller: _hipsC,
                            palette: palette),
                        MedicionFormField(
                            label: 'Glúteos',
                            suffix: 'cm',
                            controller: _glutesC,
                            palette: palette),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    MedicionFormSection(
                      title: 'MIEMBROS SUPERIORES', // i18n: Fase W2
                      palette: palette,
                      expanded: _upperExpanded,
                      onToggle: () =>
                          setState(() => _upperExpanded = !_upperExpanded),
                      children: [
                        MedicionFormField(
                            label: 'Bíceps izq.',
                            suffix: 'cm',
                            controller: _bicepsLC,
                            palette: palette),
                        MedicionFormField(
                            label: 'Bíceps der.',
                            suffix: 'cm',
                            controller: _bicepsRC,
                            palette: palette),
                        MedicionFormField(
                            label: 'Bíceps flex. izq.',
                            suffix: 'cm',
                            controller: _bicepsFlexedLC,
                            palette: palette),
                        MedicionFormField(
                            label: 'Bíceps flex. der.',
                            suffix: 'cm',
                            controller: _bicepsFlexedRC,
                            palette: palette),
                        MedicionFormField(
                            label: 'Antebrazo izq.',
                            suffix: 'cm',
                            controller: _forearmLC,
                            palette: palette),
                        MedicionFormField(
                            label: 'Antebrazo der.',
                            suffix: 'cm',
                            controller: _forearmRC,
                            palette: palette),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    MedicionFormSection(
                      title: 'MIEMBROS INFERIORES', // i18n: Fase W2
                      palette: palette,
                      expanded: _lowerExpanded,
                      onToggle: () =>
                          setState(() => _lowerExpanded = !_lowerExpanded),
                      children: [
                        MedicionFormField(
                            label: 'Muslo sup. izq.',
                            suffix: 'cm',
                            controller: _upperThighLC,
                            palette: palette),
                        MedicionFormField(
                            label: 'Muslo sup. der.',
                            suffix: 'cm',
                            controller: _upperThighRC,
                            palette: palette),
                        MedicionFormField(
                            label: 'Muslo med. izq.',
                            suffix: 'cm',
                            controller: _midThighLC,
                            palette: palette),
                        MedicionFormField(
                            label: 'Muslo med. der.',
                            suffix: 'cm',
                            controller: _midThighRC,
                            palette: palette),
                        MedicionFormField(
                            label: 'Gemelo izq.',
                            suffix: 'cm',
                            controller: _calfLC,
                            palette: palette),
                        MedicionFormField(
                            label: 'Gemelo der.',
                            suffix: 'cm',
                            controller: _calfRC,
                            palette: palette),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    TextField(
                      controller: _notesC,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Nota (opcional)', // i18n: Fase W2
                        labelStyle: TextStyle(color: palette.textMuted),
                        filled: true,
                        fillColor: palette.bgCard,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
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
        ],
      ),
    );
  }
}
