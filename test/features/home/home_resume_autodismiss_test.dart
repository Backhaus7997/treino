import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/home/home_screen.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/l10n/app_l10n.dart';

UserProfile _profile() => UserProfile(
      uid: 'u1',
      email: 'u1@test.com',
      displayName: 'Martín',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2026, 5, 12),
      updatedAt: DateTime.utc(2026, 5, 12),
    );

Session _session() => Session(
      id: 'stub-session-001',
      uid: 'u1',
      routineId: 'r1',
      routineName: 'Push',
      startedAt: DateTime.utc(2026, 5, 18, 18, 42),
      status: SessionStatus.active,
      dayNumber: 1,
    );

/// El atleta arranca el entreno DESDE EL RELOJ y lo termina desde ahí, sin
/// tocar nunca el teléfono.
///
/// Antes de este arreglo el modal quedaba abierto sobre una sesión que ya no
/// existía, y como es `barrierDismissible: false` el atleta quedaba encerrado:
/// CONTINUAR daba pantalla en blanco (`StateError` en `_buildResume`) y
/// DESCARTAR le pisaba los totales a un entreno YA TERMINADO, dejándolo sin
/// contar. Se reportó como "se borra del historial".
void main() {
  testWidgets(
      'el modal de retomar se cierra solo cuando el reloj termina la sesión',
      (tester) async {
    final activa = StateProvider<bool>((ref) => true);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileProvider.overrideWith((ref) => Stream.value(_profile())),
          activeSessionForUidProvider.overrideWith((ref) async {
            // El reloj termina el entreno → `getActive` deja de devolverla.
            if (!ref.watch(activa)) return null;
            return (session: _session(), setLogs: <SetLog>[]);
          }),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          home: const Scaffold(body: HomeScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Con el entreno corriendo en la muñeca, el aviso es correcto.
    expect(find.text('Entrenamiento en curso'), findsOneWidget);

    // El reloj lo termina.
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    );
    container.read(activa.notifier).state = false;
    await tester.pumpAndSettle();

    // El modal ya no tiene sujeto: se cierra solo, sin dejar al atleta
    // encerrado con dos botones destructivos.
    expect(find.text('Entrenamiento en curso'), findsNothing);
  });
}
