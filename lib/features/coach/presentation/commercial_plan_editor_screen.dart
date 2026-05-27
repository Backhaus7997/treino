import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../application/commercial_plan_providers.dart';
import '../domain/commercial_plan.dart';

/// Create or edit a commercial plan.
///
/// Routed at `/profile/commercial-plans/new` (create) or
/// `/profile/commercial-plans/:planId` (edit). When [planId] is `'new'` or
/// null we render a blank form; otherwise we read the plan from the trainer
/// stream and pre-fill the fields.
class CommercialPlanEditorScreen extends ConsumerStatefulWidget {
  const CommercialPlanEditorScreen({super.key, this.planId});

  /// Plan id from the route, or `null` for the create flow.
  final String? planId;

  bool get isEditing => planId != null && planId != 'new';

  @override
  ConsumerState<CommercialPlanEditorScreen> createState() =>
      _CommercialPlanEditorScreenState();
}

class _CommercialPlanEditorScreenState
    extends ConsumerState<CommercialPlanEditorScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _durationCtrl = TextEditingController(text: '1');
  BillingFrequency _frequency = BillingFrequency.monthly;
  final Set<PlanInclude> _includes = <PlanInclude>{};
  bool _initialized = false;
  bool _saving = false;
  bool _archiving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  /// Pre-fill from existing plan once (when editing). Idempotent — guarded
  /// by [_initialized] so subsequent stream emissions don't clobber user
  /// edits.
  void _hydrateFrom(CommercialPlan plan) {
    if (_initialized) return;
    _initialized = true;
    _nameCtrl.text = plan.name;
    _descCtrl.text = plan.shortDescription;
    _priceCtrl.text = plan.priceArs.toString();
    _durationCtrl.text = plan.durationMonths.toString();
    _frequency = plan.billingFrequency;
    _includes
      ..clear()
      ..addAll(plan.includes);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final uid = ref.watch(currentUidProvider) ?? '';

    CommercialPlan? existing;
    if (widget.isEditing && uid.isNotEmpty) {
      final plansAsync =
          ref.watch(commercialPlansForTrainerStreamProvider(uid));
      final list = plansAsync.valueOrNull ?? const <CommercialPlan>[];
      existing = list.where((p) => p.id == widget.planId).firstOrNull;
      if (existing != null) _hydrateFrom(existing);
    }

    return Column(
      children: [
        _Header(
          title: widget.isEditing ? 'EDITAR PLAN' : 'CREAR PLAN',
          palette: palette,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
            physics: const ClampingScrollPhysics(),
            children: [
              _SectionLabel('INFORMACIÓN GENERAL', palette: palette),
              const SizedBox(height: 8),
              _FieldLabel('Nombre del plan', palette: palette),
              const SizedBox(height: 6),
              _TextField(
                controller: _nameCtrl,
                hint: 'Ej: Premium',
                palette: palette,
              ),
              const SizedBox(height: 14),
              _FieldLabel('Descripción corta', palette: palette),
              const SizedBox(height: 6),
              _TextField(
                controller: _descCtrl,
                hint: 'Ej: Coaching completo con seguimiento semanal',
                palette: palette,
                maxLines: 3,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _FieldLabel('Duración (meses)', palette: palette),
                        const SizedBox(height: 6),
                        _TextField(
                          controller: _durationCtrl,
                          hint: '1',
                          palette: palette,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _FieldLabel('Cobra cada', palette: palette),
                        const SizedBox(height: 6),
                        _FrequencyDropdown(
                          value: _frequency,
                          onChanged: (v) => setState(() => _frequency = v),
                          palette: palette,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _FieldLabel('Precio (ARS)', palette: palette),
              const SizedBox(height: 6),
              _TextField(
                controller: _priceCtrl,
                hint: '24000',
                palette: palette,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: 22),
              _SectionLabel('¿QUÉ INCLUYE ESTE PLAN?', palette: palette),
              const SizedBox(height: 8),
              for (final inc in PlanInclude.values)
                _IncludeRow(
                  label: inc.label,
                  selected: _includes.contains(inc),
                  onToggle: () => setState(() {
                    if (_includes.contains(inc)) {
                      _includes.remove(inc);
                    } else {
                      _includes.add(inc);
                    }
                  }),
                  palette: palette,
                ),
              if (widget.isEditing &&
                  existing != null &&
                  existing.status == CommercialPlanStatus.active) ...[
                const SizedBox(height: 24),
                _ArchiveButton(
                  onTap: _archiving ? null : () => _onArchive(context, ref),
                  palette: palette,
                  loading: _archiving,
                ),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    _saving ? null : () => _onSave(context, ref, existing),
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.bg,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9999),
                  ),
                ),
                child: _saving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: palette.bg,
                        ),
                      )
                    : Text(
                        widget.isEditing ? 'GUARDAR CAMBIOS' : 'GUARDAR PLAN',
                        style: GoogleFonts.barlowCondensed(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          letterSpacing: 0.8,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _onSave(
    BuildContext context,
    WidgetRef ref,
    CommercialPlan? existing,
  ) async {
    final uid = ref.read(currentUidProvider) ?? '';
    if (uid.isEmpty) return;

    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _toast(context, 'Poné un nombre al plan.');
      return;
    }
    final price = int.tryParse(_priceCtrl.text.trim());
    if (price == null || price < 0) {
      _toast(context, 'Precio inválido.');
      return;
    }
    final duration = int.tryParse(_durationCtrl.text.trim()) ?? 1;

    setState(() => _saving = true);
    try {
      final repo = ref.read(commercialPlanRepositoryProvider);
      if (existing != null) {
        await repo.update(existing.copyWith(
          name: name,
          shortDescription: _descCtrl.text.trim(),
          priceArs: price,
          durationMonths: duration < 1 ? 1 : duration,
          billingFrequency: _frequency,
          includes: _includes.toList(),
        ));
      } else {
        await repo.create(
          trainerId: uid,
          name: name,
          shortDescription: _descCtrl.text.trim(),
          priceArs: price,
          durationMonths: duration < 1 ? 1 : duration,
          billingFrequency: _frequency,
          includes: _includes.toList(),
        );
      }
      if (!context.mounted) return;
      context.pop();
    } catch (e) {
      if (!context.mounted) return;
      _toast(context, 'No pudimos guardar el plan.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onArchive(BuildContext context, WidgetRef ref) async {
    final planId = widget.planId;
    if (planId == null || planId == 'new') return;

    final palette = AppPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Archivar plan',
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: palette.textPrimary,
          ),
        ),
        content: Text(
          'El plan deja de estar visible para nuevas suscripciones. Las suscripciones existentes no se afectan.',
          style: GoogleFonts.barlow(fontSize: 14, color: palette.textPrimary),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: palette.textPrimary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.highlight,
              foregroundColor: palette.bg,
            ),
            child: Text(
              'Archivar',
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    setState(() => _archiving = true);
    try {
      await ref.read(commercialPlanRepositoryProvider).archive(planId);
      if (!context.mounted) return;
      context.pop();
    } catch (_) {
      if (!context.mounted) return;
      _toast(context, 'No pudimos archivar el plan.');
    } finally {
      if (mounted) setState(() => _archiving = false);
    }
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.palette});
  final String title;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            behavior: HitTestBehavior.opaque,
            child:
                Icon(TreinoIcon.back, size: 20, color: palette.textPrimary),
          ),
          const SizedBox(width: 14),
          Text(
            title,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              letterSpacing: 1.0,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {required this.palette});
  final String label;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.barlowCondensed(
        fontWeight: FontWeight.w700,
        fontSize: 12,
        letterSpacing: 1.2,
        color: palette.textMuted,
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label, {required this.palette});
  final String label;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.barlow(
        fontWeight: FontWeight.w500,
        fontSize: 12,
        color: palette.textMuted,
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  const _TextField({
    required this.controller,
    required this.hint,
    required this.palette,
    this.keyboardType,
    this.inputFormatters,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String hint;
  final AppPalette palette;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      maxLines: maxLines,
      style: GoogleFonts.barlow(
        fontWeight: FontWeight.w500,
        fontSize: 14,
        color: palette.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.barlow(
          fontWeight: FontWeight.w400,
          fontSize: 14,
          color: palette.textMuted,
        ),
        filled: true,
        fillColor: palette.bgCard,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.accent, width: 1.5),
        ),
      ),
    );
  }
}

class _FrequencyDropdown extends StatelessWidget {
  const _FrequencyDropdown({
    required this.value,
    required this.onChanged,
    required this.palette,
  });

  final BillingFrequency value;
  final ValueChanged<BillingFrequency> onChanged;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border, width: 1),
      ),
      child: DropdownButton<BillingFrequency>(
        value: value,
        isExpanded: true,
        dropdownColor: palette.bgCard,
        underline: const SizedBox.shrink(),
        icon: Icon(TreinoIcon.forward, size: 16, color: palette.textMuted),
        style: GoogleFonts.barlow(
          fontWeight: FontWeight.w500,
          fontSize: 14,
          color: palette.textPrimary,
        ),
        items: [
          for (final f in BillingFrequency.values)
            DropdownMenuItem(value: f, child: Text(f.label)),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

class _IncludeRow extends StatelessWidget {
  const _IncludeRow({
    required this.label,
    required this.selected,
    required this.onToggle,
    required this.palette,
  });

  final String label;
  final bool selected;
  final VoidCallback onToggle;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? palette.accent
                      : Colors.transparent,
                  border: Border.all(
                    color: selected ? palette.accent : palette.border,
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: selected
                    ? Icon(TreinoIcon.check, size: 14, color: palette.bg)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 14,
                    color: palette.textPrimary,
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

class _ArchiveButton extends StatelessWidget {
  const _ArchiveButton({
    required this.onTap,
    required this.palette,
    required this.loading,
  });

  final VoidCallback? onTap;
  final AppPalette palette;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: palette.highlight, width: 1),
          foregroundColor: palette.highlight,
          minimumSize: const Size.fromHeight(44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999),
          ),
        ),
        child: loading
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: palette.highlight,
                ),
              )
            : Text(
                'ARCHIVAR PLAN',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 0.8,
                ),
              ),
      ),
    );
  }
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)),
  );
}
