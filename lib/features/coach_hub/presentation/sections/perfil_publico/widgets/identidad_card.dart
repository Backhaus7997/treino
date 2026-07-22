// IdentidadCard — card «IDENTIDAD» de la columna izquierda de
// PerfilPublicoScreen (Fase 11, WU-03).
//
// Foto y nombre son READ-ONLY acá + deep-link a Ajustes › Cuenta
// (`/ajustes`) — evita duplicar el uploader de avatar de `_FotoEditor`
// (cuenta_tab.dart, AD-CHA-04-style reuse). La BIO sí se edita inline: mismo
// patrón save-real de `_CuentaForm` (dirty/saving/save con
// try/catch/finally), persiste `trainerBio` vía `userRepositoryProvider`,
// mismo criterio de validación que `profile_edit_trainer_screen.dart`
// (no vacía, ≥20 caracteres, máx 280).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/feed/presentation/widgets/post_avatar.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';

/// Card «IDENTIDAD» — columna izquierda de `PerfilPublicoScreen` (WU-03).
class IdentidadCard extends ConsumerStatefulWidget {
  const IdentidadCard({super.key, required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<IdentidadCard> createState() => _IdentidadCardState();
}

class _IdentidadCardState extends ConsumerState<IdentidadCard> {
  late final TextEditingController _bio;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _bio = TextEditingController(text: widget.profile.trainerBio ?? '');
  }

  @override
  void dispose() {
    _bio.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _bio.text.trim() != (widget.profile.trainerBio ?? '').trim();

  // Mismo criterio que profile_edit_trainer_screen.dart: no vacía, ≥20
  // caracteres — evita bios "muertas" tipo "hola" en Coach Discovery.
  String? get _bioError {
    final value = _bio.text.trim();
    if (value.isEmpty) return 'Escribí una bio.'; // i18n: Fase 11
    if (value.length < 20) return 'Al menos 20 caracteres.'; // i18n: Fase 11
    return null;
  }

  bool get _canSave => _dirty && _bioError == null;

  Future<void> _save() async {
    if (_saving) return;
    final error = _bioError;
    if (error != null) {
      _toast(error);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(userRepositoryProvider).update(widget.profile.uid, {
        'trainerBio': _bio.text.trim(),
      });
      _toast('Bio guardada.'); // i18n: Fase 11
    } catch (_) {
      _toast('No se pudo guardar la bio. Probá de nuevo.'); // i18n: Fase 11
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final profile = widget.profile;
    final name = (profile.displayName ?? '').trim();

    OutlineInputBorder border(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c),
        );

    return TreinoFadeSlideIn(
      delay: AppMotion.stagger(0),
      child: Container(
        key: const Key('identidad_card'),
        padding: const EdgeInsets.all(AppSpacing.s18),
        decoration: BoxDecoration(
          color: palette.bgCard,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'IDENTIDAD', // i18n: Fase 11
              style: TextStyle(
                fontFamily: AppFonts.barlowCondensed,
                fontWeight: AppFonts.w700,
                fontSize: 14,
                letterSpacing: AppFonts.headingTracking,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.s14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                PostAvatar(
                  key: const Key('identidad_card_avatar'),
                  authorDisplayName: name,
                  authorAvatarUrl: profile.avatarUrl,
                  size: 56,
                ),
                const SizedBox(width: AppSpacing.s12),
                Expanded(
                  child: Text(
                    name.isNotEmpty ? name : '—',
                    key: const Key('identidad_card_display_name'),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s12),
            TreinoInteractiveState(
              onTap: () => context.go('/ajustes'),
              builder: (ctx, states) => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s12,
                  vertical: AppSpacing.hairline,
                ),
                decoration: BoxDecoration(
                  color: states.hovered
                      ? palette.accent.withValues(alpha: 0.08)
                      : AppColorPrimitives.transparent,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(TreinoIcon.edit, size: 14, color: palette.accent),
                    const SizedBox(width: AppSpacing.hairline),
                    Text(
                      'Editar foto y nombre', // i18n: Fase 11
                      style: TextStyle(
                        color: palette.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s18),
            Text(
              'BIO', // i18n: Fase 11
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
              key: const Key('identidad_card_bio_field'),
              controller: _bio,
              maxLines: 4,
              maxLength: 280,
              enabled: !_saving,
              onChanged: (_) => setState(() {}),
              style: TextStyle(color: palette.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: palette.bg,
                hintText:
                    'Contales a tus futuros alumnos cómo entrenás.', // i18n: Fase 11
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
                key: const Key('identidad_card_save_button'),
                onPressed: (_canSave && !_saving) ? _save : null,
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
          ],
        ),
      ),
    );
  }
}
