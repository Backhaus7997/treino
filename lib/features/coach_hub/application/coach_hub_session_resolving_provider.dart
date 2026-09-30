import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_role.dart';

/// `true` mientras el Coach Hub NO tiene confirmado que quien entró es un PF:
/// la sesión de auth o el perfil siguen cargando, o el router está sacando a
/// esta sesión del shell (sin sesión → `/login`, un no-PF → `/not-allowed`).
///
/// Sólo un PF con el perfil resuelto se queda en el shell. Para cualquier otra
/// sesión, lo que dibuje el shell sobra o miente.
///
/// **Para qué existe.** En un teléfono, mientras el router esperaba la sesión se
/// quedaba en `/dashboard` (`kCoachHubInitialLocation`) y ese `/dashboard`
/// dibujaba el `MobileBanner` («Coach Hub en escritorio… usá la app»); recién
/// al resolverse el redirect aparecía la pantalla de planes. Quien tocaba el
/// link del mail del tope veía primero un cartel que le decía que se fuera.
/// `CoachHubScaffold` consulta este provider para poner una vista de carga
/// donde iría el banner.
///
/// **Las dos esperas espejan `coachHubRedirect`** (`lib/app/coach_hub_router.dart`),
/// que devuelve `null` mientras auth o el perfil están en `isLoading`. Cualquier
/// cambio en cuándo espera el redirect tiene que mirar esta regla.
///
/// **Por qué "está saliendo del shell" también cuenta como resolviendo.** Cuando
/// el redirect manda a la sesión a `/login` o a `/not-allowed`, la página del
/// shell no desaparece de golpe: el `Navigator` la sigue dibujando DEBAJO de la
/// página que entra hasta que termina la transición de ruta. Con la sesión ya
/// resuelta (anónima, atleta) ese shell mostraba el banner en esos frames — se
/// vio midiendo cada frame en `test/app/coach_hub_router_resolving_test.dart`.
/// Mientras la sesión no sea la de un PF, lo que queda debajo es la vista de
/// carga.
///
/// **Por qué un provider y no un flag calculado en el router**, como
/// `mobileFacturacionAllowed`. Ese sale de `state.uri.path`, así que cambia
/// cuando cambia la ruta y go_router reconstruye la página. La sesión que se
/// resuelve NO cambia la ruta —un PF sin destino fino sigue en `/dashboard`—, y
/// ante un refresh sin cambio de ubicación go_router re-evalúa el `redirect`
/// pero NO vuelve a invocar el `pageBuilder` del `ShellRoute` (verificado: 1
/// invocación antes y después). Un valor calculado ahí quedaría congelado en
/// "resolviendo" y el teléfono no saldría nunca de la carga. Un provider que el
/// scaffold observa se reconstruye solo cuando el estado cambia, sin depender
/// de la ruta.
///
/// **Qué NO cuenta como resolviendo:** un error de auth sin valor. No es una
/// espera sino un estado terminal (el redirect tampoco actúa), y una carga
/// eterna sería peor que el banner de antes.
final coachHubSessionResolvingProvider = Provider<bool>((ref) {
  final auth = ref.watch(authNotifierProvider);
  if (auth.isLoading) return true;
  if (!auth.hasValue) return false; // error de auth: terminal, ver arriba.

  // Sin sesión: el redirect manda a `/login`. No se mira el perfil —
  // `userProfileProvider` resuelve solo en `null`— porque ya está decidido.
  if (auth.valueOrNull == null) return true;

  final profile = ref.watch(userProfileProvider);
  if (profile.isLoading) return true;

  // Un atleta, o un perfil ausente, va a `/not-allowed` (defensivo, igual que
  // el redirect).
  return profile.valueOrNull?.role != UserRole.trainer;
});
