// EspecialidadPrecioCard — card «ESPECIALIDAD» + «PRECIO MENSUAL» de la
// columna izquierda de PerfilPublicoScreen (Fase 11, WU-04).
//
// `trainerSpecialty` es un enum FIJO de 10 valores y es SINGLE-select — el
// multi-select del mockup no tiene modelo (ADR-F11-01). Reusa
// [SpecialtyLabels] (mismo mapa de labels es-AR que ya usa
// `CoachDiscoveryPreviewCard`/`TrainerSpecialtyChips`, evita duplicar
// traducciones) y [TreinoFilterChips] del kit en modo `multiSelect: false`.
//
// El precio mensual sigue el mismo criterio de validación que
// `profile_edit_trainer_screen.dart` (entero, mínimo $500, máximo $999999).
// Guardado real vía `userRepositoryProvider.update` — mismo patrón
// dirty/saving/save de `IdentidadCard`/`_CuentaForm`.
//
// Modalidad y ubicaciones quedan READ-ONLY acá a propósito: editarlas
// inline dispara el invariante `UserRepository.update` que rechaza
// `trainerLocations.isEmpty && !trainerOffersOnline` — el partial de este
// card NUNCA incluye `trainerOffersOnline` ni `trainerLocations`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/features/coach/domain/trainer_specialty.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_specialty_chips.dart'
    show SpecialtyLabels;
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';

/// Card «ESPECIALIDAD» + «PRECIO MENSUAL» — columna izquierda de
/// `PerfilPublicoScreen` (WU-04).
class EspecialidadPrecioCard extends ConsumerStatefulWidget {
  const EspecialidadPrecioCard({super.key, required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<EspecialidadPrecioCard> createState() =>
      _EspecialidadPrecioCardState();
}

class _EspecialidadPrecioCardState
    extends ConsumerState<EspecialidadPrecioCard> {
  late TrainerSpecialty? _specialty;
  late final TextEditingController _price;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _specialty = trainerSpecialtyFromString(widget.profile.trainerSpecialty);
    _price = TextEditingController(
      text: widget.profile.trainerMonthlyRate?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _specialty !=
          trainerSpecialtyFromString(widget.profile.trainerSpecialty) ||
      _price.text.trim() !=
          (widget.profile.trainerMonthlyRate?.toString() ?? '');

  // Mismo criterio que profile_edit_trainer_screen.dart: entero, mínimo
  // $500, máximo $999999.
  String? get _priceError {
    final raw = _price.text.trim();
    if (raw.isEmpty) return 'Ingresá un precio.'; // i18n: Fase 11
    final n = int.tryParse(raw);
    if (n == null) return 'Ingresá un número entero.'; // i18n: Fase 11
    if (n < 500) return 'Mínimo \$500.'; // i18n: Fase 11
    if (n > 999999) return 'Máximo \$999999.'; // i18n: Fase 11
    return null;
  }

  bool get _canSave =>
      _dirty && _priceError == null && _specialty != null && !_saving;

  Future<void> _save() async {
    if (_saving) return;
    final specialty = _specialty;
    final error = _priceError;
    if (specialty == null || error != null) {
      _toast(error ?? 'Elegí una especialidad.'); // i18n: Fase 11
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(userRepositoryProvider).update(widget.profile.uid, {
        'trainerSpecialty': TrainerSpecialtyX.toWire(specialty),
        'trainerMonthlyRate': int.parse(_price.text.trim()),
      });
      _toast('Especialidad y precio guardados.'); // i18n: Fase 11
    } catch (_) {
      _toast('No se pudo guardar. Probá de nuevo.'); // i18n: Fase 11
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _onSpecialtyChanged(Set<String> newSelected) {
    setState(() {
      if (newSelected.isEmpty) {
        _specialty = null;
        return;
      }
      final label = newSelected.first;
      _specialty = TrainerSpecialty.values
          .firstWhere((s) => SpecialtyLabels.of(s) == label);
    });
  }

  String _modalidadResumen(UserProfile profile) {
    final locations = profile.trainerLocations.length;
    final ubicacionesLabel = locations == 1
        ? '1 ubicación'
        : '$locations ubicaciones'; // i18n: Fase 11
    final parts = <String>[
      if (profile.trainerOffersOnline) 'Online', // i18n: Fase 11
      ubicacionesLabel,
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final profile = widget.profile;

    OutlineInputBorder border(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: c),
        );

    final specialtyOptions =
        TrainerSpecialty.values.map(SpecialtyLabels.of).toList();
    final selected =
        _specialty != null ? {SpecialtyLabels.of(_specialty!)} : <String>{};

    return TreinoFadeSlideIn(
      delay: AppMotion.stagger(1),
      child: Container(
        key: const Key('especialidad_precio_card'),
        padding: const EdgeInsets.all(AppSpacing.s18),
        decoration: BoxDecoration(
          color: palette.bgCard,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ESPECIALIDAD', // i18n: Fase 11
              style: TextStyle(
                fontFamily: AppFonts.barlowCondensed,
                fontWeight: AppFonts.w700,
                fontSize: 14,
                letterSpacing: AppFonts.headingTracking,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.s14),
            TreinoFilterChips(
              options: specialtyOptions,
              selected: selected,
              onChanged: _onSpecialtyChanged,
            ),
            const SizedBox(height: AppSpacing.s18),
            Text(
              'PRECIO MENSUAL (ARS)', // i18n: Fase 11
              style: TextStyle(
                fontFamily: AppFonts.barlow,
                fontWeight: AppFonts.w600,
                fontSize: 11,
                letterSpacing: 0.5,
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.hairline),
            TextField(
              key: const Key('especialidad_precio_card_price_field'),
              controller: _price,
              enabled: !_saving,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: palette.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: palette.bg,
                prefixText: '\$ ',
                prefixStyle: TextStyle(color: palette.textMuted),
                hintText: '28000',
                hintStyle: TextStyle(color: palette.textMuted),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s14,
                  vertical: AppSpacing.s14,
                ),
                border: border(palette.border),
                enabledBorder: border(palette.border),
                focusedBorder: border(palette.accent),
                disabledBorder: border(palette.border),
              ),
            ),
            const SizedBox(height: AppSpacing.s12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                key: const Key('especialidad_precio_card_save_button'),
                onPressed: _canSave ? _save : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.bg,
                  disabledBackgroundColor: palette.bgCard,
                  disabledForegroundColor: palette.textMuted,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s18,
                    vertical: AppSpacing.s12,
                  ),
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
                    : const Text('GUARDAR'), // i18n: Fase 11
              ),
            ),
            const SizedBox(height: AppSpacing.s18),
            Container(
              key: const Key('especialidad_precio_card_modalidad'),
              padding: const EdgeInsets.all(AppSpacing.s12),
              decoration: BoxDecoration(
                color: palette.bg,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: palette.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MODALIDAD', // i18n: Fase 11
                    style: TextStyle(
                      fontFamily: AppFonts.barlow,
                      fontWeight: AppFonts.w600,
                      fontSize: 11,
                      letterSpacing: 0.5,
                      color: palette.textMuted,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.hairline),
                  Text(
                    _modalidadResumen(profile),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.hairline),
                  Text(
                    'Editá tu modalidad y ubicaciones desde la app '
                    'móvil.', // i18n: Fase 11
                    style: TextStyle(color: palette.textMuted, fontSize: 12),
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
