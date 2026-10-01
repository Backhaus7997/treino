import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/analytics/analytics_consent.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/gyms/data/gym_repository.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/presentation/privacy_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

// Pantalla de Privacidad — las DOS tarjetas: analítica (por dispositivo) y
// correos promocionales (por cuenta, `users/{uid}.notificationPrefs`).
//
// Lo que más pesa del de correos es la regla «no sé no es sí»: mientras no hay
// una lectura —cargando o con error— el interruptor tiene que estar
// DESHABILITADO. Un switch prendido sobre un valor que nunca se leyó deja al
// usuario «confirmando» algo que no vio.

const _uid = 'uid-privacidad';

class _MockUser extends Mock implements User {
  @override
  String get uid => _uid;
}

class _MockUserRepository extends Mock implements UserRepository {}

/// Lo que se le mandó a Firebase Analytics, sin Firebase.
class _ToggleEspia {
  final List<bool> llamadas = [];
  Future<void> call(bool enabled) async => llamadas.add(enabled);
}

const _llaveCorreos = ValueKey('privacy-promo-emails-switch');
const _llaveAnalitica = ValueKey('privacy-analytics-switch');

Switch _switch(WidgetTester tester, Key key) =>
    tester.widget<Switch>(find.byKey(key));

/// Deja que un evento del stream del documento llegue a la pantalla: el primer
/// `pump` entrega el evento al provider (que marca el widget como sucio) y el
/// segundo dibuja el frame con el valor nuevo.
Future<void> _alDocumento(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Future<void> _montar(
  WidgetTester tester, {
  required UserRepository repo,
  _ToggleEspia? espia,
  Locale locale = const Locale('es', 'AR'),
  Size size = const Size(390, 844),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final toggle = espia ?? _ToggleEspia();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesOverride(prefs),
        analyticsToggleProvider.overrideWithValue(toggle.call),
        authStateChangesProvider.overrideWith((_) => Stream.value(_MockUser())),
        userRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: const Scaffold(body: PrivacyScreen()),
      ),
    ),
  );
  // El auth llega por un stream: un frame para que el provider de correos
  // pase de «sin sesión» a escuchar el documento.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  setUpAll(() {
    registerFallbackValue(false);
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Contra Firestore (fake): lo que el usuario ve sale del documento de verdad.
  // ──────────────────────────────────────────────────────────────────────────
  group('PrivacyScreen — correos promocionales, contra el documento', () {
    late FakeFirebaseFirestore firestore;
    late UserRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = UserRepository(
        firestore: firestore,
        gyms: GymRepository(firestore: firestore),
      );
    });

    Future<void> sembrar(Map<String, Object?> extra) => firestore
        .collection('users')
        .doc(_uid)
        .set(<String, Object?>{'uid': _uid, ...extra});

    testWidgets('campo ausente → PRENDIDO (igual que el servidor)',
        (tester) async {
      await sembrar({});
      await _montar(tester, repo: repo);

      final sw = _switch(tester, _llaveCorreos);
      expect(sw.value, isTrue);
      expect(sw.onChanged, isNotNull,
          reason: 'ya leyó: tiene que poder tocarse');
    });

    testWidgets('email: false → APAGADO', (tester) async {
      await sembrar({
        'notificationPrefs': {
          'novedades_plan': {'email': false},
        },
      });
      await _montar(tester, repo: repo);

      final sw = _switch(tester, _llaveCorreos);
      expect(sw.value, isFalse);
      expect(sw.onChanged, isNotNull);
    });

    testWidgets('email: true → PRENDIDO', (tester) async {
      await sembrar({
        'notificationPrefs': {
          'novedades_plan': {'email': true},
        },
      });
      await _montar(tester, repo: repo);

      expect(_switch(tester, _llaveCorreos).value, isTrue);
    });

    testWidgets(
        'apagarlo escribe el MAPA ANIDADO con merge y no pisa el resto del '
        'documento', (tester) async {
      await sembrar({
        'displayName': 'Ana',
        'notificationPrefs': {
          'mensaje_nuevo': {'push': true, 'email': false},
        },
      });
      await _montar(tester, repo: repo);

      await tester.tap(find.byKey(_llaveCorreos));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final data = (await firestore.collection('users').doc(_uid).get()).data();
      expect(
        data,
        equals({
          'uid': _uid,
          'displayName': 'Ana',
          'notificationPrefs': {
            'mensaje_nuevo': {'push': true, 'email': false},
            'novedades_plan': {'email': false},
          },
        }),
      );
      // Y la pantalla lo muestra: el switch lee del documento, no de un
      // estado local.
      expect(_switch(tester, _llaveCorreos).value, isFalse);
    });

    testWidgets(
        'si la escritura falla: avisa con un snackbar y el switch queda en el '
        'valor real', (tester) async {
      await sembrar({});
      await _montar(tester, repo: repo);
      expect(_switch(tester, _llaveCorreos).value, isTrue);

      whenCalling(Invocation.method(#set, null))
          .on(firestore.collection('users').doc(_uid))
          .thenThrow(FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          ));

      await tester.tap(find.byKey(_llaveCorreos));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('No pudimos guardar el cambio. Intentá de nuevo.'),
        findsOneWidget,
      );
      expect(
        _switch(tester, _llaveCorreos).value,
        isTrue,
        reason: 'no se guardó nada: el valor real sigue siendo «prendido»',
      );
      final data = (await firestore.collection('users').doc(_uid).get()).data();
      expect(data, equals({'uid': _uid}));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Contra un repo controlable: los estados que Firestore fake no da (cargando,
  // error) y el rebote optimista de la caché de Firestore.
  // ──────────────────────────────────────────────────────────────────────────
  group('PrivacyScreen — correos promocionales, estados sin respuesta', () {
    late _MockUserRepository repo;
    late StreamController<bool> doc;

    setUp(() {
      repo = _MockUserRepository();
      doc = StreamController<bool>.broadcast();
      addTearDown(doc.close);
      when(() => repo.watchCorreosPromocionales(any()))
          .thenAnswer((_) => doc.stream);
      when(() => repo.setCorreosPromocionales(any(), any()))
          .thenAnswer((_) async {});
    });

    testWidgets('CARGANDO → deshabilitado, y tocarlo no escribe nada',
        (tester) async {
      await _montar(tester, repo: repo);
      // El stream del documento todavía no emitió.

      final sw = _switch(tester, _llaveCorreos);
      expect(
        sw.onChanged,
        isNull,
        reason: '«no sé» no es «sí»: sin lectura no se puede accionar',
      );
      expect(
        sw.value,
        isFalse,
        reason: 'y tampoco puede mostrarse PRENDIDO mientras carga',
      );

      await tester.tap(find.byKey(_llaveCorreos), warnIfMissed: false);
      await tester.pump();
      verifyNever(() => repo.setCorreosPromocionales(any(), any()));
    });

    testWidgets('ERROR de lectura → deshabilitado', (tester) async {
      await _montar(tester, repo: repo);

      doc.addError(FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
      ));
      await _alDocumento(tester);

      expect(_switch(tester, _llaveCorreos).onChanged, isNull);
      verifyNever(() => repo.setCorreosPromocionales(any(), any()));
    });

    testWidgets('sin respuesta, el lector de pantalla NO oye «apagado»',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _montar(tester, repo: repo);

      final sinRespuesta = tester.getSemantics(find.byKey(_llaveCorreos));
      expect(
        sinRespuesta.getSemanticsData().flagsCollection.isToggled,
        Tristate.none,
        reason: 'un switch que no leyó su valor no puede anunciar «apagado»',
      );
      expect(sinRespuesta.getSemanticsData().flagsCollection.isEnabled,
          Tristate.isFalse);

      doc.add(false);
      await _alDocumento(tester);

      final conRespuesta = tester.getSemantics(find.byKey(_llaveCorreos));
      expect(
        conRespuesta.getSemanticsData().flagsCollection.isToggled,
        Tristate.isFalse,
        reason: 'ya leyó `false`: ahora sí es «apagado»',
      );
      handle.dispose();
    });

    testWidgets('al llegar la lectura se habilita y refleja el valor',
        (tester) async {
      await _montar(tester, repo: repo);
      expect(_switch(tester, _llaveCorreos).onChanged, isNull);

      doc.add(false);
      await _alDocumento(tester);

      final sw = _switch(tester, _llaveCorreos);
      expect(sw.onChanged, isNotNull);
      expect(sw.value, isFalse);
    });

    testWidgets('tocar el switch llama al repo con el valor NUEVO y el uid',
        (tester) async {
      await _montar(tester, repo: repo);
      doc.add(true);
      await _alDocumento(tester);

      await tester.tap(find.byKey(_llaveCorreos));
      await tester.pump();
      verify(() => repo.setCorreosPromocionales(_uid, false)).called(1);

      // Y de vuelta: el valor que llega por el stream es ahora `false`.
      doc.add(false);
      await _alDocumento(tester);
      await tester.tap(find.byKey(_llaveCorreos));
      await tester.pump();
      verify(() => repo.setCorreosPromocionales(_uid, true)).called(1);
    });

    testWidgets(
        'falla de escritura con rebote de la caché: snackbar y el switch '
        'VUELVE al valor real', (tester) async {
      // Lo que hace el SDK real: aplica la escritura en la caché local y el
      // stream emite el valor nuevo al instante; cuando el servidor la
      // rechaza, la deshace y re-emite el valor de verdad.
      when(() => repo.setCorreosPromocionales(any(), any()))
          .thenAnswer((inv) async {
        doc.add(inv.positionalArguments[1] as bool);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        doc.add(!(inv.positionalArguments[1] as bool));
        throw FirebaseException(
          plugin: 'cloud_firestore',
          code: 'permission-denied',
        );
      });
      await _montar(tester, repo: repo);
      doc.add(true);
      await _alDocumento(tester);
      expect(_switch(tester, _llaveCorreos).value, isTrue);

      await tester.tap(find.byKey(_llaveCorreos));
      await tester.pump(); // el stream emite `false` (optimista)
      expect(_switch(tester, _llaveCorreos).value, isFalse);

      await tester.pump(const Duration(milliseconds: 100)); // rebote + error
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('No pudimos guardar el cambio. Intentá de nuevo.'),
        findsOneWidget,
      );
      expect(_switch(tester, _llaveCorreos).value, isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // La tarjeta de analítica sigue siendo la que era.
  // ──────────────────────────────────────────────────────────────────────────
  group('PrivacyScreen — analítica y composición', () {
    late _MockUserRepository repo;

    setUp(() {
      repo = _MockUserRepository();
      when(() => repo.watchCorreosPromocionales(any()))
          .thenAnswer((_) => Stream<bool>.value(true));
    });

    testWidgets('la tarjeta de analítica sigue funcionando', (tester) async {
      final espia = _ToggleEspia();
      await _montar(tester, repo: repo, espia: espia);

      expect(_switch(tester, _llaveAnalitica).value, isTrue);
      expect(find.text('Analítica de uso'), findsOneWidget);

      await tester.tap(find.byKey(_llaveAnalitica));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(espia.llamadas, [false]);
      expect(_switch(tester, _llaveAnalitica).value, isFalse);
      // …y no tocó al otro.
      expect(_switch(tester, _llaveCorreos).value, isTrue);
      verifyNever(() => repo.setCorreosPromocionales(any(), any()));
    });

    testWidgets('el copy de la tarjeta nueva es el de es_AR', (tester) async {
      await _montar(tester, repo: repo);

      expect(find.text('Correos promocionales'), findsOneWidget);
      expect(
        find.text(
          'Si lo apagás, no te mandamos más. Los avisos de tu cuenta te '
          'siguen llegando.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        'la frase «preferencia de ESTE dispositivo» queda pegada a la '
        'analítica: la tarjeta de correos va DESPUÉS y no la hereda',
        (tester) async {
      await _montar(tester, repo: repo);
      final l10n = AppL10n.of(tester.element(find.byType(PrivacyScreen)));

      // Es una tarjeta aparte: otro `Switch`, otro título.
      expect(find.byType(Switch), findsNWidgets(2));

      final yAnalitica = tester.getTopLeft(find.byKey(_llaveAnalitica)).dy;
      final yExplicacion =
          tester.getTopLeft(find.text(l10n.privacyAnalyticsExplainer)).dy;
      final yNota =
          tester.getTopLeft(find.text(l10n.privacyAnalyticsCrashNote)).dy;
      final yCorreos = tester.getTopLeft(find.byKey(_llaveCorreos)).dy;

      expect(yAnalitica, lessThan(yExplicacion));
      expect(yExplicacion, lessThan(yNota));
      expect(
        yNota,
        lessThan(yCorreos),
        reason: 'la explicación del dispositivo tiene que quedar entre la '
            'tarjeta de analítica y la de correos, no después de la segunda',
      );

      // Y lo que dice la tarjeta de correos no habla de dispositivo ni del
      // Coach Hub: es una preferencia de la CUENTA.
      expect(l10n.privacyPromoEmailsSubtitle, isNot(contains('dispositivo')));
      expect(l10n.privacyPromoEmailsSubtitle, isNot(contains('Coach Hub')));
    });

    testWidgets(
        'con el texto del sistema al máximo y una pantalla chica no '
        'desborda: el contenido scrollea y la tarjeta de correos se alcanza',
        (tester) async {
      await _montar(
        tester,
        repo: repo,
        size: const Size(320, 480),
        textScale: 2.0,
      );

      await tester.scrollUntilVisible(
        find.byKey(_llaveCorreos),
        200,
        scrollable: find.byType(Scrollable),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byKey(_llaveCorreos), findsOneWidget);
    });
  });
}
