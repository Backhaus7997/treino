import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../auth/application/auth_providers.dart';
import '../../profile_setup/application/profile_setup_providers.dart';
import '../application/user_providers.dart';
import '../domain/experience_level.dart';
import '../domain/gender.dart';
import '../domain/user_profile.dart';

// ---------------------------------------------------------------------------
// Validators (inline per design §4.2 — NOT shared from auth)
// Moved to instance methods on _ProfileEditPersonalScreenState so they can
// access AppL10n.of(context).
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Save state
// ---------------------------------------------------------------------------

enum _SaveState { idle, uploading, saving, error }

// ---------------------------------------------------------------------------
// Main screen widget
// ---------------------------------------------------------------------------

/// Real implementation of the Datos personales edit screen.
///
/// REQ-PSR-015: form pre-populated from [userProfileProvider].
/// REQ-PSR-016: save calls [UserRepository.update] with partial + pops.
/// REQ-PSR-017: inline validators — displayName, bodyWeightKg, heightCm.
/// REQ-PSR-018: avatar reuses [avatarUploadServiceProvider]. // i18n: Fase 6 Etapa 3
class ProfileEditPersonalScreen extends ConsumerStatefulWidget {
  const ProfileEditPersonalScreen({super.key});

  @override
  ConsumerState<ProfileEditPersonalScreen> createState() =>
      _ProfileEditPersonalScreenState();
}

class _ProfileEditPersonalScreenState
    extends ConsumerState<ProfileEditPersonalScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _weightCtrl;
  late final TextEditingController _heightCtrl;

  UserProfile? _initialProfile;
  Gender? _selectedGender;
  ExperienceLevel? _selectedExperience;

  // Avatar — either the existing URL or a newly-picked local path
  String? _existingAvatarUrl;
  String? _pendingLocalPath; // non-null → new image chosen, not yet uploaded

  final _saveState = ValueNotifier(_SaveState.idle);

  /// Tracks whether controllers have been seeded from the first
  /// resolved userProfileProvider value. Needed because
  /// StreamProvider values are not guaranteed to be synchronously
  /// available in initState (especially in tests with overrides).
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _weightCtrl = TextEditingController();
    _heightCtrl = TextEditingController();
    // Attempt eager seeding — works in production where the stream is warm.
    _seedFromProfile(ref.read(userProfileProvider).valueOrNull);
  }

  /// Seeds form controllers and selection state from [profile].
  /// Safe to call multiple times; no-op after first successful seed.
  void _seedFromProfile(UserProfile? profile) {
    if (_seeded || profile == null) return;
    _seeded = true;
    _initialProfile = profile;
    _existingAvatarUrl = profile.avatarUrl;
    _nameCtrl.text = profile.displayName ?? '';
    _weightCtrl.text =
        profile.bodyWeightKg != null ? profile.bodyWeightKg!.toString() : '';
    _heightCtrl.text =
        profile.heightCm != null ? profile.heightCm!.toString() : '';
    _selectedGender = profile.gender;
    _selectedExperience = profile.experienceLevel;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    _saveState.dispose();
    super.dispose();
  }

  // ── Validators (inline per design §4.2 — NOT shared from auth) ──────────

  String? _validateDisplayName(String? value) {
    final l10n = AppL10n.of(context);
    if (value == null || value.trim().isEmpty) {
      return l10n.profileEditPersonalNameRequired;
    }
    if (value.trim().length > 50) {
      return l10n.profileEditPersonalNameMaxLength;
    }
    return null;
  }

  String? _validateBodyWeightKg(String? value) {
    if (value == null || value.trim().isEmpty) return null; // nullable field
    final l10n = AppL10n.of(context);
    final n = double.tryParse(value.replaceAll(',', '.'));
    if (n == null) return l10n.profileEditPersonalWeightInvalidNumber;
    if (n < 30 || n > 300) {
      return l10n.profileEditPersonalWeightOutOfRange;
    }
    return null;
  }

  String? _validateHeightCm(String? value) {
    if (value == null || value.trim().isEmpty) return null; // nullable field
    final l10n = AppL10n.of(context);
    final n = int.tryParse(value.trim());
    if (n == null) return l10n.profileEditPersonalWeightInvalidNumber;
    if (n < 120 || n > 230) {
      return l10n.profileEditPersonalHeightOutOfRange;
    }
    return null;
  }

  /// True while an avatar upload or Firestore update is in flight.
  /// Used to gate the save handler, the header back-tap and the avatar
  /// picker so an in-flight save cannot be interrupted (orphaned uploads).
  bool get _isBusy =>
      _saveState.value == _SaveState.uploading ||
      _saveState.value == _SaveState.saving;

  // ── Avatar pick ──────────────────────────────────────────────────────────

  Future<void> _pickAvatar() async {
    if (_isBusy) return;
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (file != null && mounted) {
      setState(() => _pendingLocalPath = file.path);
    }
  }

  // ── Save ─────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (_isBusy) return; // re-entrancy guard — a save is already in flight
    if (!(_formKey.currentState?.validate() ?? false)) return;

    _saveState.value = _SaveState.saving;

    // Prefer uid from seeded initial profile (available synchronously from
    // initState read). Fall back to auth state for robustness.
    final uid = _initialProfile?.uid ??
        ref.read(authStateChangesProvider).valueOrNull?.uid;
    if (uid == null) {
      _saveState.value = _SaveState.error;
      return;
    }

    String? avatarUrl = _existingAvatarUrl;

    // Upload new avatar if one was staged
    if (_pendingLocalPath != null) {
      _saveState.value = _SaveState.uploading;
      try {
        avatarUrl = await ref
            .read(avatarUploadServiceProvider)
            .upload(_pendingLocalPath!);
        // Persist the uploaded URL immediately and clear the staged path so
        // that if the Firestore update below fails, a retry reuses this URL
        // instead of re-uploading (which would orphan a storage object).
        if (mounted) {
          setState(() {
            _existingAvatarUrl = avatarUrl;
            _pendingLocalPath = null;
          });
        } else {
          _existingAvatarUrl = avatarUrl;
          _pendingLocalPath = null;
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'No pudimos subir tu foto. Probá de nuevo.', // i18n: Fase 6 Etapa 3
                style: GoogleFonts.barlow(fontSize: 14),
              ),
            ),
          );
        }
        _saveState.value = _SaveState.idle;
        return;
      }
    }

    _saveState.value = _SaveState.saving;

    // Build partial — only changed fields
    final partial = <String, Object?>{};
    final newName = _nameCtrl.text.trim();
    if (newName != (_initialProfile?.displayName ?? '')) {
      partial['displayName'] = newName;
    }

    final newWeight = double.tryParse(_weightCtrl.text.replaceAll(',', '.'));
    if (newWeight != _initialProfile?.bodyWeightKg) {
      partial['bodyWeightKg'] = newWeight;
    }

    final newHeight = int.tryParse(_heightCtrl.text.trim());
    if (newHeight != _initialProfile?.heightCm) {
      partial['heightCm'] = newHeight;
    }

    if (_selectedGender != _initialProfile?.gender) {
      partial['gender'] = _selectedGender?.toJson();
    }

    if (_selectedExperience != _initialProfile?.experienceLevel) {
      partial['experienceLevel'] = _selectedExperience?.toJson();
    }

    // Compare against the persisted URL (from the initial profile), not
    // _existingAvatarUrl — the latter is updated to the freshly-uploaded URL
    // above, so it would no longer reflect a change after an upload.
    if (avatarUrl != _initialProfile?.avatarUrl) {
      partial['avatarUrl'] = avatarUrl;
    }

    // Always send displayName if it's in the form (ensure non-empty is sent)
    if (!partial.containsKey('displayName')) {
      // include it if the form value differs from stored (case: same string)
      final current = _nameCtrl.text.trim();
      if (current != (_initialProfile?.displayName ?? '')) {
        partial['displayName'] = current;
      }
    }

    try {
      await ref.read(userRepositoryProvider).update(uid, partial);
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'No pudimos guardar los cambios. Probá de nuevo.', // i18n: Fase 6 Etapa 3
              style: GoogleFonts.barlow(fontSize: 14),
            ),
          ),
        );
      }
      _saveState.value = _SaveState.idle;
    }
  }

  // ── Discard ───────────────────────────────────────────────────────────────

  bool get _isDirty {
    if (_nameCtrl.text.trim() != (_initialProfile?.displayName ?? '')) {
      return true;
    }
    if (_pendingLocalPath != null) return true;
    // An avatar already uploaded but not yet persisted (e.g. upload succeeded
    // but the Firestore update failed) still counts as a pending change.
    if (_existingAvatarUrl != _initialProfile?.avatarUrl) return true;
    if (_selectedGender != _initialProfile?.gender) return true;
    if (_selectedExperience != _initialProfile?.experienceLevel) return true;
    final w = double.tryParse(_weightCtrl.text.replaceAll(',', '.'));
    if (w != _initialProfile?.bodyWeightKg) return true;
    final h = int.tryParse(_heightCtrl.text.trim());
    if (h != _initialProfile?.heightCm) return true;
    return false;
  }

  void _onBackTap() {
    if (_isBusy) return; // don't interrupt an in-flight save
    if (_isDirty) {
      _showDiscardDialog();
    } else {
      context.pop();
    }
  }

  Future<void> _showDiscardDialog() async {
    final palette = AppPalette.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: palette.bgCard,
        title: Text(
          '¿Descartar los cambios?', // i18n: Fase 6 Etapa 3
          style: GoogleFonts.barlowCondensed(
            color: palette.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Lo que editaste se va a perder.', // i18n: Fase 6 Etapa 3
          style: GoogleFonts.barlow(color: palette.textMuted, fontSize: 14),
        ),
        // Center the action buttons (decision 2026-05-27).
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'VOLVER', // i18n: Fase 6 Etapa 3
              style: GoogleFonts.barlowCondensed(
                color: palette.textMuted,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 1.0,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'DESCARTAR', // i18n: Fase 6 Etapa 3
              style: GoogleFonts.barlowCondensed(
                color: palette.danger,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) context.pop();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    // Lazy seed: fires once when the stream delivers the first UserProfile.
    // In production the stream is already warm (no-op). In tests the
    // StreamProvider may not resolve until the first frame after pump().
    final profileAsync = ref.watch(userProfileProvider);
    profileAsync.whenData((p) {
      if (!_seeded) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _seedFromProfile(p));
          }
        });
      }
    });

    return Column(
      children: [
        // ── Header ──────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: GestureDetector(
            onTap: _onBackTap,
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Icon(TreinoIcon.back, size: 20, color: palette.textPrimary),
                const SizedBox(width: 14),
                Text(
                  'EDITAR PERFIL', // i18n: Fase 6 Etapa 3
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
        // ── Form ────────────────────────────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + MediaQuery.paddingOf(context).bottom),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar editor — centered (decision 2026-05-27)
                  Center(
                    child: _AvatarEditor(
                      key: const Key('edit_personal_avatar_editor'),
                      existingAvatarUrl: _existingAvatarUrl,
                      pendingLocalPath: _pendingLocalPath,
                      onTap: _pickAvatar,
                      palette: palette,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Display name
                  _FieldLabel(
                      label: 'NOMBRE',
                      palette: palette), // i18n: Fase 6 Etapa 3
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('edit_personal_display_name'),
                    controller: _nameCtrl,
                    validator: _validateDisplayName,
                    style: GoogleFonts.barlow(
                      color: palette.textPrimary,
                      fontSize: 14,
                    ),
                    decoration: _inputDecoration(
                      palette: palette,
                      hint: 'Tu nombre', // i18n: Fase 6 Etapa 3
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Gender
                  _FieldLabel(
                      label: 'GÉNERO',
                      palette: palette), // i18n: Fase 6 Etapa 3
                  const SizedBox(height: 8),
                  _GenderSelector(
                    selected: _selectedGender,
                    onChanged: (g) => setState(() => _selectedGender = g),
                    palette: palette,
                  ),
                  const SizedBox(height: 18),

                  // Body weight
                  _FieldLabel(
                      label: 'PESO (KG)',
                      palette: palette), // i18n: Fase 6 Etapa 3
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('edit_personal_weight_field'),
                    controller: _weightCtrl,
                    validator: _validateBodyWeightKg,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: GoogleFonts.barlow(
                      color: palette.textPrimary,
                      fontSize: 14,
                    ),
                    decoration: _inputDecoration(
                      palette: palette,
                      hint: '80',
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Height
                  _FieldLabel(
                      label: 'ALTURA (CM)',
                      palette: palette), // i18n: Fase 6 Etapa 3
                  const SizedBox(height: 8),
                  TextFormField(
                    key: const Key('edit_personal_height_field'),
                    controller: _heightCtrl,
                    validator: _validateHeightCm,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.barlow(
                      color: palette.textPrimary,
                      fontSize: 14,
                    ),
                    decoration: _inputDecoration(
                      palette: palette,
                      hint: '175',
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Experience level
                  _FieldLabel(
                      label: 'EXPERIENCIA',
                      palette: palette), // i18n: Fase 6 Etapa 3
                  const SizedBox(height: 8),
                  _ExperienceLevelSelector(
                    selected: _selectedExperience,
                    onChanged: (e) => setState(() => _selectedExperience = e),
                    palette: palette,
                  ),
                  const SizedBox(height: 20),

                  // Action row
                  ValueListenableBuilder<_SaveState>(
                    valueListenable: _saveState,
                    builder: (context, state, _) {
                      final busy = state == _SaveState.uploading ||
                          state == _SaveState.saving;
                      return Row(
                        children: [
                          Expanded(
                            child: _OutlinedPill(
                              key: const Key('edit_personal_discard_button'),
                              label: 'DESCARTAR', // i18n: Fase 6 Etapa 3
                              onTap: busy ? null : _onBackTap,
                              palette: palette,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _FilledPill(
                              key: const Key('edit_personal_save_button'),
                              label: busy
                                  ? '...'
                                  : 'GUARDAR', // i18n: Fase 6 Etapa 3
                              onTap: busy ? null : _save,
                              palette: palette,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration({
    required AppPalette palette,
    required String hint,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.barlow(
        color: palette.textMuted,
        fontSize: 14,
      ),
      filled: true,
      fillColor: palette.bgCard,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: palette.textMuted.withValues(alpha: 0.2),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: palette.textMuted.withValues(alpha: 0.2),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.accent),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: palette.danger),
      ),
      errorStyle: GoogleFonts.barlow(
        color: palette.danger,
        fontSize: 12,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Avatar editor
// ---------------------------------------------------------------------------

class _AvatarEditor extends StatelessWidget {
  const _AvatarEditor({
    super.key,
    this.existingAvatarUrl,
    this.pendingLocalPath,
    required this.onTap,
    required this.palette,
  });

  final String? existingAvatarUrl;
  final String? pendingLocalPath;
  final VoidCallback onTap;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.textMuted.withValues(alpha: 0.12),
                  image: _imageProvider != null
                      ? DecorationImage(
                          image: _imageProvider!,
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: _imageProvider == null
                    ? Icon(
                        TreinoIcon.tabProfile,
                        size: 36,
                        color: palette.textMuted,
                      )
                    : null,
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: palette.accent,
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.bg, width: 2),
                  ),
                  child: Icon(
                    TreinoIcon.edit,
                    color: palette.bg,
                    size: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Tocá para cambiar tu foto', // i18n: Fase 6 Etapa 3
            style: GoogleFonts.barlow(
              color: palette.textMuted,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  ImageProvider? get _imageProvider {
    if (pendingLocalPath != null) return FileImage(File(pendingLocalPath!));
    if (existingAvatarUrl != null) {
      return NetworkImage(existingAvatarUrl!);
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Gender selector
// ---------------------------------------------------------------------------

class _GenderSelector extends StatelessWidget {
  const _GenderSelector({
    required this.selected,
    required this.onChanged,
    required this.palette,
  });

  final Gender? selected;
  final ValueChanged<Gender?> onChanged;
  final AppPalette palette;

  static const _choices = [
    (value: Gender.male, label: 'HOMBRE'), // i18n: Fase 6 Etapa 3
    (value: Gender.female, label: 'MUJER'), // i18n: Fase 6 Etapa 3
    (value: Gender.undisclosed, label: 'OTRO'), // i18n: Fase 6 Etapa 3
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _choices.map((choice) {
        final isSelected = selected == choice.value;
        return GestureDetector(
          onTap: () => onChanged(isSelected ? null : choice.value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? palette.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(9999),
              border: Border.all(
                color: isSelected ? palette.accent : palette.border,
              ),
            ),
            child: Text(
              choice.label,
              style: GoogleFonts.barlowCondensed(
                color: isSelected ? palette.bg : palette.textMuted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Experience level selector
// ---------------------------------------------------------------------------

class _ExperienceLevelSelector extends StatelessWidget {
  const _ExperienceLevelSelector({
    required this.selected,
    required this.onChanged,
    required this.palette,
  });

  final ExperienceLevel? selected;
  final ValueChanged<ExperienceLevel?> onChanged;
  final AppPalette palette;

  static const _choices = [
    (
      value: ExperienceLevel.beginner,
      label: 'PRINCIPIANTE', // i18n: Fase 6 Etapa 3
      description: 'Recién empiezo o vuelvo después de mucho.',
    ),
    (
      value: ExperienceLevel.intermediate,
      label: 'INTERMEDIO', // i18n: Fase 6 Etapa 3
      description: 'Entreno hace 6+ meses, conozco la mayoría de ejercicios.',
    ),
    (
      value: ExperienceLevel.advanced,
      label: 'AVANZADO', // i18n: Fase 6 Etapa 3
      description: '2+ años entrenando con periodización.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _choices.map((choice) {
        final isSelected = selected == choice.value;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: GestureDetector(
            onTap: () => onChanged(isSelected ? null : choice.value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: palette.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? palette.accent : palette.border,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    choice.label,
                    style: GoogleFonts.barlowCondensed(
                      color: isSelected ? palette.accent : palette.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    choice.description,
                    style: GoogleFonts.barlow(
                      color: palette.textMuted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared pill buttons
// ---------------------------------------------------------------------------

class _FilledPill extends StatelessWidget {
  const _FilledPill({
    super.key,
    required this.label,
    required this.onTap,
    required this.palette,
  });

  final String label;
  final VoidCallback? onTap;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: onTap != null ? palette.accent : palette.border,
          borderRadius: BorderRadius.circular(9999),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.barlowCondensed(
            color: palette.bg,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }
}

class _OutlinedPill extends StatelessWidget {
  const _OutlinedPill({
    super.key,
    required this.label,
    required this.onTap,
    required this.palette,
  });

  final String label;
  final VoidCallback? onTap;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(color: palette.border),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: GoogleFonts.barlowCondensed(
            color: palette.textMuted,
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Field label
// ---------------------------------------------------------------------------

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, required this.palette});

  final String label;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.barlowCondensed(
        color: palette.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
      ),
    );
  }
}
