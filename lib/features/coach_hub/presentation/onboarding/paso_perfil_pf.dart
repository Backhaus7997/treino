import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/utils/geohash.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach/domain/trainer_location.dart';
import 'package:treino/features/coach/domain/trainer_specialty.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_specialty_chips.dart'
    show SpecialtyLabels;
import 'package:treino/features/coach_hub/application/hub_onboarding_controller.dart';
import 'package:treino/features/coach_hub/data/lugar_search_service.dart';
import 'package:treino/features/coach_hub/domain/perfil_pf_validators.dart';
import 'package:treino/features/coach_hub/presentation/onboarding/editor_ubicacion_pf.dart';
import 'package:treino/features/coach_hub/presentation/onboarding/onboarding_widgets.dart';
import 'package:treino/features/coach_hub/presentation/widgets/button/treino_button.dart';
import 'package:treino/features/coach_hub/presentation/widgets/dialog/treino_dialog.dart';
import 'package:treino/features/coach_hub/presentation/widgets/filter_chips/filter_chips.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Paso `pf`: bio, especialidad, tarifa mensual y modalidad (online y/o un
/// lugar presencial elegido por dirección). Todo va en UNA escritura
/// ([HubOnboardingController.guardarPerfilPf]).
///
/// Precarga lo que el perfil ya tenga: un PF al que solo le falta un dato no
/// reescribe los demás de cero.
///
/// «Finalizar» solo se habilita con el formulario completo: bio y tarifa en
/// rango, una especialidad y al menos una modalidad. Una ubicación solo existe
/// si el PF ELIGIÓ un resultado de Places (con coordenadas); lo que escribió en
/// el buscador no cuenta.
class PasoPerfilPf extends ConsumerStatefulWidget {
  const PasoPerfilPf({super.key});

  @override
  ConsumerState<PasoPerfilPf> createState() => _PasoPerfilPfState();
}

class _PasoPerfilPfState extends ConsumerState<PasoPerfilPf> {
  late final TextEditingController _bio;
  late final TextEditingController _tarifa;
  TrainerSpecialty? _specialty;
  late bool _online;
  late final List<TrainerLocation> _locations;
  bool _pidiendoConsentimiento = false;

  @override
  void initState() {
    super.initState();
    final perfil = ref.read(userProfileProvider).valueOrNull;
    _bio = TextEditingController(text: perfil?.trainerBio ?? '');
    _tarifa = TextEditingController(
      text: perfil?.trainerMonthlyRate?.toString() ?? '',
    );
    _specialty = trainerSpecialtyFromString(perfil?.trainerSpecialty);
    _online = perfil?.trainerOffersOnline ?? false;
    _locations = [...?perfil?.trainerLocations];
  }

  @override
  void dispose() {
    _bio.dispose();
    _tarifa.dispose();
    super.dispose();
  }

  bool get _tieneModalidad => _online || _locations.isNotEmpty;

  bool get _completo =>
      validarBio(_bio.text) == null &&
      validarPrecio(_tarifa.text) == null &&
      _specialty != null &&
      _tieneModalidad;

  /// Mismo armado que `profile_edit_trainer_screen.dart`: ubicación propia
  /// (`custom`), coordenadas EXACTAS de Places y `geohash5` derivado de ellas.
  void _agregarLugar(LugarCandidato lugar) {
    final repetido = _locations.any(
      (l) => l.lat == lugar.lat && l.lng == lugar.lng,
    );
    if (repetido) return;
    setState(() {
      _locations.add(
        TrainerLocation(
          id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
          type: TrainerLocationType.custom,
          customLabel: lugar.label,
          lat: lugar.lat,
          lng: lugar.lng,
          geohash: geohash5(lugar.lat, lugar.lng),
        ),
      );
    });
  }

  /// Confirmación previa a publicar la ubicación. `null` (cerró el diálogo
  /// sin elegir) cuenta como cancelar.
  Future<bool> _confirmarConsentimiento() async {
    final l10n = AppL10n.of(context);
    final palette = AppPalette.of(context);
    final aceptado = await showTreinoDialog<bool>(
      context,
      builder: (dialogContext) => TreinoDialog(
        key: const Key('onboarding-pf-consent'),
        title: l10n.profileEditTrainerConsentConfirmTitle,
        body: Text(
          l10n.profileEditTrainerConsentConfirmBody,
          style: GoogleFonts.barlow(
            color: palette.textMuted,
            fontSize: AppTextSize.body,
            height: 1.4,
          ),
        ),
        primaryLabel: l10n.profileEditTrainerConsentConfirmAccept,
        onPrimaryTap: () => Navigator.of(dialogContext).pop(true),
        secondaryLabel: l10n.profileEditTrainerConsentConfirmCancel,
        onSecondaryTap: () => Navigator.of(dialogContext).pop(false),
      ),
    );
    return aceptado ?? false;
  }

  Future<void> _finalizar() async {
    if (!_completo || _pidiendoConsentimiento) return;
    final perfil = ref.read(userProfileProvider).valueOrNull;

    // D11: hay ubicaciones y nunca se consintió ⇒ se pregunta ANTES de
    // escribir. Cancelar no escribe nada y deja el formulario como está; el
    // consentimiento viaja en el MISMO batch que el perfil.
    var otorgaConsentimiento = false;
    if (_locations.isNotEmpty && perfil?.trainerLocationConsentAt == null) {
      _pidiendoConsentimiento = true;
      final acepto = await _confirmarConsentimiento();
      _pidiendoConsentimiento = false;
      if (!mounted || !acepto) return;
      otorgaConsentimiento = true;
    }

    await ref.read(hubOnboardingControllerProvider.notifier).guardarPerfilPf(
          PerfilPfDraft(
            bio: _bio.text,
            specialty: _specialty!,
            monthlyRate: int.parse(_tarifa.text.trim()),
            offersOnline: _online,
            locations: List.unmodifiable(_locations),
          ),
          otorgaConsentimientoUbicacion: otorgaConsentimiento,
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final palette = AppPalette.of(context);
    final escritura = ref.watch(hubOnboardingControllerProvider);
    final opciones = [
      for (final s in TrainerSpecialty.values) SpecialtyLabels.of(s),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OnboardingEncabezado(
          titulo: l10n.coachHubOnboardingPfTitle,
          cuerpo: l10n.coachHubOnboardingPfBody,
        ),
        const SizedBox(height: AppSpacing.s20),
        OnboardingEtiqueta(l10n.coachHubOnboardingPfBioLabel),
        const SizedBox(height: AppSpacing.s8),
        TextFormField(
          key: const Key('onboarding-pf-bio'),
          controller: _bio,
          minLines: 3,
          maxLines: 6,
          keyboardType: TextInputType.multiline,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (v) => validarBio(v ?? ''),
          onChanged: (_) => setState(() {}),
          style: GoogleFonts.barlow(
            color: palette.textPrimary,
            fontSize: AppTextSize.bodyLarge,
          ),
        ),
        const SizedBox(height: AppSpacing.s14),
        OnboardingEtiqueta(l10n.coachHubOnboardingPfSpecialtyLabel),
        const SizedBox(height: AppSpacing.s8),
        TreinoFilterChips(
          options: opciones,
          selected: _specialty == null ? {} : {SpecialtyLabels.of(_specialty!)},
          onChanged: (sel) => setState(() {
            _specialty = sel.isEmpty
                ? null
                : TrainerSpecialty.values
                    .firstWhere((s) => SpecialtyLabels.of(s) == sel.first);
          }),
        ),
        const SizedBox(height: AppSpacing.s14),
        _CampoTarifa(
          controller: _tarifa,
          etiqueta: l10n.coachHubOnboardingPfRateLabel,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.s14),
        OnboardingEtiqueta(l10n.coachHubOnboardingPfModalityLabel),
        const SizedBox(height: AppSpacing.s8),
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.coachHubOnboardingPfOnlineSwitch,
                style: GoogleFonts.barlow(
                  color: palette.textPrimary,
                  fontSize: AppTextSize.body,
                ),
              ),
            ),
            Switch(
              key: const Key('onboarding-pf-online'),
              value: _online,
              onChanged: (v) => setState(() => _online = v),
              activeThumbColor: palette.accent,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.s12),
        OnboardingEtiqueta(l10n.coachHubOnboardingPfLocationsLabel),
        const SizedBox(height: AppSpacing.s8),
        for (var i = 0; i < _locations.length; i++)
          _FilaLugar(
            indice: i,
            lugar: _locations[i],
            tooltip: l10n.coachHubOnboardingPfLocationRemove,
            onQuitar: () => setState(() => _locations.removeAt(i)),
          ),
        if (_locations.isNotEmpty) const SizedBox(height: AppSpacing.s8),
        EditorUbicacionPf(onElegir: _agregarLugar),
        if (!_tieneModalidad) ...[
          const SizedBox(height: AppSpacing.s12),
          Text(
            l10n.coachHubOnboardingPfModalityRequired,
            style: GoogleFonts.barlow(
              color: palette.textMuted,
              fontSize: AppTextSize.bodyDense,
            ),
          ),
        ],
        if (escritura.hasError) ...[
          const SizedBox(height: AppSpacing.s12),
          OnboardingError(mensajeDeErrorDeEscritura(l10n, escritura.error!)),
        ],
        const SizedBox(height: AppSpacing.s20),
        TreinoButton(
          key: const Key('onboarding-pf-finalizar'),
          label: l10n.coachHubOnboardingPfFinish,
          expand: true,
          loading: escritura.isLoading,
          onPressed: _completo && !escritura.isLoading ? _finalizar : null,
        ),
      ],
    );
  }
}

class _CampoTarifa extends StatelessWidget {
  const _CampoTarifa({
    required this.controller,
    required this.etiqueta,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String etiqueta;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OnboardingEtiqueta(etiqueta),
        const SizedBox(height: AppSpacing.s8),
        TextFormField(
          key: const Key('onboarding-pf-tarifa'),
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autovalidateMode: AutovalidateMode.onUserInteraction,
          validator: (v) => validarPrecio(v ?? ''),
          onChanged: (_) => onChanged(),
          style: GoogleFonts.barlow(
            color: palette.textPrimary,
            fontSize: AppTextSize.bodyLarge,
          ),
          decoration: InputDecoration(
            prefixText: '\$ ',
            prefixStyle: GoogleFonts.barlow(
              color: palette.textMuted,
              fontSize: AppTextSize.bodyLarge,
            ),
          ),
        ),
      ],
    );
  }
}

class _FilaLugar extends StatelessWidget {
  const _FilaLugar({
    required this.indice,
    required this.lugar,
    required this.tooltip,
    required this.onQuitar,
  });

  final int indice;
  final TrainerLocation lugar;
  final String tooltip;
  final VoidCallback onQuitar;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s8,
        ),
        decoration: BoxDecoration(
          color: palette.bgCard,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Row(
          children: [
            Icon(TreinoIcon.mapPin, color: palette.textMuted),
            const SizedBox(width: AppSpacing.s12),
            Expanded(
              child: Text(
                lugar.customLabel ?? '',
                style: GoogleFonts.barlow(
                  color: palette.textPrimary,
                  fontSize: AppTextSize.body,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TreinoIconButton(
              key: Key('onboarding-pf-lugar-quitar-$indice'),
              icon: TreinoIcon.close,
              tooltip: tooltip,
              onPressed: onQuitar,
            ),
          ],
        ),
      ),
    );
  }
}
