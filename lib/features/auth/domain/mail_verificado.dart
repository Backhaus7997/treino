import '../../profile/domain/user_profile.dart';
import '../../profile/domain/user_role.dart';

/// Si [profile] confirmó con el código de 6 dígitos el mail que Firebase Auth
/// tiene HOY ([authEmail]), para el rol que la cuenta tiene HOY.
///
/// Espeja `verificadoParaSuRol` de `functions/src/auth/codigo-de-verificacion.ts`:
/// la regla vive en dos lenguajes y tiene que decir lo mismo.
///
/// - **Por rol**: `emailVerification` guarda una entrada por rol. Un alumno que
///   el equipo promueve a entrenador vuelve a ver la pantalla del código, porque
///   el mail que le llega es el del entrenador (el que dice dónde paga un PF) y
///   la entrada de alumno no cuenta.
/// - **Con el mail adentro**: si el equipo le cambia el correo en Auth, el nuevo
///   todavía no lo abrió nadie. Auth y lo guardado se comparan sin mayúsculas ni
///   espacios: `Ana@Test.com ` y `ana@test.com` son el mismo mail.
///
/// [authEmail] nulo o en blanco devuelve `true`: no hay a dónde mandar el
/// código (el backend contesta `sin-email`), y frenar a esa cuenta la dejaría
/// atrapada en una pantalla que no puede completar. No pasa con los métodos de
/// ingreso de hoy (mail, Google, Apple); es la salida segura si algún día pasa.
bool correoVerificadoParaElRol(UserProfile profile, String? authEmail) {
  final actual = _normalizar(authEmail);
  if (actual.isEmpty) return true;

  final confirmado = _normalizar(
    profile.emailVerification[profile.role.toJson()]?.email,
  );
  return confirmado.isNotEmpty && confirmado == actual;
}

String _normalizar(String? email) => email?.trim().toLowerCase() ?? '';
