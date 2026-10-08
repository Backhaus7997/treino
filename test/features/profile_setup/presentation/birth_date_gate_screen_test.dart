import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile_setup/presentation/birth_date_gate_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

/// La pantalla del gate de edad no tenía NINGÚN test, y por eso el bug llegó a
/// un usuario: guardar la fecha dejaba la pantalla quieta.
///
/// La causa de fondo era del router —un gate con entrada y sin salida, cubierto
/// en `test/app/router_auth_redirect_test.dart`— pero eso deja una pregunta
/// aparte que estos casos contestan: ¿el botón se destraba solo, o además de no
/// navegar se quedaba cargando para siempre? Son dos fallas distintas y se ven
/// iguales desde el teléfono.

const _uid = 'u1';

class _MockAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

/// Repo que explota al escribir, para el camino de error.
class _RepoQueFalla extends UserRepository {
  _RepoQueFalla({required super.firestore});

  @override
  Future<void> update(
    String uid,
    Map<String, Object?> partial, {
    bool grantLocationConsent = false,
  }) async {
    throw FirebaseException(plugin: 'firestore', code: 'unavailable');
  }
}

UserProfile _perfil({DateTime? bornAt}) => UserProfile(
      uid: _uid,
      email: 'a@b.com',
      displayName: 'martin',
      role: UserRole.athlete,
      createdAt: DateTime.utc(2024, 1, 1),
      updatedAt: DateTime.utc(2024, 1, 1),
      bornAt: bornAt,
    );

/// Monta la pantalla con `userProfileProvider` YA RESUELTO.
///
/// No es comodidad del test: es lo que pasa en produccion. A `/birth-date` se
/// llega por el redirect del router, y ese redirect leyo `userProfileProvider`
/// para decidir mandarte — o sea que cuando la pantalla monta, el provider ya
/// tiene valor.
///
/// Con un `ProviderScope` recien creado el `StreamProvider` arranca en
/// `loading`, el `ref.read` del `initState` ve null, y el campo aparece vacio.
/// Ese arbol no se parece a la app: haria fallar la precarga por un motivo que
/// el usuario nunca vive.
Future<void> montar(
  WidgetTester tester, {
  required FirebaseAuth auth,
  required UserRepository repo,
  required UserProfile perfil,
}) async {
  final container = ProviderContainer(
    overrides: [
      firebaseAuthProvider.overrideWithValue(auth),
      userRepositoryProvider.overrideWithValue(repo),
      userProfileProvider.overrideWith((ref) => Stream.value(perfil)),
    ],
  );
  addTearDown(container.dispose);
  await container.read(userProfileProvider.future);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const BirthDateGateScreen(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late _MockAuth auth;
  late FakeFirebaseFirestore firestore;

  setUp(() {
    auth = _MockAuth();
    final user = _MockUser();
    when(() => user.uid).thenReturn(_uid);
    when(() => auth.currentUser).thenReturn(user);
    firestore = FakeFirebaseFirestore();
  });

  /// Una fecha válida ya cargada precarga `_picked` desde `initState`, así que
  /// el botón arranca habilitado y no hace falta manejar el date picker.
  final valida = DateTime.utc(1990, 5, 20);

  testWidgets('guardar persiste bornAt', (tester) async {
    await firestore.collection('users').doc(_uid).set({'uid': _uid});
    await montar(
      tester,
      auth: auth,
      repo: UserRepository(firestore: firestore),
      perfil: _perfil(bornAt: valida),
    );

    await tester.tap(find.byKey(const Key('birth_date_gate_save')));
    await tester.pumpAndSettle();

    final doc = await firestore.collection('users').doc(_uid).get();
    expect(doc.data()!['bornAt'], isNotNull);
  });

  testWidgets('el botón se destraba después de guardar', (tester) async {
    // Si esto se cae, hay una SEGUNDA falla además de la del router: el usuario
    // se queda con el spinner girando para siempre y ni siquiera puede
    // reintentar. Desde el teléfono las dos se ven igual — "toqué guardar y no
    // pasó nada"— y arreglar una sola dejaría al usuario igual de trabado.
    await firestore.collection('users').doc(_uid).set({'uid': _uid});
    await montar(
      tester,
      auth: auth,
      repo: UserRepository(firestore: firestore),
      perfil: _perfil(bornAt: valida),
    );

    await tester.tap(find.byKey(const Key('birth_date_gate_save')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('birth_date_gate_save')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
      reason: 'el spinner quedó girando después de una escritura exitosa',
    );
  });

  testWidgets('si la escritura falla, muestra el error y destraba el botón',
      (tester) async {
    await montar(
      tester,
      auth: auth,
      repo: _RepoQueFalla(firestore: firestore),
      perfil: _perfil(bornAt: valida),
    );

    await tester.tap(find.byKey(const Key('birth_date_gate_save')));
    await tester.pumpAndSettle();

    expect(find.textContaining('No pudimos guardar'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('birth_date_gate_save')),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
      reason: 'sin destrabar el botón, el usuario no puede ni reintentar',
    );
  });

  testWidgets('precarga la fecha que el perfil ya tiene', (tester) async {
    // A este gate también llega quien cargó en su momento una fecha por debajo
    // del piso. Con el campo vacío no tendría forma de ver cuál es la fecha que
    // lo está trabando.
    await montar(
      tester,
      auth: auth,
      repo: UserRepository(firestore: firestore),
      perfil: _perfil(bornAt: DateTime.utc(2015, 3, 10)),
    );

    expect(find.textContaining('2015'), findsOneWidget);
  });
}
