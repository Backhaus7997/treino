import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/auth/domain/mail_verificado.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/domain/verified_email.dart';

// La misma regla que `verificadoParaSuRol` en
// `functions/src/auth/codigo-de-verificacion.ts`: si una cambia, cambia la otra.

VerifiedEmail _entrada(String email) =>
    VerifiedEmail(email: email, verifiedAt: DateTime.utc(2026, 1, 1));

UserProfile _perfil(UserRole rol, Map<String, VerifiedEmail> verificacion) =>
    UserProfile(
      uid: 'u1',
      email: 'ana@test.com',
      displayName: 'ana',
      role: rol,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
      emailVerification: verificacion,
    );

void main() {
  group('correoVerificadoParaElRol', () {
    final casos = <({
      String nombre,
      UserRole rol,
      Map<String, VerifiedEmail> verificacion,
      String? authEmail,
      bool esperado,
    })>[
      (
        nombre: 'sin ninguna entrada',
        rol: UserRole.athlete,
        verificacion: const {},
        authEmail: 'ana@test.com',
        esperado: false,
      ),
      (
        nombre: 'solo la entrada del OTRO rol (el alumno promovido a PF)',
        rol: UserRole.trainer,
        verificacion: {'athlete': _entrada('ana@test.com')},
        authEmail: 'ana@test.com',
        esperado: false,
      ),
      (
        nombre: 'solo la entrada del otro rol, al revés (PF vuelto alumno)',
        rol: UserRole.athlete,
        verificacion: {'trainer': _entrada('ana@test.com')},
        authEmail: 'ana@test.com',
        esperado: false,
      ),
      (
        nombre: 'la entrada es de otro mail que el de Auth',
        rol: UserRole.athlete,
        verificacion: {'athlete': _entrada('vieja@test.com')},
        authEmail: 'ana@test.com',
        esperado: false,
      ),
      (
        nombre: 'el mismo mail con otras mayúsculas y espacios es el mismo',
        rol: UserRole.athlete,
        verificacion: {'athlete': _entrada('  Ana@TEST.com ')},
        authEmail: 'ana@test.com',
        esperado: true,
      ),
      (
        nombre: 'ídem del lado de Auth',
        rol: UserRole.athlete,
        verificacion: {'athlete': _entrada('ana@test.com')},
        authEmail: ' ANA@test.com ',
        esperado: true,
      ),
      (
        nombre: 'coincide: entrada del rol de hoy con el mail de hoy',
        rol: UserRole.trainer,
        verificacion: {
          'athlete': _entrada('ana@test.com'),
          'trainer': _entrada('ana@test.com'),
        },
        authEmail: 'ana@test.com',
        esperado: true,
      ),
      (
        nombre: 'el mail guardado en blanco no confirma nada',
        rol: UserRole.athlete,
        verificacion: {'athlete': _entrada('   ')},
        authEmail: 'ana@test.com',
        esperado: false,
      ),
      (
        nombre: 'Auth sin mail: no hay a dónde mandar el código, no se frena',
        rol: UserRole.athlete,
        verificacion: const {},
        authEmail: null,
        esperado: true,
      ),
      (
        nombre: 'Auth con el mail en blanco: ídem',
        rol: UserRole.athlete,
        verificacion: const {},
        authEmail: '  ',
        esperado: true,
      ),
    ];

    for (final c in casos) {
      test(c.nombre, () {
        expect(
          correoVerificadoParaElRol(
              _perfil(c.rol, c.verificacion), c.authEmail),
          c.esperado,
        );
      });
    }
  });
}
