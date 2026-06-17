import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/tabs/avatar_web_uploader.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';

/// Tab «Cuenta» de Configuración (Fase W3.1 / W3.1b).
///
/// Información personal del PF logueado (foto, nombre, apellido, email,
/// teléfono, idioma) + «Zona peligrosa». Reusa `userProfileProvider` — pantalla
/// web nueva sin re-implementar data (AD-CHA-04). `firstName`/`lastName`/`phone`
/// se persisten en `users` vía `userRepository.update`; `displayName` se deriva
/// de nombre+apellido para no romper roster/perfil público.
class CuentaTab extends ConsumerWidget {
  const CuentaTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(userProfileProvider);
    return profileAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) =>
          const _Muted('No se pudo cargar tu cuenta.'), // i18n: Fase W3
      data: (profile) => profile == null
          ? const _Muted('No se pudo cargar tu cuenta.') // i18n: Fase W3
          : _CuentaForm(profile: profile),
    );
  }
}

/// Separa el nombre en (nombre, apellido). Para usuarios previos a W3.1b
/// (sin `firstName`/`lastName`) deriva del `displayName` partiendo en el
/// primer espacio.
({String first, String last}) _splitName(UserProfile p) {
  final first = p.firstName?.trim() ?? '';
  final last = p.lastName?.trim() ?? '';
  if (first.isNotEmpty || last.isNotEmpty) return (first: first, last: last);

  final parts = (p.displayName ?? '').trim().split(RegExp(r'\s+'))
    ..removeWhere((s) => s.isEmpty);
  if (parts.isEmpty) return (first: '', last: '');
  if (parts.length == 1) return (first: parts.first, last: '');
  return (first: parts.first, last: parts.sublist(1).join(' '));
}

class _CuentaForm extends ConsumerStatefulWidget {
  const _CuentaForm({required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<_CuentaForm> createState() => _CuentaFormState();
}

class _CuentaFormState extends ConsumerState<_CuentaForm> {
  late final TextEditingController _first;
  late final TextEditingController _last;
  late final TextEditingController _phone;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final n = _splitName(widget.profile);
    _first = TextEditingController(text: n.first);
    _last = TextEditingController(text: n.last);
    _phone = TextEditingController(text: widget.profile.phone ?? '');
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool get _dirty {
    final n = _splitName(widget.profile);
    return _first.text.trim() != n.first ||
        _last.text.trim() != n.last ||
        _phone.text.trim() != (widget.profile.phone ?? '').trim();
  }

  // GUARDAR CAMBIOS exige al menos un nombre: si no, `displayName` (derivado de
  // nombre+apellido) quedaría vacío y rompería roster/perfil público.
  bool get _canSave => _dirty && _first.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (_saving) return;
    final first = _first.text.trim();
    final last = _last.text.trim();
    final phone = _phone.text.trim();
    if (first.isEmpty) {
      _toast('El nombre no puede estar vacío.'); // i18n: Fase W3
      return;
    }
    final displayName = [first, last].where((s) => s.isNotEmpty).join(' ');
    setState(() => _saving = true);
    try {
      await ref.read(userRepositoryProvider).update(widget.profile.uid, {
        'firstName': first,
        'lastName': last,
        'phone': phone,
        'displayName': displayName,
      });
      _toast('Cambios guardados'); // i18n: Fase W3
    } catch (_) {
      _toast('No se pudieron guardar los cambios. Probá de nuevo.'); // i18n
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(
            onPressed: (_canSave && !_saving) ? _save : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: palette.accent,
              foregroundColor: palette.bg,
              disabledBackgroundColor: palette.bgCard,
              disabledForegroundColor: palette.textMuted,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
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
                : const Text('GUARDAR CAMBIOS'), // i18n: Fase W3
          ),
        ),
        const SizedBox(height: 16),
        const _SectionLabel('INFORMACIÓN PERSONAL'), // i18n: Fase W3
        const SizedBox(height: 4),
        Text(
          'Esta info se muestra en tu perfil público.', // i18n: Fase W3
          style: TextStyle(color: palette.textMuted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: palette.bgCard,
            border: Border.all(color: palette.border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FotoEditor(profile: widget.profile),
              const SizedBox(height: 22),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _LabeledInput(
                      label: 'NOMBRE', // i18n: Fase W3
                      controller: _first,
                      enabled: !_saving,
                      onChanged: () => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _LabeledInput(
                      label: 'APELLIDO', // i18n: Fase W3
                      controller: _last,
                      enabled: !_saving,
                      onChanged: () => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Email = identidad de Auth, read-only (cambiarlo exige
              // re-verificación; la rule de Firestore lo bloquea).
              _Field(label: 'EMAIL', value: widget.profile.email),
              const SizedBox(height: 14),
              _LabeledInput(
                label: 'TELÉFONO', // i18n: Fase W3
                controller: _phone,
                enabled: !_saving,
                onChanged: () => setState(() {}),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 14),
              // Idioma lockeado a es-AR (locale_resolver, ADR-I18N-005).
              const _Field(label: 'IDIOMA', value: 'Español (Argentina)'),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const _DangerZone(),
      ],
    );
  }
}

/// Avatar (con anillo degradé) + caption + CAMBIAR FOTO / QUITAR (W3.1b).
/// La foto se guarda al instante (no espera al GUARDAR CAMBIOS): sube vía
/// [AvatarWebUploader] y persiste `avatarUrl`; QUITAR setea `avatarUrl: null`.
class _FotoEditor extends ConsumerStatefulWidget {
  const _FotoEditor({required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<_FotoEditor> createState() => _FotoEditorState();
}

class _FotoEditorState extends ConsumerState<_FotoEditor> {
  bool _busy = false;

  Future<void> _changePhoto() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final url = await ref.read(avatarWebUploaderProvider).pickAndUpload();
      if (url == null) return; // picker cancelado
      await ref
          .read(userRepositoryProvider)
          .update(widget.profile.uid, {'avatarUrl': url});
      _toast('Foto actualizada'); // i18n: Fase W3
    } on AvatarTooLargeException {
      // i18n: Fase W3
      _toast('La imagen supera el máximo de 2 MB. Probá con una más liviana.');
    } catch (_) {
      _toast('No se pudo cambiar la foto. Probá de nuevo.'); // i18n: Fase W3
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePhoto() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Borra el archivo de Storage (best-effort) y limpia la referencia para
      // no dejar el objeto huérfano en avatars/{uid}.jpg.
      await ref.read(avatarWebUploaderProvider).deleteStored();
      await ref
          .read(userRepositoryProvider)
          .update(widget.profile.uid, {'avatarUrl': null});
      _toast('Foto quitada'); // i18n: Fase W3
    } catch (_) {
      _toast('No se pudo quitar la foto. Probá de nuevo.'); // i18n: Fase W3
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final name = (widget.profile.displayName ?? '').trim();
    final hasAvatar = (widget.profile.avatarUrl ?? '').isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [palette.accent, palette.highlight],
            ),
          ),
          child: _Avatar(
              name: name, url: widget.profile.avatarUrl, palette: palette),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (name.isNotEmpty)
                Text(
                  name,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(height: 4),
              Text(
                // i18n: Fase W3
                'JPG o PNG · máximo 2MB · 400x400 px recomendado',
                style: TextStyle(color: palette.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : _changePhoto,
                    child: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('CAMBIAR FOTO'), // i18n: Fase W3
                  ),
                  if (hasAvatar)
                    TextButton(
                      onPressed: _busy ? null : _removePhoto,
                      style: TextButton.styleFrom(
                        foregroundColor: palette.danger,
                      ),
                      child: const Text('QUITAR'), // i18n: Fase W3
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DangerZone extends ConsumerWidget {
  const _DangerZone();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final links = ref.watch(trainerLinksStreamProvider).valueOrNull ?? const [];
    final activos = links
        .where((l) => l.status == TrainerLinkStatus.active)
        .map((l) => l.athleteId)
        .toSet()
        .length;
    final alumnos =
        activos == 1 ? '1 alumno activo' : '$activos alumnos activos';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.danger),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ZONA PELIGROSA', // i18n: Fase W3
            style: TextStyle(
              color: palette.danger,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            // i18n: Fase W3
            'Tu cuenta tiene $alumnos. Eliminar la cuenta cancela todos los '
            'planes y emite los reembolsos correspondientes.',
            style: TextStyle(color: palette.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton(
                onPressed: () => _soon(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.warning,
                  side: BorderSide(color: palette.warning),
                ),
                child: const Text('PAUSAR CUENTA'), // i18n: Fase W3
              ),
              OutlinedButton(
                onPressed: () => _soon(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.danger,
                  side: BorderSide(color: palette.danger),
                ),
                child: const Text('ELIMINAR CUENTA'), // i18n: Fase W3
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LabeledInput extends StatelessWidget {
  const _LabeledInput({
    required this.label,
    required this.controller,
    required this.enabled,
    required this.onChanged,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    OutlineInputBorder border(Color c) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: palette.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: keyboardType,
          onChanged: (_) => onChanged(),
          style: TextStyle(color: palette.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: palette.bg,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: border(palette.border),
            enabledBorder: border(palette.border),
            focusedBorder: border(palette.accent),
            disabledBorder: border(palette.border),
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: palette.textMuted, fontSize: 12)),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: palette.bg,
            border: Border.all(color: palette.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            value,
            style: TextStyle(color: palette.textPrimary, fontSize: 14),
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.url, required this.palette});

  final String name;
  final String? url;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final hasUrl = url != null && url!.isNotEmpty;
    return CircleAvatar(
      radius: 28,
      backgroundColor: palette.bg,
      backgroundImage: hasUrl ? NetworkImage(url!) : null,
      // Una URL de avatar rota no debe romper la UI: caemos al color de fondo.
      onBackgroundImageError: hasUrl ? (_, __) {} : null,
      child: (url == null || url!.isEmpty)
          ? Text(
              initial,
              style: TextStyle(
                color: palette.accent,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            )
          : null,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Text(
      text,
      style: TextStyle(
        color: palette.textMuted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Text(
          text,
          style: TextStyle(color: palette.textMuted, fontSize: 14),
        ),
      ),
    );
  }
}

/// Placeholder honesto para acciones todavía no cableadas (pausar/eliminar →
/// W3.3; pausar no tiene backend).
void _soon(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Próximamente')), // i18n: Fase W3
  );
}
