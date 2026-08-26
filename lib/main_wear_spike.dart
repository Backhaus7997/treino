/// SPIKE DE MEDICIÓN — Wear OS. **No es código de producción y no se mergea.**
///
/// Existe para contestar dos preguntas, y NADA más. Toda la arquitectura del
/// companion de watchOS salió de una sola restricción: Firestore no tiene SDK
/// para watchOS. Si en Wear OS esa restricción no existe, el diseño entero se
/// replantea. Antes de invertir en UI hay que verificar la premisa CORRIENDO:
///
///   A) ¿Firestore con listeners en vivo funciona adentro de un reloj Wear OS?
///      No alcanza con que compile: hay que ver llegar un snapshot que NADIE
///      pidió, empujado por el servidor, con `isFromCache: false`.
///
///   B) ¿El dominio Dart se reusa SIN tocarlo? Se corren los fixtures de
///      `conformance/` —el mismo contrato que hoy comparten Dart y Swift—
///      contra las funciones puras importadas tal cual del árbol de producción.
///      Si pasan los 22 casos en el reloj, no hace falta reimplementar nada en
///      otro lenguaje, y con eso desaparece la familia de bugs que costó cuatro
///      incidentes en el ciclo de Apple.
///
/// La pregunta (B) se contesta sin red, así que se ejecuta primero: un fallo de
/// conectividad no puede enmascarar un fallo de reuso del dominio.
///
/// Cómo correr:
/// ```
/// ./scripts/emulator.sh   # fija --project treino-dev (#840)
/// flutter run -d emulator-5554 -t lib/main_wear_spike.dart \
///   --dart-define=USE_EMULATOR=true
/// ```
///
/// No hace falta `adb reverse`: FlutterFire detecta que corre en un emulador de
/// Android y reescribe `localhost` a 10.0.2.2 por su cuenta. Se ve en el log
/// (`Mapping Firestore Emulator host "localhost" to "10.0.2.2"`). Lo que SÍ hace
/// falta es permitir HTTP en claro hacia esa IP — ver
/// `android/app/src/debug/res/xml/network_security_config.xml`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

// Importados TAL CUAL del árbol de producción. Que estas dos líneas compilen y
// corran en un target Wear OS es, literalmente, la mitad del spike.
import 'features/workout/domain/plan_advance.dart';
import 'features/workout/domain/routine_selection.dart';
import 'firebase_options.dart';
import 'wear_spike_fixtures.dart';

/// Atleta sembrado por `scripts/seed_emulator_full.js`. Credenciales
/// EMULATOR-ONLY, documentadas en `scripts/seed_emulator_full_README.md`.
const String _seedUid = 'seed-athlete-001';
const String _seedEmail = 'martin@emulator.treino';
const String _seedPassword = 'Emulator1234!';

void main() {
  runApp(const _SpikeApp());
}

// ---------------------------------------------------------------------------
// (B) Reuso del dominio — sin red, corre primero.
// ---------------------------------------------------------------------------

/// Resultado de un caso del contrato de conformidad.
typedef _CaseResult = ({String rule, String name, bool passed, String detail});

/// Corre los fixtures de `conformance/` contra las funciones puras del árbol de
/// producción, importadas sin modificar.
List<_CaseResult> _runDomainConformance() {
  final results = <_CaseResult>[];

  final planAdvance =
      jsonDecode(planAdvanceFixturesJson) as Map<String, dynamic>;
  for (final raw in planAdvance['cases'] as List<dynamic>) {
    final c = raw as Map<String, dynamic>;
    final given = c['given'] as Map<String, dynamic>;
    final expect = c['expect'] as Map<String, dynamic>;

    final lastRaw = given['lastFinished'] as Map<String, dynamic>?;
    final actual = nextPlanPosition(
      lastFinished: lastRaw == null
          ? null
          : (
              dayNumber: lastRaw['dayNumber'] as int,
              weekNumber: lastRaw['weekNumber'] as int,
            ),
      numDays: given['numDays'] as int,
      numWeeks: given['numWeeks'] as int,
    );

    final ok = actual.dayNumber == expect['dayNumber'] &&
        actual.weekNumber == expect['weekNumber'];
    results.add((
      rule: 'plan-advance',
      name: c['name'] as String,
      passed: ok,
      detail: ok
          ? 'd${actual.dayNumber} w${actual.weekNumber}'
          : 'esperaba d${expect['dayNumber']} w${expect['weekNumber']}, '
              'dio d${actual.dayNumber} w${actual.weekNumber}',
    ));
  }

  final selection =
      jsonDecode(routineSelectionFixturesJson) as Map<String, dynamic>;
  for (final raw in selection['cases'] as List<dynamic>) {
    final c = raw as Map<String, dynamic>;
    final given = c['given'] as Map<String, dynamic>;
    final expected =
        (c['expect'] as Map<String, dynamic>)['routineId'] as String?;

    final actual = resolveActiveRoutineId(
      activeRoutineId: given['activeRoutineId'] as String?,
      assignedIds: (given['assignedIds'] as List<dynamic>).cast<String>(),
      selfCreatedIds: (given['selfCreatedIds'] as List<dynamic>).cast<String>(),
    );

    final ok = actual == expected;
    results.add((
      rule: 'routine-selection',
      name: c['name'] as String,
      passed: ok,
      detail: ok ? (actual ?? 'null') : 'esperaba $expected, dio $actual',
    ));
  }

  return results;
}

// ---------------------------------------------------------------------------
// (A) Listeners de Firestore
// ---------------------------------------------------------------------------

/// Un evento del listener. `fromCache: false` es la prueba de que el dato vino
/// EMPUJADO por el servidor y no del caché local.
typedef _SnapEvent = ({
  int seq,
  int docs,
  bool fromCache,
  bool pendingWrites,
  int msSincePrev,
});

class _SpikeApp extends StatefulWidget {
  const _SpikeApp();

  @override
  State<_SpikeApp> createState() => _SpikeAppState();
}

class _SpikeAppState extends State<_SpikeApp> {
  late final List<_CaseResult> _domain;
  final List<_SnapEvent> _events = [];
  final Stopwatch _sinceLastEvent = Stopwatch();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  String _stage = 'arrancando';
  String? _error;

  @override
  void initState() {
    super.initState();
    // (B) primero: sin red, así un fallo de conectividad no lo enmascara.
    _domain = _runDomainConformance();
    final failed = _domain.where((r) => !r.passed).toList();
    debugPrint(
      '[SPIKE] dominio: ${_domain.length - failed.length}/${_domain.length} '
      'casos del contrato de conformidad OK',
    );
    for (final f in failed) {
      debugPrint('[SPIKE] dominio FALLA ${f.rule} · ${f.name}: ${f.detail}');
    }
    unawaited(_bootFirestore());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _bootFirestore() async {
    try {
      setState(() => _stage = 'Firebase.initializeApp');
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      const useEmulator = bool.fromEnvironment('USE_EMULATOR');
      if (useEmulator) {
        setState(() => _stage = 'apuntando a emuladores');
        // Mismas llamadas que `lib/main.dart`, a propósito: el spike mide el
        // camino REAL, no uno propio. `localhost` lo reescribe FlutterFire a
        // 10.0.2.2 solo. Ver el encabezado de este archivo.
        FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
        await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
      }

      setState(() => _stage = 'signIn');
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _seedEmail,
        password: _seedPassword,
      );

      setState(() => _stage = 'listener abierto');
      _sinceLastEvent.start();
      _sub = FirebaseFirestore.instance
          .collection('users')
          .doc(_seedUid)
          .collection('sessions')
          .snapshots()
          .listen(
        (snap) {
          final ms = _sinceLastEvent.elapsedMilliseconds;
          _sinceLastEvent.reset();
          setState(() {
            _events.insert(0, (
              seq: _events.length + 1,
              docs: snap.docs.length,
              fromCache: snap.metadata.isFromCache,
              pendingWrites: snap.metadata.hasPendingWrites,
              msSincePrev: ms,
            ));
          });
          // Duplicado a consola: el log es lo que se cita como evidencia.
          debugPrint(
            '[SPIKE] snapshot #${_events.length} docs=${snap.docs.length} '
            'fromCache=${snap.metadata.isFromCache} '
            'pendingWrites=${snap.metadata.hasPendingWrites} '
            '+${ms}ms',
          );
        },
        onError: (Object e) {
          setState(() => _error = 'listener: $e');
          debugPrint('[SPIKE] ERROR listener: $e');
        },
      );
    } catch (e) {
      setState(() => _error = '$_stage: $e');
      debugPrint('[SPIKE] ERROR $_stage: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final failed = _domain.where((r) => !r.passed).toList();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: DefaultTextStyle(
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              height: 1.25,
            ),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                const Text(
                  'SPIKE WEAR OS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),

                // (B)
                Text(
                  'B) dominio: ${_domain.length - failed.length}/${_domain.length}',
                  style: TextStyle(
                    color:
                        failed.isEmpty ? Colors.greenAccent : Colors.redAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                for (final f in failed)
                  Text(
                    '✗ ${f.rule} · ${f.name}: ${f.detail}',
                    style:
                        const TextStyle(color: Colors.redAccent, fontSize: 9),
                  ),
                const SizedBox(height: 8),

                // (A)
                Text(
                  'A) firestore: $_stage',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_error != null)
                  Text(
                    _error!,
                    style:
                        const TextStyle(color: Colors.redAccent, fontSize: 9),
                  ),
                Text(
                  'eventos: ${_events.length}',
                  style: TextStyle(
                    color: _events.any((e) => !e.fromCache)
                        ? Colors.greenAccent
                        : Colors.amberAccent,
                    fontSize: 11,
                  ),
                ),
                for (final e in _events.take(8))
                  Text(
                    '#${e.seq} docs=${e.docs} '
                    'cache=${e.fromCache ? 'S' : 'N'} +${e.msSincePrev}ms',
                    style: const TextStyle(fontSize: 9),
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
