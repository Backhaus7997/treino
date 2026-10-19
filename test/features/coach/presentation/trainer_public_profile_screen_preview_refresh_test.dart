// #1498 (c) — después de cargar los años desde el aviso del preview, el preview
// seguía mostrando «AÑOS EXP —» y el aviso: había que matar la app para ver el
// dato (QA manual 2026-10-19, Pixel 9 Pro, coach.lautaro).
//
// El dato SÍ se guardaba (`users/{uid}` y `trainerPublicProfiles/{uid}` con el
// valor). Lo que fallaba era que el preview leía el perfil público UNA vez
// (`trainerByIdProvider`, un `FutureProvider` con `.get()`):
//
//  - ese provider lo comparte `TrainerProfileView` —la pantalla de abajo en el
//    stack— y lo mantiene vivo, así que un preview nuevo reusaba el valor que
//    quedó en memoria (el paso 4 del reporte: salir y volver a entrar);
//  - y aun invalidándolo al volver del formulario, depende de qué le conteste
//    la lectura puntual al SDK en ese momento.
//
// Estos tests ejercitan los datos REALES (`FakeFirebaseFirestore` + el
// `UserRepository` de verdad, el mismo dual-write que usa el formulario) y no
// overridean ningún provider del perfil público: lo que se mide es que el
// preview siga al documento.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/presentation/trainer_public_profile_screen.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_preview_notices.dart';
import 'package:treino/features/notifications/application/notification_router.dart'
    show locationActualDe;
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/trainer_profile_view.dart';
import 'package:treino/features/reviews/application/review_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

const _uid = 'trainer-uid';
const _previewPath = '/profile/trainer-preview/$_uid';

UserProfile _pf() => UserProfile(
      uid: _uid,
      email: 'pf@test.com',
      displayName: 'Coach Ana',
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

/// Un PF con tarjeta pública creada y SIN años de experiencia cargados.
Future<FakeFirebaseFirestore> _firestoreDelPf() async {
  final firestore = FakeFirebaseFirestore();
  await firestore.collection('users').doc(_uid).set(_pf().toJson());
  await firestore.collection('trainerPublicProfiles').doc(_uid).set({
    'uid': _uid,
    'displayName': 'Coach Ana',
    'displayNameLowercase': 'coach ana',
  });
  return firestore;
}

/// Lo que hace el formulario de EDITAR al guardar: el dual-write de verdad.
Future<void> _guardarAnios(FakeFirebaseFirestore firestore, int years) =>
    UserRepository(firestore: firestore).update(
      _uid,
      {'trainerExperienceYears': years},
    );

/// Stand-in del formulario de EDITAR: GUARDAR hace el mismo `update` y
/// `pop()`, como `ProfileEditTrainerScreen` en modo edición.
class _FormularioDeEdicion extends ConsumerWidget {
  const _FormularioDeEdicion({required this.years});
  final int years;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: TextButton(
          onPressed: () async {
            await ref
                .read(userRepositoryProvider)
                .update(_uid, {'trainerExperienceYears': years});
            if (context.mounted) context.pop();
          },
          child: const Text('GUARDAR'),
        ),
      );
}

GoRouter _router({required String initialLocation, int yearsToSave = 8}) =>
    GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => const Scaffold(body: TrainerProfileView()),
        ),
        GoRoute(
          path: '/profile/trainer-preview/:uid',
          builder: (_, state) => TrainerPublicProfileScreen(
            uid: state.pathParameters['uid']!,
            preview: true,
          ),
        ),
        GoRoute(
          path: '/profile/edit-trainer',
          builder: (_, __) => _FormularioDeEdicion(years: yearsToSave),
        ),
      ],
    );

Widget _app(FakeFirebaseFirestore firestore, GoRouter router) => ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        currentUidProvider.overrideWithValue(_uid),
        userProfileProvider.overrideWith((_) => Stream.value(_pf())),
        trainerLinksStreamProvider.overrideWith((_) => Stream.value(const [])),
        currentAthleteLinkAnyStatusProvider
            .overrideWith((_) => Stream.value(null)),
        currentAthleteLinkProvider.overrideWith((_) => Stream.value(null)),
        trainerReviewsProvider(_uid)
            .overrideWith((_) => Stream.value(const [])),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        routerConfig: router,
      ),
    );

Finder get _aviso => find.byType(TrainerPreviewMissingExperienceNotice);

void main() {
  testWidgets(
      'el preview abierto sigue al documento: si los años se guardan, '
      'aparece el valor y se va el aviso, sin navegar ni reiniciar',
      (tester) async {
    final firestore = await _firestoreDelPf();
    await tester.pumpWidget(
      _app(firestore, _router(initialLocation: _previewPath)),
    );
    await tester.pumpAndSettle();
    expect(_aviso, findsOneWidget, reason: 'sanity: aún no hay años');

    await _guardarAnios(firestore, 8);
    await tester.pumpAndSettle();

    expect(find.text('8'), findsOneWidget);
    expect(_aviso, findsNothing);
  });

  testWidgets(
      'EDITAR desde la tarjeta y VER PREVIEW después: el preview NO reusa el '
      'perfil que quedó en memoria en la pantalla de abajo (paso 4 del '
      'reporte)', (tester) async {
    final firestore = await _firestoreDelPf();
    final router = _router(initialLocation: '/');
    await tester.pumpWidget(_app(firestore, router));
    await tester.pumpAndSettle();
    // La vista del PF ya cargó (y mantiene vivo) su perfil público, sin años.
    expect(find.text('VISIBLE'), findsOneWidget);

    // El PF guarda los años desde EDITAR…
    await _guardarAnios(firestore, 8);
    await tester.pumpAndSettle();

    // …y abre VER PREVIEW.
    await tester.tap(find.text('VER PREVIEW'));
    await tester.pumpAndSettle();

    expect(locationActualDe(router), _previewPath);
    expect(find.text('8'), findsOneWidget);
    expect(_aviso, findsNothing);
  });

  testWidgets(
      'el flujo del reporte: aviso → formulario → GUARDAR → vuelve al preview '
      'con el valor nuevo y sin aviso', (tester) async {
    final firestore = await _firestoreDelPf();
    await tester.pumpWidget(
      _app(firestore, _router(initialLocation: _previewPath)),
    );
    await tester.pumpAndSettle();
    expect(_aviso, findsOneWidget);

    await tester.tap(_aviso);
    await tester.pumpAndSettle();
    expect(find.text('GUARDAR'), findsOneWidget);

    await tester.tap(find.text('GUARDAR'));
    await tester.pumpAndSettle();

    expect(find.byType(TrainerPublicProfileScreen), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(_aviso, findsNothing);
  });
}
