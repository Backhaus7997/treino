import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/components/treino_focus_tokens.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/image/avatar_cropper.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/core/widgets/motion/treino_shimmer.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/tabs/avatar_web_uploader.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
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
    // Cross-fade entre loading→data→error (ADR-F12-03) — cada estado con su
    // propia key para que TreinoStateSwitcher detecte el cambio y anime.
    final stateKey = switch (profileAsync) {
      AsyncData() => const ValueKey('data'),
      AsyncError() => const ValueKey('error'),
      _ => const ValueKey('loading'),
    };
    return TreinoStateSwitcher(
      childKey: stateKey,
      child: profileAsync.when(
        loading: () => const _CuentaSkeleton(),
        error: (_, __) =>
            const _Muted('No se pudo cargar tu cuenta.'), // i18n: Fase W3
        data: (profile) => profile == null
            ? const _Muted('No se pudo cargar tu cuenta.') // i18n: Fase W3
            : _CuentaForm(profile: profile),
      ),
    );
  }
}

/// Skeleton de formulario para el loading de Cuenta (ADR-F12-03) — espeja el
/// layout real: botón GUARDAR, label + subtítulo, y la card «INFORMACIÓN
/// PERSONAL» (avatar circular + filas NOMBRE/APELLIDO, EMAIL, TELÉFONO).
class _CuentaSkeleton extends StatelessWidget {
  const _CuentaSkeleton();

  Widget _bar(AppPalette palette, {double? width, double height = 12}) =>
      Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: palette.border,
          borderRadius: BorderRadius.circular(4),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      key: const Key('cuenta_skeleton'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: _bar(palette, width: 170, height: 44),
        ),
        const SizedBox(height: 16),
        _bar(palette, width: 160, height: 11),
        const SizedBox(height: 6),
        _bar(palette, width: 220, height: 13),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: palette.bgCard,
            border: Border.all(color: palette.border),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: TreinoShimmer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: palette.border,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _bar(palette, width: 140),
                          const SizedBox(height: 8),
                          _bar(palette, width: 210, height: 10),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(child: _bar(palette, height: 44)),
                    const SizedBox(width: 16),
                    Expanded(child: _bar(palette, height: 44)),
                  ],
                ),
                const SizedBox(height: 14),
                _bar(palette, height: 44),
                const SizedBox(height: 14),
                _bar(palette, height: 44),
              ],
            ),
          ),
        ),
      ],
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
        // Tarjeta «INFORMACIÓN PERSONAL» — primera en el stagger eager
        // (ADR-F12-04, PROHIBIDO dentro de ListView.builder; acá es un
        // Column fijo, no aplica el riesgo).
        TreinoFadeSlideIn(
          delay: AppMotion.stagger(0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionLabel('INFORMACIÓN PERSONAL'), // i18n: Fase W3
              const SizedBox(height: 4),
              const _PerfilPublicoCaption(),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: palette.bgCard,
                  border: Border.all(color: palette.border),
                  borderRadius: BorderRadius.circular(AppRadius.md),
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
            ],
          ),
        ),
        const SizedBox(height: 28),
        TreinoFadeSlideIn(
          delay: AppMotion.stagger(1),
          child: const _DangerZone(),
        ),
      ],
    );
  }
}

/// Subtítulo de la card «INFORMACIÓN PERSONAL» con deep-link honesto
/// (ADR-F12-07) a `/perfil-publico` (Fase 11, ya rediseñada) — «perfil
/// público» es tappable vía [TreinoInteractiveState] (hover/focus/teclado +
/// `Semantics(button: true)` de fábrica).
class _PerfilPublicoCaption extends StatelessWidget {
  const _PerfilPublicoCaption();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final focusTokens = TreinoFocusTokens.of(context);
    final muted = TextStyle(color: palette.textMuted, fontSize: 13);

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Esta info se muestra en tu ', style: muted), // i18n: Fase W3
        TreinoInteractiveState(
          onTap: () => context.go('/perfil-publico'),
          builder: (ctx, states) => Container(
            key: const Key('cuenta_perfil_publico_link'),
            padding:
                const EdgeInsets.symmetric(horizontal: AppSpacing.hairline),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border:
                  states.focused ? Border.all(color: focusTokens.ring) : null,
            ),
            child: Text(
              'perfil público', // i18n: Fase W3
              style: TextStyle(
                color: palette.accent,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                decoration: states.hovered ? TextDecoration.underline : null,
              ),
            ),
          ),
        ),
        Text('.', style: muted),
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
      final uploader = ref.read(avatarWebUploaderProvider);
      final picked = await uploader.pickFile();
      if (picked == null) return; // picker cancelado
      if (!mounted) return;
      // Cropper con preview circular + 1:1 lock antes de subir.
      final croppedPath = await AvatarCropper().cropToSquare(
        sourcePath: picked.path,
        context: context,
      );
      if (croppedPath == null) return; // cropper cancelado
      final url = await uploader.uploadCroppedPath(croppedPath);
      if (!mounted) return;
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
        borderRadius: BorderRadius.circular(AppRadius.md),
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
                onPressed: () => _confirmPausarCuenta(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: palette.warning,
                  side: BorderSide(color: palette.warning),
                ),
                child: const Text('PAUSAR CUENTA'), // i18n: Fase W3
              ),
              OutlinedButton(
                onPressed: () => _confirmEliminarCuenta(context),
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

/// Confirmación honesta de ELIMINAR CUENTA (ADR-F12-01/F12-08): eliminar la
/// cuenta se gestiona desde la app móvil (políticas de las stores) — no hay
/// backend web para ejecutarlo, así que el dialog nunca promete una acción
/// que no corre. `Entendido` sólo cierra el dialog, no muta nada.
Future<void> _confirmEliminarCuenta(BuildContext context) {
  return showTreinoDialog<void>(
    context,
    builder: (ctx) => TreinoDialog(
      title: 'Eliminar cuenta', // i18n: Fase W3
      body: const Text(
        // i18n: Fase W3
        'La eliminación de tu cuenta se gestiona desde la app TREINO, '
        'según las políticas de las tiendas de aplicaciones. Próximamente '
        'vas a poder hacerlo también desde acá.',
      ),
      destructive: true,
      primaryLabel: 'Entendido', // i18n: Fase W3
      onPrimaryTap: () => Navigator.of(ctx).maybePop(),
      secondaryLabel: 'Cancelar', // i18n: Fase W3
      onSecondaryTap: () => Navigator.of(ctx).maybePop(),
    ),
  );
}

/// Confirmación honesta de PAUSAR CUENTA: todavía no hay backend web para
/// pausar la cuenta — el dialog lo explica en vez de simular la acción con
/// un snackbar «Próximamente» seco.
Future<void> _confirmPausarCuenta(BuildContext context) {
  return showTreinoDialog<void>(
    context,
    builder: (ctx) => TreinoDialog(
      title: 'Pausar cuenta', // i18n: Fase W3
      body: const Text(
        // i18n: Fase W3
        'Pausar la cuenta todavía no está disponible desde la web. '
        'Próximamente vas a poder hacerlo desde acá.',
      ),
      primaryLabel: 'Entendido', // i18n: Fase W3
      onPrimaryTap: () => Navigator.of(ctx).maybePop(),
      secondaryLabel: 'Cancelar', // i18n: Fase W3
      onSecondaryTap: () => Navigator.of(ctx).maybePop(),
    ),
  );
}
