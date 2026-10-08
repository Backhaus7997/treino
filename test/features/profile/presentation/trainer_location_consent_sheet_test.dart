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
// Estado/semántica: `google_fonts` no carga en `flutter_test` (mide con la
// fuente de fallback, ~2,5x más ancha que Barlow), así que ningún assert acá
// es sobre ancho o wrapping — qué método del repo se llamó y en qué quedó el
// doc de Firestore. Mismo patrón que `home_cta_button_test.dart`.
//
// La única excepción es el grupo de la letra de accesibilidad, y es
// estructural: que los botones queden a la vista sin desbordar. Ahí la fuente
// de fallback juega a favor del test, no en contra: más ancha es más alta, así
// que si algo, el rojo sale antes.

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

Widget _host(
  FakeFirebaseFirestore firestore, {
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return ProviderScope(
    overrides: [firestoreProvider.overrideWithValue(firestore)],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                // Como lo abre `TrainerLocationConsentGate`: sin esto el
                // sheet queda topado a 9/16 de la pantalla y no al 0,9 que
                // pide el propio widget.
                isScrollControlled: true,
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

  // Con la letra al máximo de accesibilidad (≈3,1× en iOS) el texto empujaba
  // los dos botones 327 px por debajo del borde: el PF no podía ni aceptar ni
  // apagar la publicación, sólo cerrar arrastrando (iPhone 17e, 2026-10-02).
  group('letra al máximo de accesibilidad', () {
    testWidgets(
        'los dos botones quedan a la vista sin scrollear y nada desborda',
        (tester) async {
      tester.view.physicalSize = const Size(1170, 2532); // iPhone 17e
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(firestore, textScaler: const TextScaler.linear(3.1)),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final pantalla = Offset.zero & const Size(390, 844);
      for (final key in const [
        Key('trainer_location_consent_accept_button'),
        Key('trainer_location_consent_revoke_button'),
      ]) {
        final boton = tester.getRect(find.byKey(key));
        expect(
          pantalla.contains(boton.topLeft) &&
              pantalla.contains(boton.bottomRight - const Offset(1, 1)),
          isTrue,
          reason: '$key quedó fuera de la pantalla: $boton',
        );
      }

      // Y el texto se lee entero: scrolleando, su final aparece por encima de
      // los botones. Sin esto, un scroll que no scrollea pasaría el test de
      // arriba con el cuerpo cortado para siempre.
      final l10n = AppL10n.of(
        tester.element(find.byType(TrainerLocationConsentSheet)),
      );
      final cuerpo = find.text(l10n.trainerLocationConsentSheetBody);
      // Desde el centro del área scrolleable, que está a la vista: el centro
      // del párrafo queda debajo del corte, sobre los botones.
      await tester.drag(
        find.ancestor(of: cuerpo, matching: find.byType(Scrollable)).first,
        const Offset(0, -3000),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(cuerpo).dy,
        lessThanOrEqualTo(
          tester
              .getTopLeft(
                find.byKey(const Key('trainer_location_consent_accept_button')),
              )
              .dy,
        ),
      );
    });
  });
}
