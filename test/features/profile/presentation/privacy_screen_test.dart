import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Tristate;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/core/analytics/analytics_consent.dart';
import 'package:treino/core/persistence/shared_prefs_provider.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/gyms/data/gym_repository.dart';
import 'package:treino/features/profile/application/correos_promocionales_providers.dart';
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
  _MockUser([this._id = _uid]);

  final String _id;

  @override
  String get uid => _id;
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

/// La PRIMERA llamada a `GoogleFonts.*` de un proceso de test devuelve un
/// estilo que todavía mide con Ahem (cada glifo = 1 em), y con el texto a 3x el
/// encabezado «PRIVACIDAD» desborda por 287 px aunque con Barlow real mida 256.
/// Sólo importa cuando el test corre solo o filtrado (en el archivo entero lo
/// calientan los tests de antes), pero un test no puede depender de qué corrió
/// antes. Se pide la MISMA variante que dibuja la pantalla y se deja un hueco
/// async REAL para que la carga termine antes del `pumpWidget`.
Future<void> _calentarFuentes(WidgetTester tester) async {
  GoogleFonts.barlow(fontWeight: FontWeight.w600);
  GoogleFonts.barlowCondensed(fontWeight: FontWeight.w700);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pumpAndSettle();
}

Future<void> _montar(
  WidgetTester tester, {
  required UserRepository repo,
  _ToggleEspia? espia,
  Stream<User?>? auth,
  Locale locale = const Locale('es', 'AR'),
  Size size = const Size(390, 844),
  double textScale = 1.0,
  // Un inset inferior del sistema (`MediaQuery.padding.bottom`), como el del
  // home indicator. 0 = no tocar el que ya trae el `MediaQuery`.
  double insetInferior = 0,
  // Si viene, el `Scaffold` se arma como el del shell: `extendBody: true` con
  // esta barra como `bottomNavigationBar`, así la barra queda ENCIMA del cuerpo
  // y el `Scaffold` publica su alto en `padding.bottom`.
  Widget? barraFlotante,
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
        authStateChangesProvider
            .overrideWith((_) => auth ?? Stream.value(_MockUser())),
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
            padding: insetInferior > 0
                ? EdgeInsets.only(bottom: insetInferior)
                : null,
          ),
          child: child!,
        ),
        home: Scaffold(
          extendBody: barraFlotante != null,
          bottomNavigationBar: barraFlotante,
          body: const PrivacyScreen(),
        ),
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
  // Una lectura BUENA que deja de valer. Riverpod conserva el valor anterior
  // cuando el estado pasa a carga o a error, así que `hasValue` sigue en `true`
  // con el documento VIEJO: el switch quedaba habilitado, mostrando eso, y un
  // toque escribía esa elección —hecha mirando otra cosa— sobre el uid de ahora.
  // ──────────────────────────────────────────────────────────────────────────
  group('PrivacyScreen — correos promocionales, la lectura deja de ser vigente',
      () {
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

    ProviderContainer contenedor(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(PrivacyScreen)));

    testWidgets('un valor y DESPUÉS un error del stream → deshabilitado',
        (tester) async {
      await _montar(tester, repo: repo);
      doc.add(true);
      await _alDocumento(tester);
      expect(_switch(tester, _llaveCorreos).onChanged, isNotNull);

      doc.addError(FirebaseException(
        plugin: 'cloud_firestore',
        code: 'unavailable',
      ));
      await _alDocumento(tester);

      // Precondición, para que el test no sea vacío: el estado SIGUE teniendo
      // el valor viejo. Es lo que engañaba a un `hasValue` a secas.
      final estado = contenedor(tester).read(correosPromocionalesProvider);
      expect(estado.hasValue, isTrue);
      expect(estado.hasError, isTrue);

      final sw = _switch(tester, _llaveCorreos);
      expect(sw.onChanged, isNull,
          reason: 'el valor es de antes del error: no es una lectura vigente');
      expect(sw.value, isFalse,
          reason:
              'y tampoco se muestra el valor viejo como si fuera el de ahora');

      await tester.tap(find.byKey(_llaveCorreos), warnIfMissed: false);
      await tester.pump();
      verifyNever(() => repo.setCorreosPromocionales(any(), any()));
    });

    testWidgets(
        'un valor y DESPUÉS una recarga → deshabilitado hasta que llega',
        (tester) async {
      await _montar(tester, repo: repo);
      doc.add(true);
      await _alDocumento(tester);
      expect(_switch(tester, _llaveCorreos).onChanged, isNotNull);

      contenedor(tester).invalidate(correosPromocionalesProvider);
      await _alDocumento(tester);

      // Precondición: carga CON el valor anterior a cuestas.
      final estado = contenedor(tester).read(correosPromocionalesProvider);
      expect(estado.hasValue, isTrue);
      expect(estado.isLoading, isTrue);

      final sw = _switch(tester, _llaveCorreos);
      expect(sw.onChanged, isNull);
      expect(sw.value, isFalse);
      await tester.tap(find.byKey(_llaveCorreos), warnIfMissed: false);
      await tester.pump();
      verifyNever(() => repo.setCorreosPromocionales(any(), any()));

      // Llega la lectura nueva y se habilita con SU valor.
      doc.add(false);
      await _alDocumento(tester);
      final despues = _switch(tester, _llaveCorreos);
      expect(despues.onChanged, isNotNull);
      expect(despues.value, isFalse);
    });

    group('cambio de cuenta', () {
      late StreamController<User?> auth;
      late StreamController<bool> docA;
      late StreamController<bool> docB;

      setUp(() {
        auth = StreamController<User?>.broadcast();
        docA = StreamController<bool>.broadcast();
        docB = StreamController<bool>.broadcast();
        addTearDown(auth.close);
        addTearDown(docA.close);
        addTearDown(docB.close);
        when(() => repo.watchCorreosPromocionales('uid-a'))
            .thenAnswer((_) => docA.stream);
        when(() => repo.watchCorreosPromocionales('uid-b'))
            .thenAnswer((_) => docB.stream);
      });

      Future<void> conCuentaA(WidgetTester tester) async {
        await _montar(tester, repo: repo, auth: auth.stream);
        auth.add(_MockUser('uid-a'));
        await _alDocumento(tester);
        docA.add(true);
        await _alDocumento(tester);
        expect(_switch(tester, _llaveCorreos).onChanged, isNotNull);
      }

      testWidgets(
          'mientras carga el documento del uid NUEVO: deshabilitado y sin '
          'escribir; después escribe sobre el uid nuevo', (tester) async {
        await conCuentaA(tester);

        auth.add(_MockUser('uid-b'));
        await _alDocumento(tester);

        // Precondición: el provider arrastra el valor de A mientras carga B.
        final estado = contenedor(tester).read(correosPromocionalesProvider);
        expect(estado.hasValue, isTrue);
        expect(estado.isLoading, isTrue);

        expect(_switch(tester, _llaveCorreos).onChanged, isNull);
        await tester.tap(find.byKey(_llaveCorreos), warnIfMissed: false);
        await tester.pump();
        verifyNever(() => repo.setCorreosPromocionales(any(), any()));

        // Llega el documento de B —apagado— y recién ahí se puede tocar.
        docB.add(false);
        await _alDocumento(tester);
        final sw = _switch(tester, _llaveCorreos);
        expect(sw.onChanged, isNotNull);
        expect(sw.value, isFalse, reason: 'el valor es el de B, no el de A');

        await tester.tap(find.byKey(_llaveCorreos));
        await tester.pump();
        verify(() => repo.setCorreosPromocionales('uid-b', true)).called(1);
        verifyNever(() => repo.setCorreosPromocionales('uid-a', any()));
      });

      testWidgets(
          'un toque justo después del cambio de cuenta, ANTES de que se '
          'redibuje, tampoco escribe', (tester) async {
        await conCuentaA(tester);

        // Sin `pump` entre medio: el widget todavía no se enteró de que cambió
        // la cuenta, así que el switch sigue habilitado con el valor de A.
        auth.add(_MockUser('uid-b'));
        await tester.tap(find.byKey(_llaveCorreos));
        await tester.pump();

        verifyNever(() => repo.setCorreosPromocionales(any(), any()));
      });
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

  // ──────────────────────────────────────────────────────────────────────────
  // Texto de ACCESIBILIDAD. A tamaños normales la pantalla entra entera y no
  // scrollea, así que estos dos defectos sólo aparecían con la letra más grande.
  // ──────────────────────────────────────────────────────────────────────────
  group('PrivacyScreen — con el texto de accesibilidad', () {
    late _MockUserRepository repo;

    setUp(() {
      repo = _MockUserRepository();
      when(() => repo.watchCorreosPromocionales(any()))
          .thenAnswer((_) => Stream<bool>.value(true));
    });

    // La barra flotante del shell: `Scaffold(extendBody: true)` la dibuja
    // ENCIMA del cuerpo y publica su alto en `MediaQuery.padding.bottom`.
    const barraKey = ValueKey('barra-flotante-del-shell');
    const altoBarra = 100.0;
    const barra = SizedBox(key: barraKey, height: altoBarra);

    Future<void> alFinalDelScroll(WidgetTester tester) async {
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -5000),
      );
      await tester.pumpAndSettle();
    }

    testWidgets(
        'al final del scroll la última línea queda POR ENCIMA de la barra '
        'flotante del shell', (tester) async {
      await _calentarFuentes(tester);
      await _montar(
        tester,
        repo: repo,
        size: const Size(390, 700),
        textScale: 3.0,
        barraFlotante: barra,
      );
      final l10n = AppL10n.of(tester.element(find.byType(PrivacyScreen)));

      await alFinalDelScroll(tester);

      final finDelTexto =
          tester.getBottomLeft(find.text(l10n.privacyPromoEmailsSubtitle)).dy;
      final topeDeLaBarra = tester.getTopLeft(find.byKey(barraKey)).dy;
      expect(
        finDelTexto,
        lessThanOrEqualTo(topeDeLaBarra),
        reason: 'con un margen fijo la última línea de la tarjeta de correos '
            'quedaba debajo del vidrio y no había más scroll para despejarla',
      );
    });

    testWidgets(
        'el margen inferior del scroll SUMA el inset del sistema, no es un '
        'número fijo', (tester) async {
      await _calentarFuentes(tester);
      await _montar(tester, repo: repo, insetInferior: 34);

      final scroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(
        scroll.padding!.resolve(TextDirection.ltr).bottom,
        AppSpacing.s20 + 34,
        reason: 'el margen base del repo más el `MediaQuery.padding.bottom`',
      );
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // El interruptor se apila DEBAJO del texto cuando la letra es muy grande.
  // Con el ícono, el texto y el switch en una fila, la columna del texto queda
  // más angosta que la palabra «promocionales» y Flutter la parte en el medio
  // («pr / omocional / es»).
  //
  // Se assertean POSICIONES RELATIVAS y la palabra contra sí misma, nunca un
  // ancho en píxeles: el ancho depende de la fuente y en tests no es el del
  // device.
  // ──────────────────────────────────────────────────────────────────────────
  group('PrivacyScreen — el switch se apila con la letra muy grande', () {
    late _MockUserRepository repo;

    setUp(() {
      repo = _MockUserRepository();
      when(() => repo.watchCorreosPromocionales(any()))
          .thenAnswer((_) => Stream<bool>.value(true));
    });

    Future<AppL10n> montarA(WidgetTester tester, double escala) async {
      await _calentarFuentes(tester);
      await _montar(tester, repo: repo, textScale: escala);
      return AppL10n.of(tester.element(find.byType(PrivacyScreen)));
    }

    // El umbral está en 1.5: por debajo todo queda como siempre, y 1.5 ya
    // apila. 1.35 es lo más grande que ofrece iOS sin accesibilidad.
    const casos = <(double, bool)>[
      (1.0, false),
      (1.35, false),
      (1.45, false),
      (1.5, true),
      (2.0, true),
      (3.0, true),
    ];

    for (final tarjeta in _tarjetas) {
      for (final (escala, apilado) in casos) {
        testWidgets(
            'tarjeta de ${tarjeta.nombre} a ${escala}x: el switch queda '
            '${apilado ? 'DEBAJO del texto' : 'AL COSTADO'}', (tester) async {
          final l10n = await montarA(tester, escala);

          final titulo = find.text(tarjeta.titulo(l10n));
          final subtitulo = find.text(tarjeta.subtitulo(l10n));
          final interruptor = find.byKey(tarjeta.llave);
          final icono = find.byIcon(tarjeta.icono);

          if (apilado) {
            expect(
              tester.getTopLeft(interruptor).dy,
              greaterThanOrEqualTo(tester.getBottomLeft(subtitulo).dy),
              reason: 'apilado: el switch arranca donde termina el texto',
            );
            expect(
              tester.getCenter(interruptor).dx,
              greaterThan(tester.view.physicalSize.width / 2),
              reason: 'y va alineado a la derecha',
            );
            // El texto toma todo el ancho: el ícono no le quita columna, se
            // va ARRIBA del título, pegado al mismo borde izquierdo.
            expect(
              tester.getBottomLeft(icono).dy,
              lessThanOrEqualTo(tester.getTopLeft(titulo).dy),
              reason: 'apilado: el ícono sube sobre el título',
            );
            expect(
              tester.getTopLeft(icono).dx,
              closeTo(tester.getTopLeft(titulo).dx, 0.01),
              reason: 'y comparte el borde izquierdo con el texto',
            );
          } else {
            expect(
              tester.getTopLeft(interruptor).dy,
              lessThan(tester.getBottomLeft(subtitulo).dy),
              reason: 'a escala normal el switch sigue al lado del texto, no '
                  'debajo',
            );
            expect(
              tester.getTopLeft(interruptor).dx,
              greaterThan(tester.getTopRight(titulo).dx),
              reason: '…y a la derecha de él',
            );
            expect(
              tester.getTopRight(icono).dx,
              lessThan(tester.getTopLeft(titulo).dx),
              reason: 'y el ícono, a la izquierda',
            );
          }
        });
      }
    }

    // 3.1 ≈ el tamaño más grande de iOS (accesibilidad 5). Va aparte del 3.0
    // porque ahí la palabra mide ~287 px y el texto, si el ícono le sigue
    // quitando columna, tiene 280: con 3.0 entraría por 2 px y el test no
    // distinguiría «el ícono sube» de «el ícono se queda en la fila».
    for (final escala in const [3.0, 3.1]) {
      testWidgets(
          'a ${escala}x el título «Correos promocionales» no parte ninguna '
          'palabra', (tester) async {
        final l10n = await montarA(tester, escala);

        final parrafo = tester.renderObject<RenderParagraph>(
          find.text(l10n.privacyPromoEmailsTitle),
        );
        double anchoDe(String palabra) {
          final pintor = TextPainter(
            text: TextSpan(text: palabra, style: parrafo.text.style),
            textDirection: TextDirection.ltr,
            textScaler: parrafo.textScaler,
          )..layout();
          final ancho = pintor.width;
          pintor.dispose();
          return ancho;
        }

        final palabraMasLarga = l10n.privacyPromoEmailsTitle
            .split(' ')
            .map(anchoDe)
            .reduce(math.max);

        expect(
          parrafo.size.width,
          greaterThanOrEqualTo(palabraMasLarga),
          reason: 'el texto tiene que tener, como mínimo, el ancho de su '
              'palabra más larga; si no, Flutter la corta en el medio',
        );
      });
    }
  });
}

/// Los datos de cada tarjeta de la pantalla, para probar las dos igual.
class _Tarjeta {
  const _Tarjeta(
    this.nombre,
    this.llave,
    this.icono,
    this.titulo,
    this.subtitulo,
  );

  final String nombre;
  final Key llave;
  final IconData icono;
  final String Function(AppL10n) titulo;
  final String Function(AppL10n) subtitulo;
}

final _tarjetas = <_Tarjeta>[
  _Tarjeta(
    'analítica',
    _llaveAnalitica,
    TreinoIcon.shieldCheck,
    (l10n) => l10n.privacyAnalyticsTitle,
    (l10n) => l10n.privacyAnalyticsSubtitle,
  ),
  _Tarjeta(
    'correos',
    _llaveCorreos,
    TreinoIcon.mail,
    (l10n) => l10n.privacyPromoEmailsTitle,
    (l10n) => l10n.privacyPromoEmailsSubtitle,
  ),
];
