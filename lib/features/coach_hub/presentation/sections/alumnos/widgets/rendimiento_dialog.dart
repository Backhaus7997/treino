import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/performance/application/performance_test_providers.dart';
import 'package:treino/features/performance/domain/performance_test.dart';

import 'medicion_form_fields.dart';

/// Dialog de alta/edición de una prueba de rendimiento — Fase 3 WU-06a.
///
/// Extraído de `_NuevoRendimientoDialog` (`alumno_detail_screen.dart`,
/// ADR-A3-04) al kit v2: `TreinoDialog`/`showTreinoDialog` en vez del
/// `Dialog` bespoke. Todos los campos opcionales. Saltos siempre expandido
/// (la sección más común); Sprints, 1RM y Resistencia colapsables.
///
/// [initial] no-nulo → modo edición. Mismo patrón que `MedicionDialog`.
///
/// Uso:
/// `showTreinoDialog<void>(context, builder: (_) => RendimientoDialog(...))`.
class RendimientoDialog extends ConsumerStatefulWidget {
  const RendimientoDialog({
    super.key,
    required this.athleteId,
    required this.trainerUid,
    this.initial,
  });

  final String athleteId;
  final String trainerUid;
  final PerformanceTest? initial;

  @override
  ConsumerState<RendimientoDialog> createState() => _RendimientoDialogState();
}

class _RendimientoDialogState extends ConsumerState<RendimientoDialog> {
  static const double _formHeight = 480;

  final _formKey = GlobalKey<FormState>();

  // Saltos
  final _cmjC = TextEditingController();
  final _squatJumpC = TextEditingController();
  final _abalakovC = TextEditingController();
  final _broadJumpC = TextEditingController();
  // Sprints
  final _sprint10C = TextEditingController();
  final _sprint20C = TextEditingController();
  final _sprint30C = TextEditingController();
  final _sprint40C = TextEditingController();
  // 1RM
  final _squat1rmC = TextEditingController();
  final _bench1rmC = TextEditingController();
  final _deadlift1rmC = TextEditingController();
  final _overhead1rmC = TextEditingController();
  final _pullUp1rmC = TextEditingController();
  // Resistencia
  final _vo2maxC = TextEditingController();
  final _courseNavetteC = TextEditingController();
  final _cooperC = TextEditingController();
  final _sitAndReachC = TextEditingController();
  // Meta
  final _notesC = TextEditingController();

  bool _sprintsExpanded = false;
  bool _oneRmExpanded = false;
  bool _resistExpanded = false;
  bool _saving = false;

  bool get _isEditing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    if (initial == null) return;

    void set(TextEditingController c, double? v) {
      if (v != null) c.text = v.toString();
    }

    set(_cmjC, initial.cmjCm);
    set(_squatJumpC, initial.squatJumpCm);
    set(_abalakovC, initial.abalakovCm);
    set(_broadJumpC, initial.broadJumpCm);
    set(_sprint10C, initial.sprint10mS);
    set(_sprint20C, initial.sprint20mS);
    set(_sprint30C, initial.sprint30mS);
    set(_sprint40C, initial.sprint40mS);
    set(_squat1rmC, initial.squat1rmKg);
    set(_bench1rmC, initial.benchPress1rmKg);
    set(_deadlift1rmC, initial.deadlift1rmKg);
    set(_overhead1rmC, initial.overheadPress1rmKg);
    set(_pullUp1rmC, initial.pullUp1rmKg);
    set(_vo2maxC, initial.vo2maxMlKgMin);
    set(_courseNavetteC, initial.courseNavetteLevel);
    set(_cooperC, initial.cooperMeters);
    set(_sitAndReachC, initial.sitAndReachCm);
    if (initial.notes != null) _notesC.text = initial.notes!;

    _sprintsExpanded = initial.sprint10mS != null ||
        initial.sprint20mS != null ||
        initial.sprint30mS != null ||
        initial.sprint40mS != null;
    _oneRmExpanded = initial.squat1rmKg != null ||
        initial.benchPress1rmKg != null ||
        initial.deadlift1rmKg != null ||
        initial.overheadPress1rmKg != null ||
        initial.pullUp1rmKg != null;
    _resistExpanded = initial.vo2maxMlKgMin != null ||
        initial.courseNavetteLevel != null ||
        initial.cooperMeters != null ||
        initial.sitAndReachCm != null;
  }

  @override
  void dispose() {
    for (final c in [
      _cmjC,
      _squatJumpC,
      _abalakovC,
      _broadJumpC,
      _sprint10C,
      _sprint20C,
      _sprint30C,
      _sprint40C,
      _squat1rmC,
      _bench1rmC,
      _deadlift1rmC,
      _overhead1rmC,
      _pullUp1rmC,
      _vo2maxC,
      _courseNavetteC,
      _cooperC,
      _sitAndReachC,
      _notesC,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

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
      final test = PerformanceTest(
        id: initial?.id ?? '',
        athleteId: widget.athleteId,
        recordedBy: widget.trainerUid,
        recordedAt: initial?.recordedAt ?? DateTime.now(),
        cmjCm: _parse(_cmjC),
        squatJumpCm: _parse(_squatJumpC),
        abalakovCm: _parse(_abalakovC),
        broadJumpCm: _parse(_broadJumpC),
        sprint10mS: _parse(_sprint10C),
        sprint20mS: _parse(_sprint20C),
        sprint30mS: _parse(_sprint30C),
        sprint40mS: _parse(_sprint40C),
        squat1rmKg: _parse(_squat1rmC),
        benchPress1rmKg: _parse(_bench1rmC),
        deadlift1rmKg: _parse(_deadlift1rmC),
        overheadPress1rmKg: _parse(_overhead1rmC),
        pullUp1rmKg: _parse(_pullUp1rmC),
        vo2maxMlKgMin: _parse(_vo2maxC),
        courseNavetteLevel: _parse(_courseNavetteC),
        cooperMeters: _parse(_cooperC),
        sitAndReachCm: _parse(_sitAndReachC),
        notes: _notesC.text.trim().isEmpty ? null : _notesC.text.trim(),
      );
      final repo = ref.read(performanceTestRepositoryProvider);
      if (_isEditing) {
        await repo.update(test);
      } else {
        await repo.add(test);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(_isEditing
              ? 'Prueba actualizada.' // i18n: Fase W2
              : 'Prueba guardada.'), // i18n: Fase W2
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('No pudimos guardar la prueba.'), // i18n: Fase W2
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
          ? 'Editar prueba de rendimiento' // i18n: Fase W2
          : 'Nueva prueba de rendimiento', // i18n: Fase W2
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
                      title: 'SALTOS', // i18n: Fase W2
                      palette: palette,
                      expanded: true,
                      onToggle: null,
                      children: [
                        MedicionFormField(
                            label: 'CMJ',
                            suffix: 'cm',
                            controller: _cmjC,
                            palette: palette),
                        MedicionFormField(
                            label: 'Squat Jump',
                            suffix: 'cm',
                            controller: _squatJumpC,
                            palette: palette),
                        MedicionFormField(
                            label: 'Abalakov',
                            suffix: 'cm',
                            controller: _abalakovC,
                            palette: palette),
                        MedicionFormField(
                            label: 'Salto largo',
                            suffix: 'cm',
                            controller: _broadJumpC,
                            palette: palette),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    MedicionFormSection(
                      title: 'SPRINTS', // i18n: Fase W2
                      palette: palette,
                      expanded: _sprintsExpanded,
                      onToggle: () =>
                          setState(() => _sprintsExpanded = !_sprintsExpanded),
                      children: [
                        MedicionFormField(
                            label: 'Sprint 10m',
                            suffix: 's',
                            controller: _sprint10C,
                            palette: palette),
                        MedicionFormField(
                            label: 'Sprint 20m',
                            suffix: 's',
                            controller: _sprint20C,
                            palette: palette),
                        MedicionFormField(
                            label: 'Sprint 30m',
                            suffix: 's',
                            controller: _sprint30C,
                            palette: palette),
                        MedicionFormField(
                            label: 'Sprint 40m',
                            suffix: 's',
                            controller: _sprint40C,
                            palette: palette),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    MedicionFormSection(
                      title: 'FUERZA MÁXIMA 1RM', // i18n: Fase W2
                      palette: palette,
                      expanded: _oneRmExpanded,
                      onToggle: () =>
                          setState(() => _oneRmExpanded = !_oneRmExpanded),
                      children: [
                        MedicionFormField(
                            label: 'Sentadilla',
                            suffix: 'kg',
                            controller: _squat1rmC,
                            palette: palette),
                        MedicionFormField(
                            label: 'Press banca',
                            suffix: 'kg',
                            controller: _bench1rmC,
                            palette: palette),
                        MedicionFormField(
                            label: 'Peso muerto',
                            suffix: 'kg',
                            controller: _deadlift1rmC,
                            palette: palette),
                        MedicionFormField(
                            label: 'Press militar',
                            suffix: 'kg',
                            controller: _overhead1rmC,
                            palette: palette),
                        MedicionFormField(
                            label: 'Dominada',
                            suffix: 'kg',
                            controller: _pullUp1rmC,
                            palette: palette),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s12),
                    MedicionFormSection(
                      title: 'RESISTENCIA / FLEXIBILIDAD', // i18n: Fase W2
                      palette: palette,
                      expanded: _resistExpanded,
                      onToggle: () =>
                          setState(() => _resistExpanded = !_resistExpanded),
                      children: [
                        MedicionFormField(
                            label: 'VO2 máx',
                            suffix: 'ml/kg/min',
                            controller: _vo2maxC,
                            palette: palette),
                        MedicionFormField(
                            label: 'Course Navette',
                            suffix: 'nivel',
                            controller: _courseNavetteC,
                            palette: palette),
                        MedicionFormField(
                            label: 'Cooper',
                            suffix: 'm',
                            controller: _cooperC,
                            palette: palette),
                        MedicionFormField(
                            label: 'Sit & Reach',
                            suffix: 'cm',
                            controller: _sitAndReachC,
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
