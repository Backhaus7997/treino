import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_motion.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/widgets/motion/treino_fade_slide_in.dart';
import 'package:treino/core/widgets/motion/treino_shimmer.dart';
import 'package:treino/core/widgets/motion/treino_state_switcher.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/tabs/notificaciones_prefs.dart';
import 'package:treino/features/profile/application/user_providers.dart';

/// Tab «Notificaciones» de Configuración (Fase W3.2 / Fase 12 WU-05).
///
/// Matriz tipo-de-aviso × canal (Email/Push/WhatsApp). Persiste en
/// `users/{uid}.notificationPrefs` vía `userRepository.update` (save-on-toggle,
/// optimista: el stream de Firestore refleja el cambio al instante).
/// Honesto: las prefs se GUARDAN; la entrega real (CFs que las respeten +
/// canales email/whatsapp) es follow-up de `functions/`.
class NotificacionesTab extends ConsumerWidget {
  const NotificacionesTab({super.key});

  static const double _colW = 80;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(webNotificationPreferencesProvider);
    final uid = ref.watch(userProfileProvider).valueOrNull?.uid;

    // Cross-fade entre loading→data→error (ADR-F12-03), mismo patrón que
    // CuentaTab (WU-03): cada estado con su propia key para que
    // TreinoStateSwitcher detecte el cambio y anime.
    final stateKey = switch (prefsAsync) {
      AsyncData() => const ValueKey('data'),
      AsyncError() => const ValueKey('error'),
      _ => const ValueKey('loading'),
    };

    return TreinoStateSwitcher(
      childKey: stateKey,
      child: prefsAsync.when(
        loading: () => const _NotifSkeleton(),
        error: (_, __) => _muted(
          context,
          'No se pudieron cargar tus preferencias.', // i18n: Fase W3
        ),
        data: (prefs) => _NotifBody(prefs: prefs, uid: uid, colW: _colW),
      ),
    );
  }
}

/// Cuerpo real del tab en estado `data`: label + subtítulo + matriz + nota
/// honesta de scope. Separado de `NotificacionesTab.build` para que
/// `TreinoStateSwitcher` distinga limpiamente este child del skeleton/error.
class _NotifBody extends StatelessWidget {
  const _NotifBody(
      {required this.prefs, required this.uid, required this.colW});

  final NotifPrefs prefs;
  final String? uid;
  final double colW;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(context, 'NOTIFICACIONES'), // i18n: Fase W3
        const SizedBox(height: 4),
        Text(
          'Elegí cómo querés recibir cada tipo de aviso.', // i18n: Fase W3
          style: TextStyle(color: palette.textMuted, fontSize: 13),
        ),
        const SizedBox(height: 16),
        _Matrix(prefs: prefs, uid: uid, colW: colW),
        const SizedBox(height: 12),
        Text(
          // Honestidad de scope (W3.2): ver notificaciones_prefs.dart.
          'Las preferencias se guardan. La entrega por email y WhatsApp se '
          'activa próximamente.', // i18n: Fase W3
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

/// Skeleton de la matriz para el loading de Notificaciones (ADR-F12-03) —
/// espeja el layout real: header de canales (EMAIL/PUSH/WHATSAPP) + ~5 filas
/// de tipo de aviso, dentro de la misma card tokenizada.
class _NotifSkeleton extends StatelessWidget {
  const _NotifSkeleton();

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
      key: const Key('notif_skeleton'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _bar(palette, width: 150, height: 11),
        const SizedBox(height: 6),
        _bar(palette, width: 260, height: 13),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
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
                  children: [
                    const Expanded(child: SizedBox()),
                    for (var i = 0; i < 3; i++)
                      Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: _bar(palette, width: 48, height: 10),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                for (var i = 0; i < 5; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(child: _bar(palette, width: 170)),
                        for (var c = 0; c < 3; c++)
                          Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: _bar(palette, width: 18, height: 18),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Matrix extends ConsumerWidget {
  const _Matrix({required this.prefs, required this.uid, required this.colW});

  final NotifPrefs prefs;
  final String? uid;
  final double colW;

  Future<void> _set(
    WidgetRef ref,
    BuildContext context,
    String typeKey,
    NotifChannel ch,
    bool value,
  ) async {
    final id = uid;
    if (id == null) return;
    try {
      await ref.read(userRepositoryProvider).update(id, {
        'notificationPrefs': prefs.toggle(typeKey, ch, value).toFirestore(),
      });
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo guardar. Probá de nuevo.'), // i18n
          ),
        );
      }
    }
  }

  /// Agrupa `kNotifTypes` preservando el orden de aparición (PAGOS / ALUMNOS
  /// / CHAT) — cada entrada es un bloque que entra con su propio stagger.
  List<MapEntry<String, List<NotifType>>> _groups() {
    final byGroup = <String, List<NotifType>>{};
    for (final t in kNotifTypes) {
      byGroup.putIfAbsent(t.group, () => []).add(t);
    }
    return byGroup.entries.toList();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final groups = _groups();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeaderRow(colW: colW),
          // Stagger por GRUPO (ADR-F12-04): Column eager, no ListView.builder
          // — el stagger es seguro acá.
          for (var i = 0; i < groups.length; i++)
            TreinoFadeSlideIn(
              delay: AppMotion.stagger(i),
              child: _GroupBlock(
                group: groups[i].key,
                types: groups[i].value,
                prefs: prefs,
                colW: colW,
                onSet: (typeKey, ch, v) => _set(ref, context, typeKey, ch, v),
              ),
            ),
        ],
      ),
    );
  }
}

/// Un grupo (PAGOS / ALUMNOS / CHAT): label del grupo + sus filas.
class _GroupBlock extends StatelessWidget {
  const _GroupBlock({
    required this.group,
    required this.types,
    required this.prefs,
    required this.colW,
    required this.onSet,
  });

  final String group;
  final List<NotifType> types;
  final NotifPrefs prefs;
  final double colW;
  final void Function(String typeKey, NotifChannel ch, bool value) onSet;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
          child: Text(
            group,
            style: TextStyle(
              color: palette.accent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        for (final t in types)
          _Row(
            type: t,
            prefs: prefs,
            colW: colW,
            onSet: (ch, v) => onSet(t.key, ch, v),
          ),
      ],
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.colW});

  final double colW;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    TextStyle s() => TextStyle(
          color: palette.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        );
    return Row(
      children: [
        const Expanded(child: SizedBox()),
        for (final ch in NotifChannel.values)
          SizedBox(
            width: colW,
            child: Center(child: Text(ch.label, style: s())),
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.type,
    required this.prefs,
    required this.colW,
    required this.onSet,
  });

  final NotifType type;
  final NotifPrefs prefs;
  final double colW;
  final void Function(NotifChannel ch, bool value) onSet;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              type.label,
              style: TextStyle(color: palette.textPrimary, fontSize: 14),
            ),
          ),
          for (final ch in NotifChannel.values)
            _ToggleCell(
              value: prefs.isOn(type.key, ch),
              colW: colW,
              onChanged: (v) => onSet(ch, v ?? false),
            ),
        ],
      ),
    );
  }
}

/// Celda de la matriz: `Checkbox` + micro feedback animado al togglear
/// (ADR-F12-04) — un halo tokenizado (`palette.accent`) que aparece/desaparece
/// vía `AnimatedContainer` implícito cuando cambia `value` (sin
/// `AnimationController` propio, respeta reduce-motion vía `AppMotion.resolve`).
class _ToggleCell extends StatelessWidget {
  const _ToggleCell({
    required this.value,
    required this.colW,
    required this.onChanged,
  });

  final bool value;
  final double colW;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizedBox(
      width: colW,
      child: Center(
        child: AnimatedContainer(
          duration: AppMotion.resolve(context, AppMotion.micro),
          curve: AppMotion.standard,
          padding: const EdgeInsets.all(AppSpacing.hairline),
          decoration: BoxDecoration(
            color: value
                ? palette.accent.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Checkbox(
            value: value,
            onChanged: onChanged,
            activeColor: palette.accent,
            checkColor: palette.bg,
            side: BorderSide(color: palette.border),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }
}

Widget _label(BuildContext context, String text) {
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

Widget _muted(BuildContext context, String text) {
  final palette = AppPalette.of(context);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 40),
    child: Center(
      child:
          Text(text, style: TextStyle(color: palette.textMuted, fontSize: 14)),
    ),
  );
}
