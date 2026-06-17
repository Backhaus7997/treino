import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/tabs/notificaciones_prefs.dart';
import 'package:treino/features/profile/application/user_providers.dart';

/// Tab «Notificaciones» de Configuración (Fase W3.2).
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
    final palette = AppPalette.of(context);
    final prefsAsync = ref.watch(webNotificationPreferencesProvider);
    final uid = ref.watch(userProfileProvider).valueOrNull?.uid;

    return prefsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => _muted(
        context,
        'No se pudieron cargar tus preferencias.', // i18n: Fase W3
      ),
      data: (prefs) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(context, 'NOTIFICACIONES'), // i18n: Fase W3
          const SizedBox(height: 4),
          Text(
            'Elegí cómo querés recibir cada tipo de aviso.', // i18n: Fase W3
            style: TextStyle(color: palette.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 16),
          _Matrix(prefs: prefs, uid: uid, colW: _colW),
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
      ),
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final children = <Widget>[_HeaderRow(colW: colW)];
    String? lastGroup;
    for (final t in kNotifTypes) {
      if (t.group != lastGroup) {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
          child: Text(
            t.group,
            style: TextStyle(
              color: palette.accent,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ));
        lastGroup = t.group;
      }
      children.add(_Row(
        type: t,
        prefs: prefs,
        colW: colW,
        onSet: (ch, v) => _set(ref, context, t.key, ch, v),
      ));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
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
            SizedBox(
              width: colW,
              child: Center(
                child: Checkbox(
                  value: prefs.isOn(type.key, ch),
                  onChanged: (v) => onSet(ch, v ?? false),
                  activeColor: palette.accent,
                  checkColor: palette.bg,
                  side: BorderSide(color: palette.border),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
        ],
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
