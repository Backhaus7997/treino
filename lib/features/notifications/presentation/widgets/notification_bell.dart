import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_badge.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../application/notification_history_providers.dart';

/// Campana del centro de notificaciones, con su badge de no vistas.
///
/// ## Por qué existe como widget y no como otra copia
///
/// La app llegó a tener CUATRO campanas —feed, dashboard del PF, perfil del PF
/// y la de adentro del propio historial—, cada una con su propio tap y su
/// propio criterio de badge. Dos de ellas prometían cosas parecidas y llevaban
/// a lugares distintos, que es la forma más rápida de que la gente deje de
/// confiar en el ícono.
///
/// Ésta es una sola, vive en la pantalla principal, y siempre lleva al mismo
/// lado. El [tab] elige con qué sub-pestaña abre.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key, this.size = 22});

  /// Tamaño del ícono. El área tapeable NO se achica con él: se mantiene en
  /// 44×44, el mínimo de la HIG, porque encogerla fue una regresión de
  /// accesibilidad la última vez que alguien la ató al tamaño visual.
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final uid = ref.watch(currentUidProvider);
    final badge =
        uid == null ? 0 : ref.watch(notificationHeaderBadgeProvider(uid));

    return Semantics(
      // `container: true`: sin esto la anotación se fusiona con el nodo del
      // header y el lector de pantalla canta el conteo pegado al saludo, en
      // vez de anunciarlo como su propio control.
      container: true,
      button: true,
      label: badge > 0
          ? l10n.notificationBellWithCountA11y(badge)
          : l10n.notificationBellA11y,
      child: GestureDetector(
        onTap: () => context.push('/home/notifications'),
        behavior: HitTestBehavior.opaque,
        child: ExcludeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(TreinoIcon.bell, size: size, color: palette.textPrimary),
                  if (badge > 0)
                    // `-4`: el badge se monta sobre la esquina del ícono. No es
                    // spacing de layout —no separa nada— así que no entra en la
                    // escala; es un offset de superposición.
                    Positioned(
                      right: -4,
                      top: -4,
                      child: TreinoBadge(count: badge),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
