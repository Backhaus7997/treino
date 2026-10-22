// Mueve el ciclo de vida de la app como lo hace el sistema: de a UN paso.
//
// `handleAppLifecycleStateChanged(paused)` desde `resumed` rompe un assert del
// framework (`AppLifecycleListener`) en cuanto hay un widget app montado: el
// sistema nunca salta, pasa por `inactive` y `hidden`. Los tests del aviso de
// fin de descanso (#1617) necesitan irse y volver varias veces, así que
// recorren la misma escalera que Android e iOS.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _escalera = [
  AppLifecycleState.resumed,
  AppLifecycleState.inactive,
  AppLifecycleState.hidden,
  AppLifecycleState.paused,
];

/// Lleva la app, paso a paso, al estado [destino].
void irA(TestWidgetsFlutterBinding binding, AppLifecycleState destino) {
  var i =
      _escalera.indexOf(binding.lifecycleState ?? AppLifecycleState.resumed);
  final j = _escalera.indexOf(destino);
  while (i != j) {
    i += j > i ? 1 : -1;
    binding.handleAppLifecycleStateChanged(_escalera[i]);
  }
}

/// La app deja de verse (pantalla bloqueada o a otra app).
void aSegundoPlano(TestWidgetsFlutterBinding binding) =>
    irA(binding, AppLifecycleState.paused);

/// La app vuelve al frente.
void aPrimerPlano(TestWidgetsFlutterBinding binding) =>
    irA(binding, AppLifecycleState.resumed);
