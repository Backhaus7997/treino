import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/auth/domain/alta_reciente.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

final _ahora = DateTime.utc(2026, 10, 9, 12);

UserProfile _alumno() => UserProfile(
      uid: 'u1',
      email: 'ana@test.com',
      displayName: 'Ana',
      role: UserRole.athlete,
      createdAt: _ahora,
      updatedAt: _ahora,
    );

bool _alta(DateTime? creadaEn) =>
    esAltaRecienCreada(profile: _alumno(), creadaEn: creadaEn, ahora: _ahora);

void main() {
  test('dentro de la ventana cuenta como alta', () {
    expect(
        _alta(_ahora.subtract(const Duration(hours: 23, minutes: 59))), isTrue);
  });

  test('a las 24 h justas ya no', () {
    expect(_alta(_ahora.subtract(ventanaAltaReciente)), isFalse);
  });

  test('reloj del teléfono atrasado unos minutos: sigue contando', () {
    expect(_alta(_ahora.add(const Duration(minutes: 5))), isTrue);
  });

  test('creada «en el futuro» más allá de la tolerancia: no', () {
    expect(_alta(_ahora.add(toleranciaDeReloj + const Duration(seconds: 1))),
        isFalse);
  });

  test('sin fecha de creación: no', () {
    expect(_alta(null), isFalse);
  });
}
