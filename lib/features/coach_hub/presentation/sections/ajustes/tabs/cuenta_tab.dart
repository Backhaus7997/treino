import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

/// Tab «Cuenta» de Configuración (Fase W3.1).
///
/// Muestra la información personal del PF logueado (avatar, nombre, email,
/// idioma) y la «Zona peligrosa». Reusa `userProfileProvider` — pantalla web
/// nueva sin re-implementar data (AD-CHA-04). La edición inline de campos, el
/// «cambiar foto» y el wire real de pausar/eliminar cuenta llegan en slices
/// siguientes (eliminar vive en W3.3 Datos/Privacidad). Acá los botones
/// señalan la intención sin ejecutar la baja todavía.
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
      data: (profile) {
        if (profile == null) {
          return const _Muted('No se pudo cargar tu cuenta.'); // i18n: Fase W3
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionLabel('INFORMACIÓN PERSONAL'), // i18n: Fase W3
            const SizedBox(height: 12),
            _PersonalCard(profile: profile),
            const SizedBox(height: 28),
            const _DangerZone(),
          ],
        );
      },
    );
  }
}

class _PersonalCard extends StatelessWidget {
  const _PersonalCard({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final name = (profile.displayName ?? '').trim();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.bgCard,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _Avatar(name: name, url: profile.avatarUrl, palette: palette),
              const SizedBox(width: 18),
              Expanded(
                child: Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton(
                      onPressed: () => _soon(context),
                      child: const Text('CAMBIAR FOTO'), // i18n: Fase W3
                    ),
                    _RoleBadge(role: profile.role, palette: palette),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // i18n: Fase W3 (labels de campos).
          _Field(label: 'Nombre', value: name.isEmpty ? '—' : name),
          const SizedBox(height: 14),
          _Field(label: 'Email', value: profile.email),
          const SizedBox(height: 14),
          // El idioma está lockeado a es-AR (locale_resolver, ADR-I18N-005).
          const _Field(label: 'Idioma', value: 'Español (Argentina)'),
        ],
      ),
    );
  }
}

class _DangerZone extends StatelessWidget {
  const _DangerZone();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
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
            'Pausar suspende tu cuenta temporalmente. Eliminar borra tu cuenta, '
            'tus alumnos y tu perfil de forma permanente.',
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role, required this.palette});

  final UserRole role;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    // i18n: Fase W3
    final label = role == UserRole.trainer ? 'ENTRENADOR' : 'ATLETA';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: palette.bg,
        border: Border.all(color: palette.accent),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: palette.accent,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
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
    return CircleAvatar(
      radius: 28,
      backgroundColor: palette.bg,
      backgroundImage:
          (url != null && url!.isNotEmpty) ? NetworkImage(url!) : null,
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

/// Placeholder honesto para acciones todavía no cableadas en W3.1.
void _soon(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Próximamente')), // i18n: Fase W3
  );
}
