import 'package:flutter/material.dart';
import 'package:treino/app/theme/tokens/primitives.dart';

import '../list_row/list_row.dart';

/// Estado de carga con la FORMA de lo que viene, en vez de un spinner.
///
/// ─── Por qué no un `CircularProgressIndicator` ─────────────────────────────
///
/// Un spinner dice "esperá" y nada más. No dice cuánto va a ocupar lo que
/// llega, así que cuando llegan los datos el layout salta: el spinner medía 36
/// px y la lista mide 400. El shimmer ya ocupa el lugar, y el salto no existe.
///
/// Es la conclusión a la que llegó el dashboard cuando sacó los suyos: «todo
/// estado de carga pasa por el shimmer del kit».
///
/// ─── Cuándo NO usar esto ──────────────────────────────────────────────────
///
/// Un spinner sigue siendo correcto en dos casos, y cambiarlos por reflejo
/// empeora la pantalla:
///
/// - **Adentro de un botón**, mientras una acción puntual está en curso. Ahí
///   el usuario ya sabe qué está esperando: tocó él.
/// - **Cuando el progreso es DETERMINADO** —la descarga de una imagen, por
///   ejemplo—. Ese spinner lleva información que un shimmer esconde.
class CoachHubSkeleton extends StatelessWidget {
  const CoachHubSkeleton({super.key, this.filas = 5, this.padding});

  /// Cuántas filas dibujar. El default llena un panel sin parecer una lista
  /// corta que ya terminó de cargar.
  final int filas;

  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.all(AppSpacing.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < filas; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.s8),
            const TreinoListRow(title: '', loading: true),
          ],
        ],
      ),
    );
  }
}
