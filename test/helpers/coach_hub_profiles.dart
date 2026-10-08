import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';

/// PF con el perfil COMPLETO, tal como lo ve el Coach Hub cuando no hay nada
/// que completar: `hubOnboardingStage(...) == HubOnboardingStage.done`.
///
/// Usalo en todo test que NO trate del onboarding del Hub y necesite un
/// trainer logueado: el gate de `/completar-perfil` deja pasar a este perfil,
/// así que las aserciones del redirect, el shell y el dashboard siguen
/// midiendo lo que midieron siempre.
///
/// Los parámetros sólo cubren lo que cambia entre suites (identidad y
/// `onboardingSeen`); los campos que hacen "completo" al perfil no se
/// parametrizan a propósito, para que nadie lo vuelva incompleto sin querer.
///
/// `bornAt` va en UTC y lejos del borde de los 13 años: no depende del reloj
/// ni de la zona horaria de quien corre el test.
UserProfile trainerCompleto({
  String uid = 'test-uid',
  String email = 'trainer@example.com',
  String displayName = 'Mateo',
  Map<String, int> onboardingSeen = const <String, int>{},
}) {
  return UserProfile(
    uid: uid,
    email: email,
    displayName: displayName,
    role: UserRole.trainer,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
    onboardingSeen: onboardingSeen,
    bornAt: DateTime.utc(1990, 1, 1),
    trainerBio: 'Entreno fuerza e hipertrofia hace diez años.',
    trainerSpecialty: 'strength',
    trainerMonthlyRate: 20000,
    trainerOffersOnline: true,
  );
}

/// PF recién promovido desde la web: sin `bornAt` ni perfil profesional.
/// `hubOnboardingStage(...) == HubOnboardingStage.age`.
UserProfile trainerRecienPromovido({
  String uid = 'test-uid',
  String email = 'trainer@example.com',
  String displayName = 'Mateo',
}) {
  return UserProfile(
    uid: uid,
    email: email,
    displayName: displayName,
    role: UserRole.trainer,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}
