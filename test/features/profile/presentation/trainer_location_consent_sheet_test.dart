import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/presentation/trainer_location_consent_sheet.dart';
import 'package:treino/l10n/app_l10n.dart';

// consentimiento-legal-versionado — R7.
//
// SOLO estado/semántica: `google_fonts` no carga en `flutter_test` (mide
// con la fuente de fallback, ~2,5x más ancha que Barlow), así que ningún
// assert acá es sobre ancho, wrapping u overflow — sólo qué método del
// repo se llamó y en qué quedó el doc de Firestore. Mismo patrón que
// `home_cta_button_test.dart`.

const _uid = 'trainer-sheet-1';

Future<void> _seedTrainer(FakeFirebaseFirestore firestore) async {
  final now = DateTime.utc(2026, 1, 1);
  final profile = UserProfile(
    uid: _uid,
    email: 'pf@test.com',
    displayName: 'Coach',
    role: UserRole.trainer,
    createdAt: now,
    updatedAt: now,
  );
  await firestore.collection('users').doc(_uid).set(profile.toJson());
}

Widget _host(FakeFirebaseFirestore firestore) {
  return ProviderScope(
    overrides: [firestoreProvider.overrideWithValue(firestore)],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isDismissible: false,
                enableDrag: true,
                builder: (_) => const TrainerLocationConsentSheet(uid: _uid),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<Map<String, Object?>> _usersDoc(FakeFirebaseFirestore firestore) async {
  final snap = await firestore.collection('users').doc(_uid).get();
  return snap.data()!;
}

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await _seedTrainer(firestore);
  });

  testWidgets('ACEPTAR llama grantTrainerLocationConsent', (tester) async {
    await tester.pumpWidget(_host(firestore));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('trainer_location_consent_accept_button')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('trainer_location_consent_accept_button')),
    );
    await tester.pumpAndSettle();

    final data = await _usersDoc(firestore);
    expect(data['trainerLocationConsentAt'], isNotNull);
    expect(data['trainerLocationConsentPromptedAt'], isNotNull);
    // El sheet se cerró — no queda montado.
    expect(find.byType(TrainerLocationConsentSheet), findsNothing);
  });

  testWidgets('APAGAR LA PUBLICACIÓN llama revokeTrainerLocationConsent',
      (tester) async {
    await tester.pumpWidget(_host(firestore));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('trainer_location_consent_revoke_button')),
    );
    await tester.pumpAndSettle();

    final data = await _usersDoc(firestore);
    // revoke deja consentAt en null (ya lo estaba) pero SIEMPRE estampa
    // promptedAt — es la prueba de que pasó por el método, no un no-op.
    expect(data['trainerLocationConsentAt'], isNull);
    expect(data['trainerLocationConsentPromptedAt'], isNotNull);
    expect(find.byType(TrainerLocationConsentSheet), findsNothing);
  });

  testWidgets(
      'cerrar sin decidir (back) sólo marca promptedAt — sin grant, sin revoke',
      (tester) async {
    await tester.pumpWidget(_host(firestore));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(TrainerLocationConsentSheet), findsOneWidget);

    // Simula el back del sistema / el arrastre — ambos pasan por el mismo
    // Navigator.pop() que intercepta el PopScope del sheet.
    final navigator =
        tester.state<NavigatorState>(find.byType(Navigator).first);
    await navigator.maybePop();
    await tester.pumpAndSettle();

    final data = await _usersDoc(firestore);
    expect(data['trainerLocationConsentAt'], isNull);
    expect(data['trainerLocationConsentPromptedAt'], isNotNull);
    expect(find.byType(TrainerLocationConsentSheet), findsNothing);
  });

  testWidgets(
      'ninguna de las 3 salidas vuelve a abrir el sheet (no reentra tras cerrar)',
      (tester) async {
    await tester.pumpWidget(_host(firestore));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('trainer_location_consent_accept_button')),
    );
    await tester.pumpAndSettle();

    // El sheet no es un widget "que se auto-reabre" — no hay listener acá
    // que lo vuelva a mostrar. Confirmamos que quedó cerrado y estable.
    expect(find.byType(TrainerLocationConsentSheet), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(TrainerLocationConsentSheet), findsNothing);
  });
}
