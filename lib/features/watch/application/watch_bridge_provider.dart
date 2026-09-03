import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/treino_link.dart';
import '../data/watch_bridge.dart';

/// Envoltorio sobre `WatchConnectivity`. Se sobreescribe en tests vía
/// `ProviderScope.overrides`.
///
/// Vive en un archivo PROPIO y no junto al servicio de credencial del teléfono
/// porque lo consumen las dos apps, y sólo una de ellas quiere las
/// dependencias de la otra: `watch_credential_providers.dart` arrastra
/// `cloud_functions` y el perfil del usuario, que en el companion de Wear no
/// pintan nada. Compartir la instancia sin compartir ese equipaje es todo el
/// motivo de este archivo.
final watchBridgeProvider = Provider<WatchBridge>((ref) => WatchBridge());

/// Canal propio con el otro dispositivo. Se sobreescribe en tests.
///
/// Convive con [watchBridgeProvider] y no lo reemplaza: el puente sigue siendo
/// el que transporta la credencial y el contexto. Este canal existe para los
/// avisos que tienen que llegar **con la app cerrada**, que es justo lo que el
/// otro no puede hacer. Ver [TreinoLink].
final treinoLinkProvider = Provider<TreinoLink>((ref) => TreinoLink());
