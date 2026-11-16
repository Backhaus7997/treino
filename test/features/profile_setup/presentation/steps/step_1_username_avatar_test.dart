import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart'
    show firebaseAuthProvider;
import 'package:treino/features/profile/application/user_public_profile_providers.dart'
    show userPublicProfileRepositoryProvider;
import 'package:treino/features/profile/data/user_public_profile_repository.dart';
import 'package:treino/features/profile_setup/application/profile_setup_providers.dart';
import 'package:treino/features/profile_setup/presentation/steps/step_1_username_avatar.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUserPublicProfileRepository extends Mock
    implements UserPublicProfileRepository {}

Widget _wrap(ProviderContainer container) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(body: Step1UsernameAvatar()),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
      ),
    );

void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  // E2E 1.3.0: en iOS el autocorrector cambió `carrilb` por `carrion` al
  // cerrar el teclado. Un @handle no es una palabra del diccionario: ni
  // corrección ni sugerencias.
  testWidgets('el username no pasa por el autocorrector ni las sugerencias',
      (tester) async {
    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
  });

  // #1698: el paso no tiene `Form`, así que el `validator:` nunca corría y
  // SIGUIENTE quedaba apagado sin decir por qué. El formato inválido deja la
  // disponibilidad en `unknown` —ahí tampoco hay fila de estado—, o sea que el
  // mensaje del campo es la ÚNICA explicación.
  group('mensaje de validación', () {
    Future<void> escribir(WidgetTester tester, String texto) async {
      await tester.enterText(find.byType(TextField), texto);
      await tester.pump();
    }

    bool puedeAvanzar() =>
        container.read(profileSetupNotifierProvider).canGoNext;

    testWidgets('sin escribir nada no hay ningún error', (tester) async {
      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      expect(find.text('Ingresá un username'), findsNothing);
      expect(find.text('Mínimo 3 caracteres'), findsNothing);
    });

    testWidgets('muy corto: dice por qué no se puede seguir', (tester) async {
      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      await escribir(tester, 'ab');

      expect(find.text('Mínimo 3 caracteres'), findsOneWidget);
      expect(puedeAvanzar(), isFalse);
    });

    testWidgets('caracteres no permitidos', (tester) async {
      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      await escribir(tester, 'ana fit');

      expect(find.text('Solo letras, números, "_" y "."'), findsOneWidget);
      expect(puedeAvanzar(), isFalse);
    });

    // El borrador sólo exige 3 caracteres, así que un nombre largo "pasa" el
    // `isStep1Valid` y lo frena el formato: justo el hueco sin mensaje.
    testWidgets('más de 20 caracteres', (tester) async {
      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      await escribir(tester, 'a' * 21);

      expect(find.text('Máximo 20 caracteres'), findsOneWidget);
      expect(puedeAvanzar(), isFalse);
    });

    testWidgets('borrar lo escrito pide el username', (tester) async {
      await tester.pumpWidget(_wrap(container));
      await tester.pump();

      await escribir(tester, 'ab');
      await escribir(tester, '');

      expect(find.text('Ingresá un username'), findsOneWidget);
    });

    testWidgets('al corregirlo el mensaje desaparece', (tester) async {
      final auth = _MockFirebaseAuth();
      when(() => auth.currentUser).thenReturn(null);
      final repo = _MockUserPublicProfileRepository();
      when(
        () => repo.isDisplayNameTaken(
          any(),
          excludeUid: any(named: 'excludeUid'),
        ),
      ).thenAnswer((_) async => false);
      final conRepo = ProviderContainer(overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        userPublicProfileRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(conRepo.dispose);
      await tester.pumpWidget(_wrap(conRepo));
      await tester.pump();

      await escribir(tester, 'ab');
      expect(find.text('Mínimo 3 caracteres'), findsOneWidget);

      await escribir(tester, 'ana_fit');
      // Deja correr el debounce de la verificación de disponibilidad.
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Mínimo 3 caracteres'), findsNothing);
      expect(conRepo.read(profileSetupNotifierProvider).canGoNext, isTrue);
    });
  });
}
