import '../../profile/domain/user_profile.dart';
import '../../profile/domain/user_role.dart';

/// Cuánto tiempo después de crear la cuenta se la sigue considerando «recién
/// creada» para «Me equivoqué de mail».
///
/// 24 h porque es la espera más larga que impone el backend entre códigos (el
/// tope de envíos): quien se registró con un mail mal tipeado y se trabó
/// esperando un código que nunca le llega tiene que poder salir dentro de ese
/// plazo. Más allá, la cuenta ya no es un alta en curso sino una cuenta que
/// existe hace días, y para borrarla está el flujo normal (con reautenticación
/// y las advertencias de alumnos, datos guardados, etc.).
const ventanaAltaReciente = Duration(hours: 24);

/// Cuánto puede estar atrasado el reloj del teléfono respecto del de Firebase
/// Auth sin que un alta recién hecha deje de contar como tal.
const toleranciaDeReloj = Duration(minutes: 10);

/// Si la cuenta es, comprobadamente, un alta recién creada que todavía no
/// confirmó NINGÚN mail: la única a la que se le puede ofrecer «Me equivoqué de
/// mail», que borra la cuenta entera SIN reautenticar.
///
/// `VerifyMailScreen` no la ven solo las altas. El router también manda ahí a
/// cuentas establecidas:
/// - un alumno verificado que el equipo PROMUEVE a entrenador (la entrada de
///   `emailVerification` es por rol);
/// - una cuenta a la que se le CAMBIÓ el mail en Auth (la entrada guarda el mail);
/// - TODAS las cuentas viejas sin verificar el día que se prende
///   `app_config/email_gate`.
/// Borrarle la cuenta a cualquiera de esas por un botón de «me equivoqué» sería
/// irreversible. Por eso exige las tres cosas, y falla CERRADO:
///
/// 1. [creadaEn] (`User.metadata.creationTime`, lo pone Firebase Auth en el
///    servidor) dentro de [ventanaAltaReciente]. Es lo que deja afuera a las
///    cuentas viejas del día del interruptor. Nulo ⇒ `false`. Se toleran unos
///    minutos «en el futuro» ([toleranciaDeReloj]) porque se compara contra el
///    reloj del teléfono, que puede estar atrasado respecto del servidor.
/// 2. Rol alumno: el alta de la app crea alumnos; un entrenador llegó por
///    promoción, o sea, es una cuenta con historia.
/// 3. `emailVerification` vacío: nunca confirmó ningún mail, para ningún rol.
///    Deja afuera la promoción y el cambio de mail, que ya tenían una entrada.
///
/// [profile] nulo (cargando, sin documento o con error) ⇒ `false`.
bool esAltaRecienCreada({
  required UserProfile? profile,
  required DateTime? creadaEn,
  required DateTime ahora,
}) {
  if (profile == null || creadaEn == null) return false;
  final antiguedad = ahora.difference(creadaEn);
  if (antiguedad < -toleranciaDeReloj || antiguedad >= ventanaAltaReciente) {
    return false;
  }
  if (profile.role != UserRole.athlete) return false;
  return profile.emailVerification.isEmpty;
}
