import 'dart:js_interop';

import 'package:web/web.dart' as web;

// Implementación web de `BeforeUnloadGuard`. La importa
// `before_unload_guard.dart` con un conditional import; fuera de web se usa
// `before_unload_guard_stub.dart`.
//
// `dart:js_interop` y `package:web` no se pueden probar en la VM: lo que se
// puede probar —cuándo se prende y cuándo se apaga— vive en la pantalla que lo
// pide, contra un guard de mentira.

bool _armado = false;

/// El mismo objeto en `add` y en `remove`: `removeEventListener` compara por
/// identidad, y un `.toJS` nuevo en cada llamada nunca lo sacaría.
final JSFunction _alDescargar = ((web.BeforeUnloadEvent evento) {
  // `preventDefault` es lo que hoy pide el estándar; `returnValue` es el modo
  // viejo, y sigue haciendo falta en algunos navegadores. El texto que se le
  // pone se ignora: el navegador muestra el suyo.
  evento.preventDefault();
  evento.returnValue = '';
}).toJS;

void armBeforeUnload() {
  if (_armado) return;
  _armado = true;
  web.window.addEventListener('beforeunload', _alDescargar);
}

void disarmBeforeUnload() {
  if (!_armado) return;
  _armado = false;
  web.window.removeEventListener('beforeunload', _alDescargar);
}
