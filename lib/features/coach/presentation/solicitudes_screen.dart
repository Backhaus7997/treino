import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/motion/treino_tappable.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import 'trainer_dashboard_tab.dart';

/// Pantalla de solicitudes de vinculación pendientes del PF.
///
/// ## Por qué existe
///
/// El push de `nueva_solicitud` apuntaba a `/coach`, que en mobile abre la
/// pestaña ALUMNOS — o sea, la lista de los que YA están vinculados. El PF
/// tocaba el aviso de una solicitud nueva y caía en una pantalla que no la
/// menciona. Hasta acá las pendientes sólo se podían ver desde la campana del
/// dashboard, que abre un bottom sheet: no hay ruta que lleve ahí, así que
/// ningún deep link podía apuntarle.
///
/// No tiene [Scaffold] propio: se apoya en el shell del router, igual que
/// `FriendRequestsInboxScreen`.
///
/// El contenido es [PendingRequestsView] con `cerrarAlVaciarse: false`. El
/// modal se cierra solo al quedar vacío, que acá sería sacarle la pantalla de
/// abajo de los pies al PF justo después de aceptar la última solicitud.
class SolicitudesScreen extends ConsumerWidget {
  const SolicitudesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Row(
            children: [
              Semantics(
                button: true,
                label: l10n.commonBack,
                child: TreinoTappable(
                  // `context.pop()` a secas no sirve acá: el deep link entra
                  // con `go`, que REEMPLAZA la pila, así que al llegar desde
                  // la notificación no hay nada que popear y la flecha sería
                  // un botón muerto. Ver `goDeepLink`.
                  onTap: () =>
                      context.canPop() ? context.pop() : context.go('/home'),
                  child: Container(
                    constraints:
                        const BoxConstraints(minWidth: 44, minHeight: 44),
                    alignment: Alignment.centerLeft,
                    child: Icon(
                      TreinoIcon.back,
                      size: 20,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // El título con el conteo lo pone `PendingRequestsView`, así que la
        // fila de arriba lleva sólo la flecha: dos encabezados apilados
        // diciendo casi lo mismo es ruido.
        // Sin `SingleChildScrollView` acá: `PendingRequestsView` ya trae el
        // suyo, y anidar dos deja la altura sin acotar.
        const Expanded(
          child: PendingRequestsView(cerrarAlVaciarse: false),
        ),
      ],
    );
  }
}
