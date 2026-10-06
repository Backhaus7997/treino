import 'package:cloud_firestore/cloud_firestore.dart'
    show FirebaseFirestore, Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/gyms/application/gym_name_prompt_providers.dart';
import 'package:treino/features/gyms/application/gym_providers.dart';
import 'package:treino/features/gyms/application/places_providers.dart';
import 'package:treino/features/gyms/data/gym_repository.dart';
import 'package:treino/features/gyms/data/resolve_gym_place_service.dart';
import 'package:treino/features/gyms/presentation/gym_name_prompt_card.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

class _MockUserRepository extends Mock implements UserRepository {}

/// Simula la carrera: otro usuario nombra el gym entre nuestro `getById` y
/// nuestro `update`; la regla niega el nuestro.
class _LosingRaceGymRepository extends GymRepository {
  _LosingRaceGymRepository({required super.firestore, required this.winner})
      : _fs = firestore;
  final String winner;
  final FirebaseFirestore _fs;

  @override
  Future<void> setName(String gymId, String name) async {
    await _fs
        .collection('gyms')
        .doc(gymId)
        .update({'name': winner, 'nameNeeded': false});
    throw Exception('permission-denied');
  }
}

UserProfile _profile({String? gymId, UserRole role = UserRole.athlete}) =>
    UserProfile(
      uid: 'u1',
      email: 'u1@test.com',
      displayName: 'Ana',
      role: role,
      createdAt: DateTime.utc(2026, 5, 12),
      updatedAt: DateTime.utc(2026, 5, 12),
      gymId: gymId,
    );

Map<String, Object?> _gymDoc({required bool nameNeeded, String? name}) => {
      'name': name ?? 'Gimnasio',
      if (nameNeeded) 'nameNeeded': true,
      'lat': -34.5,
      'lng': -58.4,
      'geohash': '6d6m7',
      'source': 'google-places',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
    };

void main() {
  late FakeFirebaseFirestore firestore;
  late _MockUserRepository userRepo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    userRepo = _MockUserRepository();
    when(() => userRepo.update(any(), any())).thenAnswer((_) async {});
  });

  Future<void> pump(
    WidgetTester tester, {
    required Stream<UserProfile?> profile,
    GymRepository? gymRepo,
  }) async {
    final repo = gymRepo ?? GymRepository(firestore: firestore);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileProvider.overrideWith((ref) => profile),
          currentUidProvider.overrideWithValue('u1'),
          userRepositoryProvider.overrideWithValue(userRepo),
          gymRepositoryProvider.overrideWithValue(repo),
          resolveGymPlaceServiceProvider.overrideWithValue(
            ResolveGymPlaceService(
              gymRepository: repo,
              httpClient: http.Client(),
              clientApiKey: 'test',
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          home: const Scaffold(body: GymNamePromptCard()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> seed({required bool nameNeeded, String? name}) => firestore
      .collection('gyms')
      .doc('g1')
      .set(_gymDoc(nameNeeded: nameNeeded, name: name));

  final title = find.text('Tu gimnasio necesita un nombre');
  final cta = find.text('PONERLE NOMBRE');

  testWidgets('se muestra cuando el gym vinculado está nameNeeded',
      (tester) async {
    await seed(nameNeeded: true);
    await pump(tester, profile: Stream.value(_profile(gymId: 'g1')));
    expect(title, findsOneWidget);
    expect(cta, findsOneWidget);
  });

  testWidgets('también se muestra a un entrenador', (tester) async {
    await seed(nameNeeded: true);
    await pump(
      tester,
      profile: Stream.value(_profile(gymId: 'g1', role: UserRole.trainer)),
    );
    expect(title, findsOneWidget);
  });

  testWidgets('se oculta si el gym ya tiene nombre', (tester) async {
    await seed(nameNeeded: false, name: 'Iron Box');
    await pump(tester, profile: Stream.value(_profile(gymId: 'g1')));
    expect(title, findsNothing);
  });

  testWidgets('se oculta sin gym', (tester) async {
    await pump(tester, profile: Stream.value(_profile()));
    expect(title, findsNothing);
  });

  testWidgets('se oculta mientras carga', (tester) async {
    await pump(tester, profile: const Stream<UserProfile?>.empty());
    expect(title, findsNothing);
  });

  testWidgets('se oculta ante un error', (tester) async {
    await pump(
      tester,
      profile: Stream<UserProfile?>.error(Exception('boom')),
    );
    expect(title, findsNothing);
  });

  testWidgets('"Ahora no" lo oculta por la sesión', (tester) async {
    await seed(nameNeeded: true);
    await pump(tester, profile: Stream.value(_profile(gymId: 'g1')));
    await tester.tap(find.text('Ahora no'));
    await tester.pump();
    expect(title, findsNothing);
  });

  testWidgets('el CTA abre el diálogo para nombrar', (tester) async {
    await seed(nameNeeded: true);
    await pump(tester, profile: Stream.value(_profile(gymId: 'g1')));
    await tester.tap(cta);
    await tester.pumpAndSettle();
    expect(find.text('Ponele nombre a tu gimnasio'), findsOneWidget);
    expect(find.byKey(const Key('gym-name-field')), findsOneWidget);
  });

  testWidgets('cancelar el diálogo no escribe nada y deja la card',
      (tester) async {
    await seed(nameNeeded: true);
    await pump(tester, profile: Stream.value(_profile(gymId: 'g1')));
    await tester.tap(cta);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gym-name-cancel')));
    await tester.pumpAndSettle();
    final data = (await firestore.collection('gyms').doc('g1').get()).data()!;
    expect(data['nameNeeded'], true);
    expect(title, findsOneWidget);
  });

  testWidgets('guardar escribe el nombre y la card desaparece en vivo',
      (tester) async {
    await seed(nameNeeded: true);
    await pump(tester, profile: Stream.value(_profile(gymId: 'g1')));
    await tester.tap(cta);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('gym-name-field')), ' Iron Box ');
    await tester.pump();
    await tester.tap(find.byKey(const Key('gym-name-confirm')));
    await tester.pumpAndSettle();

    final data = (await firestore.collection('gyms').doc('g1').get()).data()!;
    expect(data['name'], 'Iron Box');
    expect(data['nameNeeded'], false);
    // Re-escribe el gymId para que `users/{uid}.gymName` se resuelva.
    final writes = verify(() => userRepo.update('u1', captureAny())).captured;
    expect(writes, isNotEmpty);
    expect(writes.last, {'gymId': 'g1'});
    expect(title, findsNothing);
  });

  testWidgets(
      'un nombre bloqueado por moderación muestra el aviso y no escribe',
      (tester) async {
    await seed(nameNeeded: true);
    await pump(tester, profile: Stream.value(_profile(gymId: 'g1')));
    await tester.tap(cta);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('gym-name-field')), 'puta madre');
    await tester.pump();
    await tester.tap(find.byKey(const Key('gym-name-confirm')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Normas de Comunidad'), findsOneWidget);
    expect(find.textContaining('No pudimos guardar el gimnasio'), findsNothing);
    verifyNever(() => userRepo.update(any(), any()));
    final data = (await firestore.collection('gyms').doc('g1').get()).data()!;
    expect(data['nameNeeded'], true);
    expect(title, findsOneWidget);
  });

  testWidgets(
      'si otro lo nombró primero, muestra el nombre ganador y se oculta',
      (tester) async {
    await seed(nameNeeded: true);
    await pump(
      tester,
      profile: Stream.value(_profile(gymId: 'g1')),
      gymRepo: _LosingRaceGymRepository(
        firestore: firestore,
        winner: 'Gimnasio Ganador',
      ),
    );
    await tester.tap(cta);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('gym-name-field')), 'Mi nombre');
    await tester.pump();
    await tester.tap(find.byKey(const Key('gym-name-confirm')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Gimnasio Ganador'), findsOneWidget);
    expect(title, findsNothing);
  });

  testWidgets('un error de red al guardar avisa y deja la card',
      (tester) async {
    await seed(nameNeeded: true);
    when(() => userRepo.update(any(), any())).thenThrow(Exception('offline'));
    await pump(tester, profile: Stream.value(_profile(gymId: 'g1')));
    await tester.tap(cta);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('gym-name-field')), 'Iron Box');
    await tester.pump();
    await tester.tap(find.byKey(const Key('gym-name-confirm')));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('No pudimos guardar el gimnasio'), findsOneWidget);
  });

  test('el descarte es por uid: A descartó, B sigue viendo el aviso', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    expect(c.read(gymNamePromptDismissedProvider('A')), isFalse);
    c.read(gymNamePromptDismissedProvider('A').notifier).state = true;
    expect(c.read(gymNamePromptDismissedProvider('A')), isTrue);
    expect(c.read(gymNamePromptDismissedProvider('B')), isFalse);
  });

  testWidgets('A descarta, cambia la cuenta a B: B ve el aviso',
      (tester) async {
    await seed(nameNeeded: true);
    final uid = StateProvider<String?>((ref) => 'u1');
    final container = ProviderContainer(overrides: [
      userProfileProvider
          .overrideWith((ref) => Stream.value(_profile(gymId: 'g1'))),
      currentUidProvider.overrideWith((ref) => ref.watch(uid)),
      gymRepositoryProvider
          .overrideWithValue(GymRepository(firestore: firestore)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          home: const Scaffold(body: GymNamePromptCard()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Ahora no'));
    await tester.pump();
    expect(title, findsNothing);

    container.read(uid.notifier).state = 'u2';
    await tester.pump();
    await tester.pump();
    expect(title, findsOneWidget);
  });

  testWidgets('a 320dp con textScaler 2.0 no desborda y ambas acciones se ven',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await seed(nameNeeded: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileProvider
              .overrideWith((ref) => Stream.value(_profile(gymId: 'g1'))),
          currentUidProvider.overrideWithValue('u1'),
          gymRepositoryProvider
              .overrideWithValue(GymRepository(firestore: firestore)),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child!,
          ),
          home: const Scaffold(
              body: SingleChildScrollView(
            child: GymNamePromptCard(),
          )),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('gym_name_prompt_dismiss')), findsOneWidget);
    expect(find.byKey(const Key('gym_name_prompt_cta')), findsOneWidget);
  });
}
