// ─────────────────────────────────────────────────────────────────────────────
// Acceso ADMIN al emulador de Firestore para las suites E2E
// ─────────────────────────────────────────────────────────────────────────────
//
// Las suites manejan la app con el SDK de cliente, que pasa por las reglas. Hay
// cosas que una suite necesita leer o preparar y que las reglas, con razón, no
// le dejan a ningún cliente:
//
//   • `mail_queue`: el código de verificación del mail sólo existe en claro en
//     los `params` del mail encolado (`verificaciones_de_mail` guarda el hash).
//   • `app_config/email_gate`: el interruptor del gate del mail lo prende el
//     equipo desde la consola, no la app.
//
// Para eso está la API REST del emulador con `Authorization: Bearer owner`, que
// es el bypass de reglas que el emulador documenta para tests. SÓLO existe en
// el emulador: contra un Firestore real ese token es inválido y la request da
// 401. Igual, el host está fijo en `localhost` a propósito — este archivo no
// sabe hablar con otro lado.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:treino/core/firebase/emuladores.dart';
import 'package:treino/firebase_options.dart';

/// Mismo host y puerto que `conectarEmuladores()`: el puerto es la constante
/// que usa ella.
const String _host = 'localhost';
const int _port = kPuertoEmuladorFirestore;

String get _docsBase =>
    '/v1/projects/${DefaultFirebaseOptions.currentPlatform.projectId}'
    '/databases/(default)/documents';

Future<(int, Object?)> _request(
  String method,
  String path, {
  Map<String, Object>? query,
  Object? body,
}) async {
  final client = HttpClient();
  try {
    final uri = Uri(
      scheme: 'http',
      host: _host,
      port: _port,
      path: path,
      queryParameters: query,
    );
    final req = await client.openUrl(method, uri);
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer owner');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    return (res.statusCode, text.isEmpty ? null : jsonDecode(text));
  } finally {
    client.close();
  }
}

Object? _decode(Map<String, dynamic> v) {
  if (v.containsKey('nullValue')) return null;
  if (v.containsKey('stringValue')) return v['stringValue'];
  if (v.containsKey('booleanValue')) return v['booleanValue'];
  if (v.containsKey('integerValue')) return int.parse('${v['integerValue']}');
  if (v.containsKey('doubleValue')) return (v['doubleValue'] as num).toDouble();
  if (v.containsKey('timestampValue')) {
    return DateTime.parse(v['timestampValue'] as String);
  }
  if (v.containsKey('mapValue')) {
    return _decodeFields(
      (v['mapValue'] as Map<String, dynamic>)['fields']
          as Map<String, dynamic>?,
    );
  }
  if (v.containsKey('arrayValue')) {
    final values = ((v['arrayValue'] as Map<String, dynamic>)['values']
            as List<dynamic>?) ??
        const [];
    return values.map((e) => _decode(e as Map<String, dynamic>)).toList();
  }
  // Bytes, geopoints, referencias: ninguna suite los lee. Fallar acá evita
  // devolver un mapa crudo que, reescrito con `adminSetDoc`, corrompería el
  // documento en silencio.
  throw UnsupportedError('emulator_admin: tipo de valor no soportado: $v');
}

Map<String, Object?> _decodeFields(Map<String, dynamic>? fields) => {
      for (final e in (fields ?? const <String, dynamic>{}).entries)
        e.key: _decode(e.value as Map<String, dynamic>),
    };

Map<String, Object?> _encode(Object? v) => switch (v) {
      null => {'nullValue': null},
      final bool b => {'booleanValue': b},
      final int i => {'integerValue': '$i'},
      final double d => {'doubleValue': d},
      final String s => {'stringValue': s},
      final DateTime t => {'timestampValue': t.toUtc().toIso8601String()},
      final Map<String, Object?> m => {
          'mapValue': {
            'fields': {for (final e in m.entries) e.key: _encode(e.value)},
          },
        },
      final List<Object?> l => {
          'arrayValue': {'values': l.map(_encode).toList()},
        },
      _ => throw ArgumentError.value(v, 'v', 'tipo no soportado'),
    };

/// Lee `path` (p. ej. `app_config/email_gate`) salteando las reglas. `null`
/// si el documento no existe.
Future<Map<String, Object?>?> adminGetDoc(String path) async {
  final (status, body) = await _request('GET', '$_docsBase/$path');
  if (status == 404) return null;
  if (status != 200) {
    throw StateError('adminGetDoc($path): HTTP $status — $body');
  }
  return _decodeFields(
    (body! as Map<String, dynamic>)['fields'] as Map<String, dynamic>?,
  );
}

/// Escribe `path` entero (reemplaza, no mergea) salteando las reglas.
Future<void> adminSetDoc(String path, Map<String, Object?> data) async {
  final (status, body) = await _request(
    'PATCH',
    '$_docsBase/$path',
    body: {
      'fields': {for (final e in data.entries) e.key: _encode(e.value)},
    },
  );
  if (status != 200) {
    throw StateError('adminSetDoc($path): HTTP $status — $body');
  }
}

/// Borra `path` salteando las reglas. No falla si no existía.
Future<void> adminDeleteDoc(String path) async {
  final (status, body) = await _request('DELETE', '$_docsBase/$path');
  if (status != 200 && status != 404) {
    throw StateError('adminDeleteDoc($path): HTTP $status — $body');
  }
}

/// Actualiza SÓLO los campos de [data] en `path` (merge, con `updateMask`),
/// salteando las reglas. Falla si el documento no existe.
Future<void> adminUpdateFields(String path, Map<String, Object?> data) async {
  final (status, body) = await _request(
    'PATCH',
    '$_docsBase/$path',
    query: {
      // Un parámetro por campo: separados por coma, el emulador lee UN path
      // con comas adentro y responde 400.
      'updateMask.fieldPaths': data.keys.toList(),
      'currentDocument.exists': 'true',
    },
    body: {
      'fields': {for (final e in data.entries) e.key: _encode(e.value)},
    },
  );
  if (status != 200) {
    throw StateError('adminUpdateFields($path): HTTP $status — $body');
  }
}

/// Los documentos de [collection] con `field == value`, salteando las reglas.
///
/// [parent] es el documento padre para una subcolección (`users/{uid}` para
/// `sessions`); sin él, la colección es de primer nivel. Cada resultado trae su
/// `path` relativo a `documents/`, listo para [adminUpdateFields].
Future<List<({String path, Map<String, Object?> data})>> adminWhereEqual(
  String collection,
  String field,
  String value, {
  String? parent,
}) async {
  final (status, body) = await _request(
    'POST',
    parent == null ? '$_docsBase:runQuery' : '$_docsBase/$parent:runQuery',
    body: {
      'structuredQuery': {
        'from': [
          {'collectionId': collection},
        ],
        'where': {
          'fieldFilter': {
            'field': {'fieldPath': field},
            'op': 'EQUAL',
            'value': {'stringValue': value},
          },
        },
      },
    },
  );
  if (status != 200) {
    throw StateError('adminWhereEqual($collection): HTTP $status — $body');
  }
  return [
    for (final row in body! as List<dynamic>)
      if ((row as Map<String, dynamic>)['document'] != null)
        (
          path: ((row['document'] as Map<String, dynamic>)['name'] as String)
              .split('/documents/')
              .last,
          data: _decodeFields(
            (row['document'] as Map<String, dynamic>)['fields']
                as Map<String, dynamic>?,
          ),
        ),
  ];
}

/// Cierra las sesiones de entreno `active` de [uid] antes de que la suite
/// entre a la app.
///
/// Una sesión colgada —la deja una corrida de `workout_session_flow_test`
/// cortada a la mitad, o un recorrido manual— hace que Inicio abra el modal
/// "Entrenamiento en curso", que no se cierra tocando afuera y aparece TARDE
/// (cuando llega la lectura de la sesión), así que tapa la pantalla siguiente
/// de la suite. Medido: tapó el check de la serie en el player.
///
/// Se cierra acá, como preparación, y NO tocando DESCARTAR en el modal: ese
/// botón hace dos `pop` —el listener del diálogo lo cierra cuando la sesión
/// deja de estar activa y después el `await finish()` vuelve a hacer `pop`
/// sobre la página de abajo— y la suite se caía con "You have popped the last
/// page off of the stack" (`home_screen.dart`, `_resumeModal`). Es un bug de la
/// app, no de la suite: está reportado aparte.
///
/// Escribe lo mismo que `SessionRepository.finish` en los campos que deciden
/// si una sesión está activa; no recalcula volumen ni duración porque ninguna
/// suite mira esa sesión después.
Future<void> closeActiveSessionsOf(String uid) async {
  final activas = await adminWhereEqual(
    'sessions',
    'status',
    'active',
    parent: 'users/$uid',
  );
  for (final s in activas) {
    await adminUpdateFields(s.path, {
      'status': 'finished',
      'finishedAt': DateTime.now(),
      'wasFullyCompleted': false,
    });
  }
}
