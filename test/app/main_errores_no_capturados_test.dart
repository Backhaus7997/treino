// El `runZonedGuarded` de `main.dart` era un `if (!kIsWeb)` sin `else`: en web
// un error async no capturado se descartaba sin dejar rastro, ni en la consola
// (QA E2E 2026-11-06, #1698). Crashlytics no soporta web, así que ahí se
// IMPRIME; en mobile sigue yendo a Crashlytics como fatal.
//
// `manejarErrorNoCapturado` recibe la plataforma y el registrador por
// parámetro porque el real necesita Firebase, y `kIsWeb` es const.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/main.dart' show manejarErrorNoCapturado;

void main() {
  late List<String?> impreso;
  late DebugPrintCallback original;

  setUp(() {
    impreso = [];
    original = debugPrint;
    debugPrint = (message, {wrapWidth}) => impreso.add(message);
  });
  tearDown(() => debugPrint = original);

  test('en web el error se IMPRIME, con su stack, y no va a Crashlytics', () {
    final stack = StackTrace.fromString('#0 fallaAsync (demo.dart:1:1)');
    var registrado = false;

    manejarErrorNoCapturado(
      StateError('se cayó un future sin await'),
      stack,
      web: true,
      registrarFatal: (_, __) => registrado = true,
    );

    expect(impreso, hasLength(1));
    expect(impreso.single, contains('[uncaught]'));
    expect(impreso.single, contains('se cayó un future sin await'));
    expect(impreso.single, contains('fallaAsync'));
    expect(registrado, isFalse, reason: 'Crashlytics no soporta web');
  });

  test('en mobile va a Crashlytics como fatal y no imprime', () {
    final error = StateError('boom');
    final stack = StackTrace.fromString('#0 boom (demo.dart:1:1)');
    final registrados = <(Object, StackTrace)>[];

    manejarErrorNoCapturado(
      error,
      stack,
      web: false,
      registrarFatal: (e, s) => registrados.add((e, s)),
    );

    expect(registrados, [(error, stack)]);
    expect(impreso, isEmpty);
  });

  test('main() le pasa ESTE handler al runZonedGuarded, sin uno inline', () {
    // El handler inline era justo donde se tragaba el error. Mirar el código
    // es la única forma de saber que `main()` lo usa: no se puede correr
    // `main()` sin Firebase.
    final src = File('lib/main.dart')
        .readAsStringSync()
        .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');

    expect(src, contains('}, manejarErrorNoCapturado);'));
    expect(src, isNot(contains('}, (error, stack) {')));
  });
}
