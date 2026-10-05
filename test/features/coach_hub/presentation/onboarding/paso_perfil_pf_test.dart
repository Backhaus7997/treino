import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/utils/geohash.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/auth/data/auth_service.dart';
import 'package:treino/features/coach_hub/application/lugar_search_providers.dart';
import 'package:treino/features/coach_hub/data/lugar_search_service.dart';
import 'package:treino/features/coach_hub/domain/perfil_pf_validators.dart';
import 'package:treino/features/coach_hub/presentation/onboarding/completar_perfil_screen.dart';
import 'package:treino/features/coach_hub/presentation/widgets/button/treino_button.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/l10n/app_l10n.dart';

class _AuthServiceMudo implements AuthService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// Cuenta las escrituras: «un solo batch» y «no escribe nada» se miden acá.
class _RepoContador extends UserRepository {
  _RepoContador({required super.firestore});

  int updates = 0;
  Map<String, Object?>? ultimoPartial;

  @override
  Future<void> update(
    String uid,
    Map<String, Object?> partial, {
    bool grantLocationConsent = false,
  }) {
    updates++;
    ultimoPartial = partial;
    return super
        .update(uid, partial, grantLocationConsent: grantLocationConsent);
  }
}

const _bioValida = 'Entreno fuerza y movilidad hace diez años.';

Map<String, Object?> _lugar(
        String nombre, String dir, double lat, double lng) =>
    {
      'displayName': {'text': nombre, 'languageCode': 'es'},
      'formattedAddress': dir,
      'location': {'latitude': lat, 'longitude': lng},
    };

http.Response _json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

const _bioKey = Key('onboarding-pf-bio');
const _tarifaKey = Key('onboarding-pf-tarifa');
const _onlineKey = Key('onboarding-pf-online');
const _busquedaKey = Key('onboarding-pf-lugar-busqueda');
const _buscarKey = Key('onboarding-pf-lugar-buscar');
const _reintentarKey = Key('onboarding-pf-lugar-reintentar');
const _finalizarKey = Key('onboarding-pf-finalizar');
const _consentKey = Key('onboarding-pf-consent');

void main() {
  late FakeFirebaseFirestore firestore;
  late _RepoContador repo;
  late Future<http.Response> Function(http.Request) places;
  late String apiKey;
  late int requests;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = _RepoContador(firestore: firestore);
    requests = 0;
    apiKey = 'KEY-DE-PRUEBA';
    places = (_) async => _json({
          'places': [
            _lugar(
              'Casa Simpson',
              'Av. Siempreviva 742, Springfield',
              -34.603722,
              -58.381592,
            ),
            _lugar('Otro lugar', 'Calle Falsa 123', -34.6, -58.4),
          ],
        });
  });

  /// Perfil del paso `pf`: con edad y nombre, sin perfil profesional.
  Future<void> sembrar({Map<String, Object?>? extra}) async {
    final now = DateTime.utc(2026, 1, 1);
    await firestore.collection('users').doc('u1').set({
      'uid': 'u1',
      'email': 'pf@test.com',
      'displayName': 'Mateo',
      'role': 'trainer',
      'createdAt': now,
      'updatedAt': now,
      'bornAt': DateTime.utc(1990, 5, 20),
      ...?extra,
    });
  }

  Future<void> pump(
    WidgetTester tester, {
    required ThemeData theme,
    Size size = const Size(1280, 1800),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
          userRepositoryProvider.overrideWithValue(repo),
          userProfileProvider.overrideWith((ref) => repo.watch('u1')),
          authServiceProvider.overrideWithValue(_AuthServiceMudo()),
          lugarSearchServiceProvider.overrideWith((ref) {
            final client = MockClient((req) {
              requests++;
              return places(req);
            });
            return LugarSearchService(httpClient: client, apiKey: apiKey);
          }),
        ],
        child: MaterialApp(
          theme: theme,
          locale: const Locale('es', 'AR'),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          home: CompletarPerfilScreen(cerrarSesion: () async {}),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<Map<String, Object?>> usuario() async =>
      (await firestore.collection('users').doc('u1').get()).data()!;

  AppL10n l10nDe(WidgetTester tester) =>
      AppL10n.of(tester.element(find.byType(CompletarPerfilScreen)));

  Future<void> escribir(WidgetTester tester, Key key, String texto) async {
    await tester.enterText(find.byKey(key), texto);
    await tester.pump();
  }

  Future<void> elegirEspecialidad(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pump();
  }

  Future<void> llenarBasicos(
    WidgetTester tester, {
    bool online = false,
    bool especialidad = true,
  }) async {
    await escribir(tester, _bioKey, _bioValida);
    await escribir(tester, _tarifaKey, '28000');
    if (especialidad) await elegirEspecialidad(tester, 'Yoga');
    if (online) {
      await tester.tap(find.byKey(_onlineKey));
      await tester.pump();
    }
  }

  /// `pumpAndSettle` no sirve: al completar el perfil la pantalla pasa a la
  /// vista de carga, que anima sin parar.
  Future<void> asentar(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> buscarYElegir(WidgetTester tester, {int indice = 0}) async {
    await escribir(tester, _busquedaKey, 'Av. Siempreviva 742');
    await tester.tap(find.byKey(_buscarKey));
    await asentar(tester);
    await tester.tap(find.byKey(Key('onboarding-pf-lugar-resultado-$indice')));
    await tester.pump();
  }

  bool finalizarHabilitado(WidgetTester tester) =>
      tester.widget<TreinoButton>(find.byKey(_finalizarKey)).onPressed != null;

  Future<void> finalizar(WidgetTester tester) async {
    await tester.tap(find.byKey(_finalizarKey));
    await asentar(tester);
  }

  final temas = <String, ThemeData Function()>{
    'dark': AppTheme.dark,
    'light': AppTheme.light,
  };

  for (final entry in temas.entries) {
    group('PasoPerfilPf (${entry.key})', () {
      // SCENARIO-CHW-ONB-033
      testWidgets('rangos de bio: 19 y 281 fallan; 20 y 280 pasan',
          (tester) async {
        await sembrar();
        await pump(tester, theme: entry.value());

        for (final largo in [19, 281]) {
          await escribir(tester, _bioKey, 'a' * largo);
          expect(find.text(validarBio('a' * largo)!), findsOneWidget,
              reason: 'bio de $largo');
        }
        for (final largo in [20, 280]) {
          await escribir(tester, _bioKey, 'a' * largo);
          expect(validarBio('a' * largo), isNull);
          expect(find.text(validarBio('a' * 19)!), findsNothing);
          expect(find.text(validarBio('a' * 281)!), findsNothing);
        }
      });

      // SCENARIO-CHW-ONB-034
      testWidgets('rangos de tarifa: 499 y 1000000 fallan; 500 y 999999 pasan',
          (tester) async {
        await sembrar();
        await pump(tester, theme: entry.value());
        await escribir(tester, _bioKey, _bioValida);
        await elegirEspecialidad(tester, 'Yoga');
        await tester.tap(find.byKey(_onlineKey));
        await tester.pump();

        for (final v in ['499', '1000000']) {
          await escribir(tester, _tarifaKey, v);
          expect(find.text(validarPrecio(v)!), findsOneWidget,
              reason: 'tarifa $v');
          expect(finalizarHabilitado(tester), isFalse, reason: 'tarifa $v');
        }
        for (final v in ['500', '999999']) {
          await escribir(tester, _tarifaKey, v);
          expect(find.text(validarPrecio('499')!), findsNothing);
          expect(find.text(validarPrecio('1000000')!), findsNothing);
          expect(finalizarHabilitado(tester), isTrue, reason: 'tarifa $v');
        }
      });

      // SCENARIO-CHW-ONB-035
      testWidgets('sin especialidad no se puede guardar', (tester) async {
        await sembrar();
        await pump(tester, theme: entry.value());
        await llenarBasicos(tester, online: true, especialidad: false);

        expect(finalizarHabilitado(tester), isFalse);
        await tester.tap(find.byKey(_finalizarKey), warnIfMissed: false);
        await tester.pump();
        expect(repo.updates, 0);

        await elegirEspecialidad(tester, 'Yoga');
        expect(finalizarHabilitado(tester), isTrue);
      });

      // SCENARIO-CHW-ONB-036
      testWidgets('sin modalidad no permite finalizar y lo explica',
          (tester) async {
        await sembrar();
        await pump(tester, theme: entry.value());
        await llenarBasicos(tester);

        expect(finalizarHabilitado(tester), isFalse);
        expect(find.text(l10nDe(tester).coachHubOnboardingPfModalityRequired),
            findsOneWidget);
        expect(repo.updates, 0);
      });

      // SCENARIO-CHW-ONB-037
      testWidgets('solo online completa, sin ubicaciones ni consentimiento',
          (tester) async {
        await sembrar();
        await pump(tester, theme: entry.value());
        await llenarBasicos(tester, online: true);

        expect(finalizarHabilitado(tester), isTrue);
        await finalizar(tester);

        expect(repo.updates, 1);
        final d = await usuario();
        expect(d['trainerOffersOnline'], isTrue);
        expect(d['trainerLocations'], isEmpty);
        expect(d['trainerBio'], _bioValida);
        expect(d['trainerSpecialty'], 'yoga');
        expect(d['trainerMonthlyRate'], 28000);
        expect(d['trainerLocationConsentAt'], isNull);
        expect(find.byKey(_consentKey), findsNothing);
      });

      // SCENARIO-CHW-ONB-038 / 039 / 041
      testWidgets(
          'dirección → resultados → elegir → guardar: TrainerLocation custom '
          'exacta y consentimiento en UN batch', (tester) async {
        await sembrar();
        await pump(tester, theme: entry.value());
        await llenarBasicos(tester);
        await buscarYElegir(tester);

        expect(finalizarHabilitado(tester), isTrue);
        await tester.tap(find.byKey(_finalizarKey));
        await asentar(tester);
        expect(find.byKey(_consentKey), findsOneWidget);
        await tester.tap(
            find.text(l10nDe(tester).profileEditTrainerConsentConfirmAccept));
        await asentar(tester);

        expect(repo.updates, 1);
        final d = await usuario();
        final locs = d['trainerLocations'] as List;
        expect(locs, hasLength(1));
        final l = locs.single as Map;
        expect(l['type'], 'custom');
        expect((l['id'] as String).startsWith('custom-'), isTrue);
        expect(l['customLabel'], 'Casa Simpson');
        expect(l['lat'], -34.603722);
        expect(l['lng'], -58.381592);
        expect(l['geohash'], geohash5(-34.603722, -58.381592));
        expect(l['gymId'], isNull);
        expect(d['trainerGeohashes'], [geohash5(-34.603722, -58.381592)]);
        expect(d['trainerOffersOnline'], isFalse);
        expect(d['trainerLocationConsentAt'], isNotNull);
        expect(d['trainerLocationConsentPromptedAt'], isNotNull);
        final publico = (await firestore
                .collection('trainerPublicProfiles')
                .doc('u1')
                .get())
            .data();
        expect((publico!['trainerLocations'] as List), hasLength(1));
        expect(publico['displayName'], 'Mateo');
      });

      testWidgets('sin displayName en Places el label es la dirección',
          (tester) async {
        places = (_) async => _json({
              'places': [
                {
                  'formattedAddress': 'Calle Sin Nombre 1',
                  'location': {'latitude': -34.5, 'longitude': -58.5},
                },
              ],
            });
        await sembrar();
        await pump(tester, theme: entry.value());
        await llenarBasicos(tester);
        await buscarYElegir(tester);
        await tester.tap(find.byKey(_finalizarKey));
        await asentar(tester);
        await tester.tap(
            find.text(l10nDe(tester).profileEditTrainerConsentConfirmAccept));
        await asentar(tester);

        final l = ((await usuario())['trainerLocations'] as List).single as Map;
        expect(l['customLabel'], 'Calle Sin Nombre 1');
      });

      // SCENARIO-CHW-ONB-040
      testWidgets('texto libre sin elegir resultado no habilita guardar',
          (tester) async {
        await sembrar();
        await pump(tester, theme: entry.value());
        await llenarBasicos(tester);
        await escribir(tester, _busquedaKey, 'Av. Siempreviva 742');

        expect(finalizarHabilitado(tester), isFalse);
        await tester.tap(find.byKey(_finalizarKey), warnIfMissed: false);
        await tester.pump();
        expect(repo.updates, 0);

        // Buscar sin elegir tampoco: los resultados no son ubicaciones.
        await tester.tap(find.byKey(_buscarKey));
        await asentar(tester);
        expect(finalizarHabilitado(tester), isFalse);
        expect(repo.updates, 0);
      });

      testWidgets('búsqueda sin resultados dice que no encontró y no guarda',
          (tester) async {
        places = (_) async => _json({'places': []});
        await sembrar();
        await pump(tester, theme: entry.value());
        await llenarBasicos(tester);
        await escribir(tester, _busquedaKey, 'zzzzzz');
        await tester.tap(find.byKey(_buscarKey));
        await asentar(tester);

        expect(find.text(l10nDe(tester).coachHubOnboardingPfLocationEmpty),
            findsOneWidget);
        expect(finalizarHabilitado(tester), isFalse);
      });

      testWidgets('buscar exige 3 caracteres y no pega a la red antes',
          (tester) async {
        await sembrar();
        await pump(tester, theme: entry.value());

        await escribir(tester, _busquedaKey, 'Av');
        final boton = tester.widget<TreinoButton>(find.byKey(_buscarKey));
        expect(boton.onPressed, isNull);
        expect(requests, 0);
      });

      testWidgets('Enter dispara la búsqueda', (tester) async {
        await sembrar();
        await pump(tester, theme: entry.value());
        await escribir(tester, _busquedaKey, 'Av. Siempreviva 742');
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await asentar(tester);

        expect(requests, 1);
        expect(find.byKey(const Key('onboarding-pf-lugar-resultado-0')),
            findsOneWidget);
      });

      // SCENARIO-CHW-ONB-041
      testWidgets(
          'cancelar el consentimiento no escribe y deja el form intacto',
          (tester) async {
        await sembrar();
        await pump(tester, theme: entry.value());
        await llenarBasicos(tester);
        await buscarYElegir(tester);

        await tester.tap(find.byKey(_finalizarKey));
        await asentar(tester);
        await tester.tap(
            find.text(l10nDe(tester).profileEditTrainerConsentConfirmCancel));
        await asentar(tester);

        expect(repo.updates, 0);
        final d = await usuario();
        expect(d['trainerBio'], isNull);
        expect(d['trainerLocationConsentAt'], isNull);
        expect(find.byKey(_consentKey), findsNothing);
        // Form intacto: bio, tarifa y el lugar elegido siguen ahí.
        expect(find.text(_bioValida), findsOneWidget);
        expect(find.text('28000'), findsOneWidget);
        expect(find.text('Casa Simpson'), findsOneWidget);
        expect(finalizarHabilitado(tester), isTrue);
      });

      // SCENARIO-CHW-ONB-042
      testWidgets('consentimiento previo no se pregunta ni se pisa',
          (tester) async {
        final antes = DateTime.utc(2026, 3, 3);
        await sembrar(extra: {
          'trainerLocationConsentAt': antes,
          'trainerLocationConsentPromptedAt': antes,
        });
        await pump(tester, theme: entry.value());
        await llenarBasicos(tester);
        await buscarYElegir(tester);
        await finalizar(tester);

        expect(find.byKey(_consentKey), findsNothing);
        expect(repo.updates, 1);
        final d = await usuario();
        expect((d['trainerLocations'] as List), hasLength(1));
        // UTC a propósito: el Timestamp vuelve en hora local.
        final consentAt = (d['trainerLocationConsentAt'] as Timestamp).toDate();
        expect(consentAt.toUtc(), antes);
      });

      // SCENARIO-CHW-ONB-044
      testWidgets('error de red: mensaje visible con reintentar que funciona',
          (tester) async {
        var falla = true;
        places = (_) async => falla
            ? _json({'error': 'x'}, 503)
            : _json({
                'places': [_lugar('Casa Simpson', 'Av. 742', -34.6, -58.38)],
              });
        await sembrar();
        await pump(tester, theme: entry.value());
        await llenarBasicos(tester);
        await escribir(tester, _busquedaKey, 'Av. Siempreviva 742');
        await tester.tap(find.byKey(_buscarKey));
        await asentar(tester);

        final l10n = l10nDe(tester);
        expect(find.text(l10n.coachHubOnboardingPfLocationNetworkError),
            findsOneWidget);
        expect(find.text(l10n.coachHubOnboardingPfLocationEmpty), findsNothing);
        expect(find.byKey(_reintentarKey), findsOneWidget);

        falla = false;
        await tester.tap(find.byKey(_reintentarKey));
        await asentar(tester);
        expect(find.byKey(const Key('onboarding-pf-lugar-resultado-0')),
            findsOneWidget);
        expect(find.text(l10n.coachHubOnboardingPfLocationNetworkError),
            findsNothing);
      });

      testWidgets(
          'key de Places vacía: error de configuración, NUNCA «sin resultados»; '
          'online completa igual', (tester) async {
        apiKey = '';
        await sembrar();
        await pump(tester, theme: entry.value());
        await llenarBasicos(tester);
        await escribir(tester, _busquedaKey, 'Av. Siempreviva 742');
        await tester.tap(find.byKey(_buscarKey));
        await asentar(tester);

        final l10n = l10nDe(tester);
        expect(find.text(l10n.coachHubOnboardingPfLocationConfigError),
            findsOneWidget);
        expect(find.text(l10n.coachHubOnboardingPfLocationEmpty), findsNothing);
        // Reintentar contra una key ausente nunca puede funcionar: no se ofrece.
        expect(find.byKey(_reintentarKey), findsNothing);
        expect(find.textContaining('KEY'), findsNothing);
        expect(finalizarHabilitado(tester), isFalse);

        await tester.tap(find.byKey(_onlineKey));
        await tester.pump();
        expect(finalizarHabilitado(tester), isTrue);
        await finalizar(tester);
        expect(repo.updates, 1);
        expect((await usuario())['trainerOffersOnline'], isTrue);
      });

      testWidgets(
          'un lugar legacy de tipo gym (sin customLabel) no es una fila en blanco',
          (tester) async {
        await sembrar(extra: {
          'trainerLocations': [
            {
              'id': 'gym-1',
              'type': 'gym',
              'gymId': 'g1',
              'lat': -34.6,
              'lng': -58.4,
              'geohash': '69y7p',
            },
          ],
        });
        await pump(tester, theme: entry.value());

        final l10n = l10nDe(tester);
        expect(find.text(l10n.coachHubOnboardingPfLocationGymFallback),
            findsOneWidget);
        expect(l10n.coachHubOnboardingPfLocationGymFallback, isNotEmpty);
      });

      testWidgets('quitar un lugar lo saca de la lista y de la escritura',
          (tester) async {
        await sembrar();
        await pump(tester, theme: entry.value());
        await llenarBasicos(tester, online: true);
        await buscarYElegir(tester, indice: 0);
        await buscarYElegir(tester, indice: 1);
        expect(find.text('Casa Simpson'), findsOneWidget);
        expect(find.text('Otro lugar'), findsOneWidget);

        await tester.tap(find.byKey(const Key('onboarding-pf-lugar-quitar-0')));
        await tester.pump();
        expect(find.text('Casa Simpson'), findsNothing);
        expect(find.text('Otro lugar'), findsOneWidget);
      });

      // SCENARIO-CHW-ONB-046
      testWidgets('solo falta el PF: único paso, con lo ya cargado precargado',
          (tester) async {
        // Falta solo la bio: especialidad, tarifa y modalidad ya están.
        await sembrar(extra: {
          'trainerSpecialty': 'yoga',
          'trainerMonthlyRate': 28000,
          'trainerOffersOnline': true,
        });
        await pump(tester, theme: entry.value());

        expect(find.byKey(_bioKey), findsOneWidget);
        expect(find.text('28000'), findsOneWidget);
        final sw = tester.widget<Switch>(find.byKey(_onlineKey));
        expect(sw.value, isTrue);
        expect(find.text('FECHA DE NACIMIENTO'), findsNothing);
        expect(find.text('NOMBRE'), findsNothing);
      });

      // SCENARIO-CHW-ONB-047
      testWidgets('nunca pide ni escribe campos de alumno', (tester) async {
        await sembrar();
        await pump(tester, theme: entry.value());
        for (final prohibido in [
          'GIMNASIO',
          'EXPERIENCIA',
          'GÉNERO',
          'PESO',
          'ALTURA',
          'FOTO',
          'AVATAR',
        ]) {
          expect(find.textContaining(prohibido), findsNothing,
              reason: prohibido);
        }
        await llenarBasicos(tester, online: true);
        await finalizar(tester);

        final claves = repo.ultimoPartial!.keys.toSet();
        expect(claves, {
          'displayName',
          'trainerBio',
          'trainerSpecialty',
          'trainerMonthlyRate',
          'trainerOffersOnline',
          'trainerLocations',
          'trainerGeohashes',
        });
        expect(claves.contains('role'), isFalse);
      });
    });
  }

  // SCENARIO-CHW-ONB-053
  for (final entry in temas.entries) {
    for (final ancho in [360.0, 1280.0]) {
      testWidgets('sin overflow a ${ancho.toInt()} px (${entry.key})',
          (tester) async {
        await sembrar();
        await pump(
          tester,
          theme: entry.value(),
          size: Size(ancho, 2600),
        );
        await llenarBasicos(tester);
        await buscarYElegir(tester);
        await buscarYElegir(tester, indice: 1);

        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('desmontar con una búsqueda en vuelo no lanza al terminar',
      (tester) async {
    final completer = Completer<http.Response>();
    places = (_) => completer.future;
    await sembrar();
    await pump(tester, theme: AppTheme.light());
    await escribir(tester, _busquedaKey, 'Av. Siempreviva 742');
    await tester.tap(find.byKey(_buscarKey));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    completer.complete(_json({'places': []}));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}
