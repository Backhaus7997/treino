import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/utils/geohash.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../coach/domain/trainer_location.dart';
import '../../coach/domain/trainer_specialty.dart';
import '../../gyms/application/gym_providers.dart';
import '../../gyms/domain/gym.dart';
import '../application/user_providers.dart';
import '../domain/user_profile.dart';

// ADR-TPO-005: view-only enum co-located with its single screen consumer.
enum ProfileEditTrainerMode { edit, onboarding }

/// Pantalla de edición del perfil público del PF.
///
/// Modelo multi-location (Fase 6 Etapa 0 PR#3): el PF puede tener una
/// lista de ubicaciones (mezcla de gyms del catálogo + lugares propios) y
/// un toggle independiente "También doy clases online". Combinaciones
/// válidas:
///   - 1+ locations + offersOnline:false → solo presencial
///   - 1+ locations + offersOnline:true  → híbrido
///   - 0 locations + offersOnline:true   → solo virtual
///   - 0 locations + offersOnline:false  → INVÁLIDO, el form lo bloquea
///
/// El form persiste vía `UserRepository.update(uid, partial)`, que ya tiene
/// el dual-write atomic a `users/{uid}` + `trainerPublicProfiles/{uid}`. La
/// validación final del estado vive en el repo (lanza ArgumentError si el
/// caso inválido llega), pero acá también la bloqueamos client-side para
/// dar feedback inmediato.
///
/// Avatar + displayName se editan desde "Datos personales" — out of scope.
class ProfileEditTrainerScreen extends ConsumerStatefulWidget {
  const ProfileEditTrainerScreen({
    super.key,
    this.mode = ProfileEditTrainerMode.edit,
  });

  // ADR-TPO-005: defaults to edit — any caller that forgets the mode
  // degrades safely to current edit-mode behavior.
  final ProfileEditTrainerMode mode;

  @override
  ConsumerState<ProfileEditTrainerScreen> createState() =>
      _ProfileEditTrainerScreenState();
}

class _ProfileEditTrainerScreenState
    extends ConsumerState<ProfileEditTrainerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bioController = TextEditingController();
  final _priceController = TextEditingController();
  final _aliasController = TextEditingController();
  TrainerSpecialty? _specialty;
  final List<TrainerLocation> _locations = [];
  bool _offersOnline = false;
  bool _initialized = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _bioController.dispose();
    _priceController.dispose();
    _aliasController.dispose();
    super.dispose();
  }

  void _initFromProfile(UserProfile profile) {
    if (_initialized) return;
    _bioController.text = profile.trainerBio ?? '';
    _priceController.text = profile.trainerMonthlyRate?.toString() ?? '';
    _aliasController.text = profile.paymentAlias ?? '';
    _specialty = trainerSpecialtyFromString(profile.trainerSpecialty);
    _locations
      ..clear()
      ..addAll(profile.trainerLocations);
    _offersOnline = profile.trainerOffersOnline;
    _initialized = true;
  }

  List<TrainerLocation> get _gymLocations =>
      _locations.where((l) => l.type == TrainerLocationType.gym).toList();

  List<TrainerLocation> get _customLocations =>
      _locations.where((l) => l.type == TrainerLocationType.custom).toList();

  Future<void> _addGym() async {
    final gyms = await ref.read(gymsProvider.future);
    if (!mounted) return;
    // Filtramos los gyms ya seleccionados — evita duplicados.
    final selectedIds = _gymLocations.map((l) => l.gymId).toSet();
    final available = gyms.where((g) => !selectedIds.contains(g.id)).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final picked = await showModalBottomSheet<Gym>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.of(context).bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _GymPickerSheet(gyms: available),
    );
    if (picked == null) return;
    setState(() {
      _locations.add(TrainerLocation(
        id: 'gym-${picked.id}',
        type: TrainerLocationType.gym,
        gymId: picked.id,
        lat: picked.lat,
        lng: picked.lng,
        geohash: picked.geohash,
      ));
      _error = null;
    });
  }

  Future<void> _addCustom() async {
    final palette = AppPalette.of(context);
    final result = await showModalBottomSheet<_CustomLocationDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: palette.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _CustomLocationSheet(),
    );
    if (result == null) return;
    setState(() {
      _locations.add(TrainerLocation(
        id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
        type: TrainerLocationType.custom,
        customLabel: result.label,
        lat: result.lat,
        lng: result.lng,
        geohash: geohash5(result.lat, result.lng),
      ));
      _error = null;
    });
  }

  void _removeLocation(TrainerLocation loc) {
    setState(() {
      _locations.removeWhere((l) => l.id == loc.id);
      _error = null;
    });
  }

  Future<void> _save(String uid) async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    if (_specialty == null) {
      setState(() => _error = 'Elegí una especialidad.');
      return;
    }
    if (_locations.isEmpty && !_offersOnline) {
      setState(() =>
          _error = 'Agregá al menos una ubicación o activá clases virtuales.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final partial = <String, Object?>{
      'trainerBio': _bioController.text.trim(),
      'trainerSpecialty': TrainerSpecialtyX.toWire(_specialty!),
      'trainerMonthlyRate': int.parse(_priceController.text.trim()),
      'paymentAlias': _aliasController.text.trim().isEmpty
          ? null
          : _aliasController.text.trim(),
      'trainerLocations': _locations.map((l) => l.toJson()).toList(),
      'trainerGeohashes': _locations.map((l) => l.geohash).toSet().toList(),
      'trainerOffersOnline': _offersOnline,
      // Limpiar legacy singular — este form trabaja con el modelo array-based.
      // Si no los nulleamos, quedan zombi en Firestore (de la migration original)
      // y el mapa los renderea como pin físico aunque el PF haya borrado
      // todas sus locations. Cleanup PR final removerá los campos del modelo.
      'trainerLatitude': null,
      'trainerLongitude': null,
      'trainerGeohash': null,
    };

    try {
      await ref.read(userRepositoryProvider).update(uid, partial);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil actualizado.')),
      );
      // ADR-TPO-006: post-save navigation branches on mode.
      if (widget.mode == ProfileEditTrainerMode.onboarding) {
        context.go('/home');
      } else {
        context.pop();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos guardar. Probá de nuevo.';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final profileAsync = ref.watch(userProfileProvider);
    final profile = profileAsync.valueOrNull;

    if (profile == null) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: palette.accent)),
      );
    }
    _initFromProfile(profile);

    // ADR-TPO-006: AppBar title derived from mode.
    final title =
        widget.mode == ProfileEditTrainerMode.onboarding
            ? 'Completá tu perfil profesional' // i18n: Fase 6 Etapa 1
            : 'Editá tu perfil profesional'; // i18n: Fase 6 Etapa 1

    // ADR-TPO-006: in onboarding mode, block back navigation at both levels.
    final body = SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionLabel(palette: palette, text: 'BIO'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _bioController,
              maxLines: 4,
              maxLength: 280,
              style: TextStyle(color: palette.textPrimary),
              decoration: _inputDecoration(
                palette,
                hint: 'Contales a tus futuros alumnos cómo entrenás.',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Escribí una bio.';
                }
                if (v.trim().length < 20) {
                  return 'Al menos 20 caracteres.';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            _SectionLabel(palette: palette, text: 'ESPECIALIDAD'),
            const SizedBox(height: 8),
            _SpecialtyDropdown(
              palette: palette,
              value: _specialty,
              onChanged: (s) => setState(() {
                _specialty = s;
                _error = null;
              }),
            ),
            const SizedBox(height: 14),
            _SectionLabel(palette: palette, text: 'PRECIO MENSUAL (ARS)'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _priceController,
              keyboardType: TextInputType.number,
              style: TextStyle(color: palette.textPrimary),
              decoration: _inputDecoration(palette, hint: 'Ej: 7000'),
              validator: (v) {
                final n = int.tryParse(v?.trim() ?? '');
                if (n == null) return 'Ingresá un número entero.';
                if (n < 500) return 'Mínimo \$500.';
                if (n > 999999) return 'Máximo \$999999.';
                return null;
              },
            ),
            const SizedBox(height: 14),
            _SectionLabel(palette: palette, text: 'ALIAS / DATOS DE COBRO'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _aliasController,
              maxLength: 120,
              style: TextStyle(color: palette.textPrimary),
              decoration: _inputDecoration(
                palette,
                hint: 'Alias, CBU, CVU o usuario de MercadoPago (opcional).',
              ),
            ),
            const SizedBox(height: 18),
            _GymsSection(
              palette: palette,
              locations: _gymLocations,
              onAdd: _addGym,
              onRemove: _removeLocation,
            ),
            const SizedBox(height: 18),
            _CustomLocationsSection(
              palette: palette,
              locations: _customLocations,
              onAdd: _addCustom,
              onRemove: _removeLocation,
            ),
            const SizedBox(height: 18),
            _OnlineToggle(
              palette: palette,
              value: _offersOnline,
              onChanged: (v) => setState(() {
                _offersOnline = v;
                _error = null;
              }),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.danger, fontSize: 13),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              key: const Key('profile_edit_trainer_save_button'),
              onPressed: _saving ? null : () => _save(profile.uid),
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: palette.bg,
                minimumSize: const Size.fromHeight(48),
                shape: const StadiumBorder(),
                disabledBackgroundColor: palette.accent.withValues(alpha: 0.3),
              ),
              child: _saving
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: palette.bg,
                      ),
                    )
                  : Text(
                      'GUARDAR',
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        letterSpacing: 1.4,
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Text(
              'El avatar y el nombre se editan desde "Datos personales".',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );

    // ADR-TPO-006: onboarding mode wraps body in PopScope to block OS back
    // gesture (iOS swipe-back, Android back button).
    final wrappedBody =
        widget.mode == ProfileEditTrainerMode.onboarding
            ? PopScope(
                canPop: false,
                onPopInvokedWithResult: (_, __) {},
                child: body,
              )
            : body;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        // ADR-TPO-006: in onboarding mode, hide the back arrow entirely.
        automaticallyImplyLeading:
            widget.mode != ProfileEditTrainerMode.onboarding,
      ),
      body: wrappedBody,
    );
  }

  InputDecoration _inputDecoration(AppPalette palette, {required String hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: palette.textMuted),
      filled: true,
      fillColor: palette.bgCard,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: palette.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: palette.danger),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.palette, required this.text});
  final AppPalette palette;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.barlowCondensed(
        color: palette.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    );
  }
}

class _SpecialtyDropdown extends StatelessWidget {
  const _SpecialtyDropdown({
    required this.palette,
    required this.value,
    required this.onChanged,
  });
  final AppPalette palette;
  final TrainerSpecialty? value;
  final ValueChanged<TrainerSpecialty?> onChanged;

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<TrainerSpecialty>(
          value: value,
          isExpanded: true,
          hint: Text(
            'Elegí una especialidad',
            style: TextStyle(color: palette.textMuted),
          ),
          dropdownColor: palette.bgCard,
          style: TextStyle(color: palette.textPrimary),
          icon: Icon(TreinoIcon.chevronDown, color: palette.textMuted),
          items: TrainerSpecialty.values
              .map((s) => DropdownMenuItem(
                    value: s,
                    child: Text(_capitalize(TrainerSpecialtyX.toWire(s))),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ── Gyms section ─────────────────────────────────────────────────────────────

class _GymsSection extends ConsumerWidget {
  const _GymsSection({
    required this.palette,
    required this.locations,
    required this.onAdd,
    required this.onRemove,
  });
  final AppPalette palette;
  final List<TrainerLocation> locations;
  final VoidCallback onAdd;
  final void Function(TrainerLocation) onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gymsAsync = ref.watch(gymsProvider);
    final gymsById = <String, Gym>{
      for (final g in gymsAsync.valueOrNull ?? const <Gym>[]) g.id: g,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(palette: palette, text: 'GIMNASIOS DONDE TRABAJÁS'),
        const SizedBox(height: 8),
        if (locations.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: palette.bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.border),
            ),
            child: Text(
              'Todavía no agregaste ningún gimnasio.',
              style: TextStyle(color: palette.textMuted, fontSize: 13),
            ),
          )
        else
          Column(
            children: locations
                .map((loc) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _LocationCard(
                        palette: palette,
                        icon: TreinoIcon.gym,
                        title: gymsById[loc.gymId]?.name ?? 'Gimnasio',
                        subtitle: gymsById[loc.gymId]?.address,
                        onRemove: () => onRemove(loc),
                      ),
                    ))
                .toList(),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: Icon(TreinoIcon.plus, size: 18, color: palette.accent),
          label: const Text('Agregar gimnasio'),
          style: OutlinedButton.styleFrom(
            foregroundColor: palette.accent,
            side: BorderSide(color: palette.accent),
            minimumSize: const Size.fromHeight(44),
            shape: const StadiumBorder(),
          ),
        ),
      ],
    );
  }
}

// ── Custom locations section ─────────────────────────────────────────────────

class _CustomLocationsSection extends StatelessWidget {
  const _CustomLocationsSection({
    required this.palette,
    required this.locations,
    required this.onAdd,
    required this.onRemove,
  });
  final AppPalette palette;
  final List<TrainerLocation> locations;
  final VoidCallback onAdd;
  final void Function(TrainerLocation) onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(palette: palette, text: 'LUGARES PROPIOS'),
        const SizedBox(height: 4),
        Text(
          'Tu casa, un parque, un studio. Lugares fuera del catálogo de gimnasios.',
          style: TextStyle(color: palette.textMuted, fontSize: 12),
        ),
        const SizedBox(height: 8),
        if (locations.isNotEmpty)
          Column(
            children: locations
                .map((loc) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _LocationCard(
                        palette: palette,
                        icon: TreinoIcon.mapPin,
                        title: loc.customLabel ?? 'Lugar propio',
                        subtitle:
                            '${loc.lat.toStringAsFixed(4)}, ${loc.lng.toStringAsFixed(4)}',
                        onRemove: () => onRemove(loc),
                      ),
                    ))
                .toList(),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: Icon(TreinoIcon.plus, size: 18, color: palette.accent),
          label: const Text('Agregar lugar propio'),
          style: OutlinedButton.styleFrom(
            foregroundColor: palette.accent,
            side: BorderSide(color: palette.accent),
            minimumSize: const Size.fromHeight(44),
            shape: const StadiumBorder(),
          ),
        ),
      ],
    );
  }
}

// ── Location card (gym or custom) ────────────────────────────────────────────

class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onRemove,
  });
  final AppPalette palette;
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: palette.accent, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: Icon(TreinoIcon.trash, size: 18, color: palette.textMuted),
            tooltip: 'Quitar',
          ),
        ],
      ),
    );
  }
}

// ── Online toggle ────────────────────────────────────────────────────────────

class _OnlineToggle extends StatelessWidget {
  const _OnlineToggle({
    required this.palette,
    required this.value,
    required this.onChanged,
  });
  final AppPalette palette;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          'Doy clases virtuales',
          style: TextStyle(
            color: palette.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          'Atletas de cualquier zona pueden contactarte.',
          style: TextStyle(color: palette.textMuted, fontSize: 12),
        ),
        value: value,
        onChanged: onChanged,
        activeThumbColor: palette.accent,
      ),
    );
  }
}

// ── Gym picker sheet ─────────────────────────────────────────────────────────

class _GymPickerSheet extends StatefulWidget {
  const _GymPickerSheet({required this.gyms});
  final List<Gym> gyms;

  @override
  State<_GymPickerSheet> createState() => _GymPickerSheetState();
}

class _GymPickerSheetState extends State<_GymPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Gym> get _filtered {
    final q = _query.toLowerCase().trim();
    if (q.isEmpty) return widget.gyms;
    return widget.gyms.where((g) {
      if (g.name.toLowerCase().contains(q)) return true;
      if ((g.address ?? '').toLowerCase().contains(q)) return true;
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      builder: (_, scrollController) => Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 18,
          bottom: MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: palette.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              'Elegí un gimnasio',
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchController,
              autofocus: true,
              style: TextStyle(color: palette.textPrimary),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o dirección…',
                hintStyle: TextStyle(color: palette.textMuted),
                prefixIcon: Icon(TreinoIcon.search, color: palette.textMuted),
                filled: true,
                fillColor: palette.bg,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: palette.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: palette.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: palette.accent, width: 1.5),
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _filtered.isEmpty
                  ? Center(
                      child: Text(
                        widget.gyms.isEmpty
                            ? 'No quedan gimnasios disponibles para sumar.'
                            : 'Sin resultados.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: palette.textMuted),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: _filtered.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: palette.border,
                      ),
                      itemBuilder: (_, i) {
                        final g = _filtered[i];
                        return ListTile(
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 4),
                          leading: Icon(TreinoIcon.gym,
                              color: palette.accent, size: 22),
                          title: Text(
                            g.name,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: g.address == null
                              ? null
                              : Text(
                                  g.address!,
                                  style: TextStyle(
                                    color: palette.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                          onTap: () => Navigator.of(context).pop(g),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Custom location sheet ────────────────────────────────────────────────────

class _CustomLocationDraft {
  _CustomLocationDraft({
    required this.label,
    required this.lat,
    required this.lng,
  });
  final String label;
  final double lat;
  final double lng;
}

class _CustomLocationSheet extends StatefulWidget {
  const _CustomLocationSheet();

  @override
  State<_CustomLocationSheet> createState() => _CustomLocationSheetState();
}

class _CustomLocationSheetState extends State<_CustomLocationSheet> {
  final _labelController = TextEditingController();
  double? _lat;
  double? _lng;
  bool _detecting = false;
  String? _error;

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _detect() async {
    if (_detecting) return;
    setState(() {
      _detecting = true;
      _error = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() {
          _error = 'Necesitamos permiso de ubicación.';
          _detecting = false;
        });
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        _lat = pos.latitude;
        _lng = pos.longitude;
        _detecting = false;
      });
    } catch (_) {
      setState(() {
        _error = 'No pudimos detectar tu ubicación.';
        _detecting = false;
      });
    }
  }

  void _submit() {
    final label = _labelController.text.trim();
    if (label.isEmpty) {
      setState(() => _error = 'Poné un nombre al lugar.');
      return;
    }
    if (_lat == null || _lng == null) {
      setState(() => _error = 'Detectá la ubicación antes de guardar.');
      return;
    }
    Navigator.of(context).pop(_CustomLocationDraft(
      label: label,
      lat: _lat!,
      lng: _lng!,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final hasLocation = _lat != null && _lng != null;
    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Agregar lugar propio',
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _labelController,
            autofocus: true,
            style: TextStyle(color: palette.textPrimary),
            decoration: InputDecoration(
              hintText: 'Ej: Mi estudio en casa, Parque Sarmiento…',
              hintStyle: TextStyle(color: palette.textMuted),
              filled: true,
              fillColor: palette.bg,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: palette.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: palette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: palette.accent, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: palette.bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                Icon(TreinoIcon.mapPin, color: palette.accent, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    hasLocation
                        ? '${_lat!.toStringAsFixed(4)}, ${_lng!.toStringAsFixed(4)}'
                        : 'Sin ubicación detectada',
                    style: TextStyle(
                      color:
                          hasLocation ? palette.textPrimary : palette.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _detecting ? null : _detect,
                  child: _detecting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          hasLocation ? 'Recalcular' : 'Detectar',
                          style: TextStyle(color: palette.accent),
                        ),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.danger, fontSize: 13),
            ),
          ],
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.accent,
              foregroundColor: palette.bg,
              minimumSize: const Size.fromHeight(48),
              shape: const StadiumBorder(),
            ),
            child: const Text('GUARDAR LUGAR'),
          ),
        ],
      ),
    );
  }
}
