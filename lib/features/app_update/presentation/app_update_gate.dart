import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/app_update_providers.dart';
import 'update_required_screen.dart';

/// Envuelve a TODA la app (se monta en el `builder` de `MaterialApp.router`,
/// arriba del Navigator). Si la versión instalada es menor que la mínima de
/// `app_config/min_version`, reemplaza lo de abajo por [UpdateRequiredScreen].
///
/// Por qué un wrapper y no un `redirect` del router: el router tiene DOS gates
/// de perfil completo y varios redirects que se pisan entre sí; un destino más
/// ahí arriesga loops. Esto no toca el router ni su estado: mientras carga, o
/// ante cualquier fallo, devuelve [child] sin cambios (falla abierto — ver
/// `minVersionConfigProvider`). Solo mobile: en web/relojes el provider de
/// plataforma es `null` y nunca se lee Firestore.
class AppUpdateGate extends ConsumerWidget {
  const AppUpdateGate({
    super.key,
    required this.child,
    this.abrirUrl,
  });

  final Widget child;

  /// Seam de tests para no lanzar la tienda de verdad.
  final Future<bool> Function(Uri url)? abrirUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final req = ref.watch(updateRequirementProvider);
    if (req == null) return child;
    final abrir = abrirUrl;
    return abrir == null
        ? UpdateRequiredScreen(storeUrl: req.storeUrl)
        : UpdateRequiredScreen(storeUrl: req.storeUrl, abrirUrl: abrir);
  }
}
