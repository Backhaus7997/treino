// Tests for ProfileEditTrainerScreen — consentimiento de publicación de
// ubicación (consentimiento-legal-versionado, T2).
//
// Strict TDD: este archivo es el artefacto RED del grupo 11.
//
// SOLO estado/semántica: `google_fonts` no carga en `flutter_test` (mide con
// la fuente de fallback, ~2,5x más ancha que Barlow), así que no hay un solo
// assert de ancho, wrapping u overflow. Los finders van por `Key`, no por
// texto, para que el copy pueda cambiar sin romper el contrato.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/coach/application/trainer_discovery_providers.dart';
import 'package:treino/features/coach/domain/trainer_location.dart';
import 'package:treino/features/coach/domain/trainer_public_profile.dart';
import 'package:treino/features/gyms/application/gym_providers.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/presentation/profile_edit_trainer_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

class MockUserRepository extends Mock implements UserRepository {}

/// Espejo público del PF. Sólo la fila `(consentAt null, promptedAt set)` de la
/// tabla de estados lo lee — las otras tres se contestan con los timestamps—,
/// pero el override tiene que estar SIEMPRE: sin él el provider sale a buscar
/// un Firestore real.
class _FakeEspejo extends Fake
    implements TrainerPublicProfileRepositoryInterface {
  _FakeEspejo({required this.publicado});
  final bool publicado;

  @override
  Future<TrainerPublicProfile?> getById(String uid) async =>
      TrainerPublicProfile(
        uid: uid,
        trainerLocations: publicado ? const [_location] : const [],
      );
}

const _uid = 'trainer-uid';

const _location = TrainerLocation(
  id: 'loc-1',
  type: TrainerLocationType.custom,
  customLabel: 'Parque Centenario',
  lat: -34.606,
  lng: -58.435,
  geohash: '69y7pkxfb',
);

/// Perfil de PF completo y guardable. `consentAt`/`promptedAt` se mueven por
/// test: son justamente lo que decide si la pantalla pide consentimiento.
UserProfile _trainer({
  List<TrainerLocation> locations = const [_location],
  DateTime? consentAt,
  DateTime? promptedAt,
}) =>
    UserProfile(
      uid: _uid,
      email: 'trainer@example.com',
      displayName: 'Mauro PF',
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      trainerBio: 'Bio de al menos 20 caracteres ok',
      trainerSpecialty: 'crossfit',
      trainerMonthlyRate: 8000,
      trainerLocations: locations,
      trainerLocationConsentAt: consentAt,
      trainerLocationConsentPromptedAt: promptedAt,
    );

Widget _buildScreen({
  required UserProfile profile,
  required MockUserRepository repo,
  bool espejoPublicado = false,
}) {
  final router = GoRouter(
    initialLocation: '/profile/edit-trainer',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, __) => const Scaffold(body: Text('HOME')),
      ),
      GoRoute(
        path: '/profile',
        builder: (_, __) => const Scaffold(body: Text('PROFILE')),
        routes: [
          GoRoute(
            path: 'edit-trainer',
            builder: (_, __) => const Scaffold(
              body: ProfileEditTrainerScreen(
                mode: ProfileEditTrainerMode.edit,
              ),
            ),
          ),
        ],
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      authStateChangesProvider.overrideWith((_) => Stream.value(null)),
      userProfileProvider.overrideWith((_) => Stream.value(profile)),
      userRepositoryProvider.overrideWithValue(repo),
      gymsProvider.overrideWith((ref) async => const []),
      trainerPublicProfileRepositoryProvider
          .overrideWithValue(_FakeEspejo(publicado: espejoPublicado)),
    ],
    child: MaterialApp.router(
      theme: AppTheme.dark(),
      routerConfig: router,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
    ),
  );
}

MockUserRepository _repo() {
  final repo = MockUserRepository();
  when(() => repo.update(
        any(),
        any(),
        grantLocationConsent: any(named: 'grantLocationConsent'),
      )).thenAnswer((_) async {});
  when(() => repo.grantTrainerLocationConsent(any())).thenAnswer((_) async {});
  when(() => repo.revokeTrainerLocationConsent(any())).thenAnswer((_) async {});
  return repo;
}

Future<void> _tapSave(WidgetTester tester) async {
  await tester.ensureVisible(
    find.byKey(const Key('profile_edit_trainer_save_button')),
  );
  await tester.tap(find.byKey(const Key('profile_edit_trainer_save_button')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(_uid);
    registerFallbackValue(<String, Object?>{});
  });

  group('T2: pedir consentimiento antes de publicar la ubicación', () {
    testWidgets(
        'guardar con ubicaciones y sin consentimiento pide confirmación '
        'ANTES de persistir', (tester) async {
      final repo = _repo();
      await tester.pumpWidget(
        _buildScreen(profile: _trainer(consentAt: null), repo: repo),
      );
      await tester.pumpAndSettle();

      await _tapSave(tester);

      // La confirmación está en pantalla...
      expect(
        find.byKey(const Key('profile_edit_trainer_consent_confirm')),
        findsOneWidget,
      );
      // ...y nada se persistió todavía. Este es el corazón del requirement:
      // sin consentimiento, el gate del subset descartaría la ubicación en
      // silencio y el PF creería estar publicado.
      verifyNever(() => repo.update(any(), any()));
      verifyNever(() => repo.grantTrainerLocationConsent(any()));
    });

    testWidgets('aceptar persiste consentimiento y formulario en UN commit',
        (tester) async {
      final repo = _repo();
      await tester.pumpWidget(
        _buildScreen(profile: _trainer(consentAt: null), repo: repo),
      );
      await tester.pumpAndSettle();

      await _tapSave(tester);
      await tester.tap(
        find.byKey(const Key('profile_edit_trainer_consent_accept')),
      );
      await tester.pumpAndSettle();

      // P1-d. La versión anterior de este test afirmaba
      // `verify(grantTrainerLocationConsent).called(1)` — o sea, medía QUÉ
      // MÉTODO se llamó. Por eso pasaba en verde sobre el bug: los dos commits
      // eran exactamente lo que verificaba.
      //
      // Lo que importa es que haya UN solo commit. `grantTrainerLocationConsent`
      // relee de Firestore y republica las ubicaciones VIEJAS, así que llamarlo
      // antes del guardado exponía en el espejo público coordenadas que el PF
      // no consintió — y las dejaba ahí para siempre si el segundo commit
      // fallaba.
      verifyNever(() => repo.grantTrainerLocationConsent(any()));
      verify(
        () => repo.update(
          _uid,
          any(),
          grantLocationConsent: true,
        ),
      ).called(1);
    });

    testWidgets('con el consentimiento ya otorgado NO lo vuelve a otorgar',
        (tester) async {
      // Control negativo del test de arriba: sin esto, `grantLocationConsent`
      // podría estar cableado en `true` siempre y el test anterior no se
      // enteraría.
      final repo = _repo();
      await tester.pumpWidget(
        _buildScreen(
          profile: _trainer(
            consentAt: DateTime.utc(2026, 3, 1),
            promptedAt: DateTime.utc(2026, 3, 1),
          ),
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      await _tapSave(tester);
      await tester.pumpAndSettle();

      verify(
        () => repo.update(
          _uid,
          any(),
          grantLocationConsent: false,
        ),
      ).called(1);
    });

    testWidgets('cancelar no persiste NI pierde lo cargado en silencio',
        (tester) async {
      final repo = _repo();
      await tester.pumpWidget(
        _buildScreen(profile: _trainer(consentAt: null), repo: repo),
      );
      await tester.pumpAndSettle();

      await _tapSave(tester);
      await tester.tap(
        find.byKey(const Key('profile_edit_trainer_consent_cancel')),
      );
      await tester.pumpAndSettle();

      verifyNever(() => repo.grantTrainerLocationConsent(any()));
      verifyNever(() => repo.update(any(), any()));
      // Sigue en el form, con la ubicación cargada — no lo mandamos a /home
      // ni le vaciamos la lista.
      expect(find.byType(ProfileEditTrainerScreen), findsOneWidget);
      expect(
        find.byKey(const Key('profile_edit_trainer_save_button')),
        findsOneWidget,
      );
    });

    testWidgets('con consentimiento ya otorgado guarda derecho, sin preguntar',
        (tester) async {
      final repo = _repo();
      await tester.pumpWidget(
        _buildScreen(
          profile: _trainer(
            consentAt: DateTime.utc(2026, 9, 3),
            promptedAt: DateTime.utc(2026, 9, 3),
          ),
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      await _tapSave(tester);

      expect(
        find.byKey(const Key('profile_edit_trainer_consent_confirm')),
        findsNothing,
      );
      verify(() => repo.update(_uid, any())).called(1);
      verifyNever(() => repo.grantTrainerLocationConsent(any()));
    });

    testWidgets('sin ubicaciones no hay nada que consentir', (tester) async {
      final repo = _repo();
      await tester.pumpWidget(
        _buildScreen(
          profile: _trainer(locations: const [], consentAt: null)
              .copyWith(trainerOffersOnline: true),
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      await _tapSave(tester);

      expect(
        find.byKey(const Key('profile_edit_trainer_consent_confirm')),
        findsNothing,
      );
      verify(() => repo.update(_uid, any())).called(1);
    });
  });

  group('T2: la fila de estado dice la verdad sobre la publicación', () {
    testWidgets(
        'revocado ⇒ estado "no publicado" aunque users siga con '
        'las ubicaciones', (tester) async {
      // Este es exactamente el estado post-revoke: `revoke` NO toca
      // `trainerLocations` en `users/{uid}`, sólo vacía el espejo público.
      // Si la fila leyera `trainerLocations` le mentiría al PF.
      await tester.pumpWidget(
        _buildScreen(
          profile: _trainer(
            consentAt: null,
            promptedAt: DateTime.utc(2026, 9, 3),
          ),
          repo: _repo(),
        ),
      );
      await tester.pumpAndSettle();

      final status = find.byKey(
        const Key('profile_edit_trainer_publication_status'),
      );
      await tester.ensureVisible(status);
      expect(status, findsOneWidget);
      expect(
        tester.widget<Text>(status).data,
        AppL10n.of(tester.element(status)).profileEditTrainerNotPublished,
      );
    });

    testWidgets('consentido ⇒ estado "publicado"', (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          profile: _trainer(
            consentAt: DateTime.utc(2026, 9, 3),
            promptedAt: DateTime.utc(2026, 9, 3),
          ),
          repo: _repo(),
        ),
      );
      await tester.pumpAndSettle();

      final status = find.byKey(
        const Key('profile_edit_trainer_publication_status'),
      );
      await tester.ensureVisible(status);
      expect(
        tester.widget<Text>(status).data,
        AppL10n.of(tester.element(status)).profileEditTrainerPublished,
      );
    });

    testWidgets(
        'cerró el sheet sin decidir ⇒ "publicado", porque el espejo lo sigue '
        'estando', (tester) async {
      // P1-b — LA fila que estaba mal. Mismo par de timestamps que el test de
      // "revocado" de arriba: consentAt null, promptedAt seteado. Los dos
      // estados son indistinguibles mirando `users/{uid}`, y la pantalla los
      // resolvía a ambos como "No publicada" leyendo `consentAt != null`.
      //
      // La diferencia está en el espejo: revocar lo vacía, cerrar sin decidir
      // NO lo toca (`_stampPromptedOnly` escribe un solo campo). Así que este
      // PF sigue con sus coordenadas visibles en el mapa para cualquier
      // atleta, y le decíamos que estaba oculto.
      await tester.pumpWidget(
        _buildScreen(
          profile: _trainer(
            consentAt: null,
            promptedAt: DateTime.utc(2026, 9, 3),
          ),
          repo: _repo(),
          espejoPublicado: true,
        ),
      );
      await tester.pumpAndSettle();

      final status = find.byKey(
        const Key('profile_edit_trainer_publication_status'),
      );
      await tester.ensureVisible(status);
      expect(
        tester.widget<Text>(status).data,
        AppL10n.of(tester.element(status)).profileEditTrainerPublished,
      );
    });

    testWidgets('PF legacy (nunca preguntado) ⇒ "publicado" por status quo',
        (tester) async {
      // La otra fila que colapsaba: (null, null). El PF al que todavía no le
      // llegó el gate sigue publicado — es el status quo, no una revocación.
      // El espejo va VACÍO a propósito: esta fila no debe leerlo, y si el
      // código lo leyera este test se pondría rojo.
      await tester.pumpWidget(
        _buildScreen(
          profile: _trainer(consentAt: null, promptedAt: null),
          repo: _repo(),
          espejoPublicado: false,
        ),
      );
      await tester.pumpAndSettle();

      final status = find.byKey(
        const Key('profile_edit_trainer_publication_status'),
      );
      await tester.ensureVisible(status);
      expect(
        tester.widget<Text>(status).data,
        AppL10n.of(tester.element(status)).profileEditTrainerPublished,
      );
    });

    testWidgets('publicado ⇒ hay botón de apagar, y apaga de verdad',
        (tester) async {
      // P1-a. El sheet promete "Podés apagar esto cuando quieras desde tu
      // perfil profesional" y hasta ahora esa frase era falsa: el único call
      // site de `revokeTrainerLocationConsent` vivía adentro del sheet, que se
      // suprime para siempre apenas el PF decide algo.
      final repo = _repo();
      await tester.pumpWidget(
        _buildScreen(
          profile: _trainer(
            consentAt: DateTime.utc(2026, 9, 3),
            promptedAt: DateTime.utc(2026, 9, 3),
          ),
          repo: repo,
        ),
      );
      await tester.pumpAndSettle();

      final revoke = find.byKey(
        const Key('profile_edit_trainer_revoke_button'),
      );
      await tester.ensureVisible(revoke);
      expect(revoke, findsOneWidget);

      await tester.tap(revoke);
      await tester.pumpAndSettle();

      verify(() => repo.revokeTrainerLocationConsent(_uid)).called(1);
    });

    testWidgets('no publicado ⇒ NO hay botón de apagar', (tester) async {
      // Control negativo del test de arriba: sin esto, el botón podría estar
      // siempre en pantalla y aquel pasaría igual.
      await tester.pumpWidget(
        _buildScreen(
          profile: _trainer(
            consentAt: null,
            promptedAt: DateTime.utc(2026, 9, 3),
          ),
          repo: _repo(),
          espejoPublicado: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('profile_edit_trainer_revoke_button')),
        findsNothing,
      );
    });

    testWidgets('sin ubicaciones no se muestra la fila', (tester) async {
      await tester.pumpWidget(
        _buildScreen(
          profile: _trainer(locations: const [], consentAt: null),
          repo: _repo(),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('profile_edit_trainer_publication_status')),
        findsNothing,
      );
    });
  });
}
