// Los dobles de abajo implementan clases selladas de cloud_firestore a propósito
// (mismo precedente que feed_following_confirmed_test.dart).
// ignore_for_file: subtype_of_sealed_class

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/app_update/application/app_update_providers.dart';
import 'package:treino/features/app_update/domain/min_version_config.dart';
import 'package:treino/features/app_update/presentation/app_update_gate.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Firestore que explota en el acto: simula un error de plataforma.
class _FirestoreRoto extends Fake implements FirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
}

/// Firestore cuya lectura no termina nunca: simula una red colgada.
class _FirestoreColgado extends Fake implements FirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String path) =>
      _ColeccionColgada();
}

class _ColeccionColgada extends Fake
    implements CollectionReference<Map<String, dynamic>> {
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) => _DocColgado();
}

class _DocColgado extends Fake
    implements DocumentReference<Map<String, dynamic>> {
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) =>
      Completer<DocumentSnapshot<Map<String, dynamic>>>().future;
}

const _appKey = Key('app_proxima');
const _pantallaKey = Key('update_required_screen');

Future<void> _montar(
  WidgetTester tester, {
  required FirebaseFirestore firestore,
  required AppUpdatePlatform? platform,
  required String? version,
  Future<bool> Function(Uri)? abrirUrl,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(firestore),
        appUpdatePlatformProvider.overrideWithValue(platform),
        installedVersionProvider.overrideWith((_) async => version),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: AppUpdateGate(
          abrirUrl: abrirUrl,
          child: const Scaffold(body: Text('app', key: _appKey)),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

Future<FakeFirebaseFirestore> _conMinimo(Map<String, dynamic>? data) async {
  final fs = FakeFirebaseFirestore();
  if (data != null) {
    await fs.collection('app_config').doc('min_version').set(data);
  }
  return fs;
}

const _doc = {
  'minVersion': {'ios': '1.4.0', 'android': '1.4.0'},
  'storeUrl': {'ios': 'https://apps.apple.com/app/id1'},
};

void main() {
  group('AppUpdateGate — bloquea', () {
    testWidgets('versión menor: pantalla bloqueante con botón a la tienda',
        (tester) async {
      Uri? abierta;
      await _montar(
        tester,
        firestore: await _conMinimo(_doc),
        platform: AppUpdatePlatform.ios,
        version: '1.3.0',
        abrirUrl: (u) async {
          abierta = u;
          return true;
        },
      );
      expect(find.byKey(_pantallaKey), findsOneWidget);
      expect(find.text('ACTUALIZÁ LA APP'), findsOneWidget);
      expect(find.byKey(_appKey), findsNothing);

      await tester.tap(find.byKey(const Key('update_required_cta')));
      await tester.pump();
      expect(abierta.toString(), 'https://apps.apple.com/app/id1');
      expect(find.byKey(const Key('update_required_error')), findsNothing);
    });

    testWidgets('si la tienda no abre, avisa en la pantalla', (tester) async {
      await _montar(
        tester,
        firestore: await _conMinimo(_doc),
        platform: AppUpdatePlatform.android,
        version: '1.0.0',
        abrirUrl: (_) async => false,
      );
      await tester.tap(find.byKey(const Key('update_required_cta')));
      await tester.pump();
      expect(find.byKey(const Key('update_required_error')), findsOneWidget);
    });
  });

  group('AppUpdateGate — deja pasar', () {
    testWidgets('versión igual al mínimo', (tester) async {
      await _montar(
        tester,
        firestore: await _conMinimo(_doc),
        platform: AppUpdatePlatform.ios,
        version: '1.4.0',
      );
      expect(find.byKey(_appKey), findsOneWidget);
      expect(find.byKey(_pantallaKey), findsNothing);
    });

    testWidgets('versión mayor al mínimo', (tester) async {
      await _montar(
        tester,
        firestore: await _conMinimo(_doc),
        platform: AppUpdatePlatform.ios,
        version: '2.0.0',
      );
      expect(find.byKey(_appKey), findsOneWidget);
    });

    testWidgets('documento ausente: falla abierto', (tester) async {
      await _montar(
        tester,
        firestore: await _conMinimo(null),
        platform: AppUpdatePlatform.ios,
        version: '0.0.1',
      );
      expect(find.byKey(_appKey), findsOneWidget);
      expect(find.byKey(_pantallaKey), findsNothing);
    });

    testWidgets('documento malformado: falla abierto', (tester) async {
      await _montar(
        tester,
        firestore: await _conMinimo({
          'minVersion': {'ios': 'basura'},
        }),
        platform: AppUpdatePlatform.ios,
        version: '0.0.1',
      );
      expect(find.byKey(_appKey), findsOneWidget);
    });

    testWidgets('error de Firestore: falla abierto', (tester) async {
      await _montar(
        tester,
        firestore: _FirestoreRoto(),
        platform: AppUpdatePlatform.ios,
        version: '0.0.1',
      );
      expect(find.byKey(_appKey), findsOneWidget);
      expect(find.byKey(_pantallaKey), findsNothing);
    });

    testWidgets('lectura colgada (offline): no bloquea y vence el timeout',
        (tester) async {
      await _montar(
        tester,
        firestore: _FirestoreColgado(),
        platform: AppUpdatePlatform.ios,
        version: '0.0.1',
      );
      // Mientras espera, la app ya se ve.
      expect(find.byKey(_appKey), findsOneWidget);
      await tester.pump(kMinVersionTimeout + const Duration(seconds: 1));
      expect(find.byKey(_appKey), findsOneWidget);
      expect(find.byKey(_pantallaKey), findsNothing);
    });

    testWidgets('versión instalada ilegible: falla abierto', (tester) async {
      await _montar(
        tester,
        firestore: await _conMinimo(_doc),
        platform: AppUpdatePlatform.ios,
        version: null,
      );
      expect(find.byKey(_appKey), findsOneWidget);
    });

    testWidgets('web / sin plataforma: nunca se gatea ni se lee Firestore',
        (tester) async {
      await _montar(
        tester,
        // Si leyera, explotaría; y la versión es menor al mínimo.
        firestore: _FirestoreRoto(),
        platform: null,
        version: '0.0.1',
      );
      expect(find.byKey(_appKey), findsOneWidget);
      expect(find.byKey(_pantallaKey), findsNothing);
    });
  });

  group('appUpdatePlatformProvider', () {
    // `kIsWeb` es una const del compilador y no se puede forzar en la VM: el
    // caso web se cubre con `platform: null` arriba (mismo valor que devuelve
    // el provider con kIsWeb) y la guarda es la primera línea del provider.
    for (final (target, esperado) in [
      (TargetPlatform.iOS, AppUpdatePlatform.ios),
      (TargetPlatform.android, AppUpdatePlatform.android),
      (TargetPlatform.macOS, null),
      (TargetPlatform.linux, null),
      (TargetPlatform.windows, null),
    ]) {
      test('$target -> $esperado', () {
        debugDefaultTargetPlatformOverride = target;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final c = ProviderContainer();
        addTearDown(c.dispose);
        expect(c.read(appUpdatePlatformProvider), esperado);
      });
    }
  });
}
