// NutricionPlanRow — fila presentational del overview cross-alumno de
// Nutrición (WU-03, Fase 6). Sigue el patrón de `FriendRequestInboxTile`:
// `ConsumerWidget` que watchea `userPublicProfileProvider(athleteId)`
// internamente para resolver nombre/avatar (el caller solo inyecta el
// [NutricionEntry] + el callback de navegación — no navega acá).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/sections/nutricion/nutricion_providers.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';
import 'package:treino/features/feed/presentation/widgets/post_avatar.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

class NutricionPlanRow extends ConsumerWidget {
  const NutricionPlanRow({super.key, required this.entry, this.onTap})
      : loading = false;

  /// Fila-skeleton sin `entry` — usada por la screen (WU-05) mientras
  /// `nutricionEntriesProvider` todavía no resolvió el roster completo
  /// (distinto del `planLoading` por-fila, que resuelve solo el plan de un
  /// alumno ya conocido).
  const NutricionPlanRow.loading({super.key})
      : entry = null,
        onTap = null,
        loading = true;

  /// Vínculo + plan (o ausencia de) del alumno — `nutricionEntriesProvider`.
  /// `null` solo cuando `loading == true`.
  final NutricionEntry? entry;

  /// Acción al tocar la fila. El caller (screen, WU-04+) es responsable de
  /// navegar al detalle del plan — este widget solo delega el evento.
  final VoidCallback? onTap;

  /// `true` = fila-skeleton sin datos todavía (roster completo en loading).
  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mientras el roster completo o el plan de este alumno todavía están
    // resolviendo el stream, el skeleton del kit (`TreinoListRow(loading:
    // true)`) reemplaza toda la fila — nunca un `CircularProgressIndicator`
    // seco.
    if (loading || entry!.planLoading) {
      return const TreinoListRow(title: '', loading: true);
    }

    final e = entry!;
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final profileAsync = ref.watch(userPublicProfileProvider(e.link.athleteId));
    final profile = profileAsync.valueOrNull;
    final displayName = profile?.displayName ?? 'Alumno'; // i18n: Fase W2
    final avatarUrl = profile?.avatarUrl;
    final plan = e.plan;

    final subtitle = plan != null
        ? 'Con plan · ${plan.meals.length} comidas · actualizado ${_relativeTime(plan.updatedAt)}' // i18n: Fase W2
        : 'Sin plan todavía'; // i18n: Fase W2

    return TreinoListRow(
      leading: Semantics(
        image: true,
        label: l10n.a11yAvatarLabel(displayName),
        child: PostAvatar(
          authorDisplayName: displayName,
          authorAvatarUrl: avatarUrl,
          size: 40,
        ),
      ),
      title: displayName,
      subtitle: subtitle,
      trailing:
          Icon(TreinoIcon.chevronRight, size: 18, color: palette.textMuted),
      onTap: onTap,
    );
  }
}

/// Tiempo relativo desde [updatedAt] — mismo formato que `solicitud_card.dart`
/// (`_relativeTime`), duplicado intencional: helper privado trivial de una
/// línea por rama, no un widget del kit.
String _relativeTime(DateTime updatedAt) {
  final delta = DateTime.now().difference(updatedAt);
  if (delta.inMinutes < 1) return 'recién';
  if (delta.inHours < 1) return 'hace ${delta.inMinutes}m';
  if (delta.inDays < 1) return 'hace ${delta.inHours}h';
  if (delta.inDays < 7) return 'hace ${delta.inDays}d';
  final d = updatedAt.day.toString().padLeft(2, '0');
  final m = updatedAt.month.toString().padLeft(2, '0');
  return '$d/$m';
}
