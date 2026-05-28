import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/coach/domain/trainer_location.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/presentation/widgets/profile_trainer_section.dart';

class _MockUser extends Mock implements User {}

User _userWithUid(String uid) {
  final u = _MockUser();
  when(() => u.uid).thenReturn(uid);
  return u;
}

UserProfile _trainer({
  String? bio,
  String? specialty,
  List<TrainerLocation> locations = const [],
  bool offersOnline = false,
  int? rate,
}) =>
    UserProfile(
      uid: 'test-uid',
      email: 'pf@example.com',
      displayName: 'Mateo PF',
      role: UserRole.trainer,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
      trainerBio: bio,
      trainerSpecialty: specialty,
      trainerMonthlyRate: rate,
      trainerLocations: locations,
      trainerGeohashes: locations.map((l) => l.geohash).toList(),
      trainerOffersOnline: offersOnline,
    );

TrainerLocation _customLoc({String label = 'Mi estudio'}) =>
    TrainerLocation(
      id: 'loc-1',
      type: TrainerLocationType.custom,
      customLabel: label,
      lat: -31.4,
      lng: -64.1,
      geohash: '6d6m7',
    );

UserProfile _athlete() => UserProfile(
      uid: 'test-uid',
      email: 'a@example.com',
      displayName: 'Atleta',
      role: UserRole.athlete,
      createdAt: DateTime(2025),
      updatedAt: DateTime(2025),
    );

Widget _pump({required List<Override> overrides}) {
  final router = GoRouter(
    initialLocation: '/profile',
    routes: [
      GoRoute(
        path: '/profile',
        builder: (_, __) => const Scaffold(
          body: SingleChildScrollView(child: ProfileTrainerSection()),
        ),
        routes: [
          GoRoute(
            path: 'edit-trainer',
            builder: (_, __) => const Scaffold(body: Text('EDIT_TRAINER')),
          ),
        ],
      ),
    ],
  );

  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      routerConfig: router,
    ),
  );
}

void main() {
  group('ProfileTrainerSection', () {
    testWidgets('NO renderiza nada cuando role == athlete', (tester) async {
      await tester.pumpWidget(_pump(overrides: [
        authStateChangesProvider
            .overrideWith((ref) => Stream.value(_userWithUid('test-uid'))),
        userProfileProvider
            .overrideWith((ref) => Stream.value(_athlete())),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('ENTRENADOR'), findsNothing);
      expect(find.text('Mi perfil de entrenador'), findsNothing);
    });

    testWidgets('renderiza header + tile cuando role == trainer',
        (tester) async {
      await tester.pumpWidget(_pump(overrides: [
        authStateChangesProvider
            .overrideWith((ref) => Stream.value(_userWithUid('test-uid'))),
        userProfileProvider.overrideWith(
          (ref) => Stream.value(_trainer(
            bio: 'mi bio entrenando',
            specialty: 'hipertrofia',
            locations: [_customLoc()],
            rate: 7000,
          )),
        ),
      ]));
      await tester.pumpAndSettle();

      expect(find.text('ENTRENADOR'), findsOneWidget);
      expect(find.text('Mi perfil de entrenador'), findsOneWidget);
      expect(
        find.text('Perfil completo · visible en Discovery'),
        findsOneWidget,
      );
    });

    testWidgets('subtitle lista campos faltantes cuando hay alguno vacío',
        (tester) async {
      await tester.pumpWidget(_pump(overrides: [
        authStateChangesProvider
            .overrideWith((ref) => Stream.value(_userWithUid('test-uid'))),
        userProfileProvider.overrideWith(
          // Sin bio, sin specialty, sin lat, sin rate.
          (ref) => Stream.value(_trainer()),
        ),
      ]));
      await tester.pumpAndSettle();

      final subtitle = find.textContaining('Faltan:');
      expect(subtitle, findsOneWidget);
      // Los 4 campos faltantes deberían listarse.
      final text = tester.widget<Text>(subtitle).data!;
      expect(text, contains('bio'));
      expect(text, contains('especialidad'));
      expect(text, contains('ubicación'));
      expect(text, contains('precio'));
    });

    testWidgets('tap navega a /profile/edit-trainer', (tester) async {
      await tester.pumpWidget(_pump(overrides: [
        authStateChangesProvider
            .overrideWith((ref) => Stream.value(_userWithUid('test-uid'))),
        userProfileProvider.overrideWith(
          (ref) => Stream.value(_trainer()),
        ),
      ]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Mi perfil de entrenador'));
      await tester.pumpAndSettle();

      expect(find.text('EDIT_TRAINER'), findsOneWidget);
    });
  });
}
