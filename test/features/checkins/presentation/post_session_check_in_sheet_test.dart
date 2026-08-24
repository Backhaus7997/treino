// Tests del paso de check-in post-sesión (#643).
//
// Tres contratos se testean acá porque son los que hacen o rompen el feature:
//   1. SALTABLE DE VERDAD — salir sin guardar no escribe nada y no cuesta nada.
//   2. REGISTRAR, NO INTERPRETAR — el aviso de dolor es neutro y no condiciona
//      ningún comportamiento de la app.
//   3. NO DESTRUCTIVO — un segundo entreno el mismo día suma un registro; no
//      pisa el del primero. Era el defecto de la slice 1, cuando el id del
//      documento era la fecha.
// El resto (qué se persiste y con qué vocabulario) se verifica contra un
// Firestore falso, no contra un mock de repositorio: así el path y el id del
// documento quedan cubiertos de punta a punta.

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/checkins/domain/check_in.dart';
import 'package:treino/features/checkins/presentation/post_session_check_in_sheet.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/domain/muscle_group.dart';
import 'package:treino/l10n/app_l10n.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

const _uid = 'u1';

/// Monta un host con un botón que abre el sheet REAL (vía
/// [showPostSessionCheckInSheet]), para que la ruta modal, el pop y el valor
/// devuelto entren en el test.
Widget _host({
  required FakeFirebaseFirestore firestore,
  required void Function(bool?) onClosed,
  CheckIn? existing,
  String? uid = _uid,
  String sessionId = 's1',
}) {
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(firestore),
      currentUidProvider.overrideWithValue(uid),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                onClosed(await showPostSessionCheckInSheet(
                  context,
                  sessionId: sessionId,
                  existing: existing,
                ));
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

/// Todos los check-ins persistidos, con su id bajo `__id`.
///
/// Lee la subcolección REAL. Si alguien vuelve a apuntar el repositorio a
/// `users/{uid}/checkIns` —el path reservado para el check-in de presencia en
/// el gym— esto se queda vacío y toda la suite se cae.
Future<List<Map<String, Object?>>> _storedCheckIns(
  FakeFirebaseFirestore firestore,
) async {
  final snap = await firestore
      .collection('users')
      .doc(_uid)
      .collection('wellbeingCheckIns')
      .get();
  return [
    for (final d in snap.docs) {...d.data(), '__id': d.id},
  ];
}

/// El único check-in persistido, o `null` si no hay ninguno. Falla si hay más
/// de uno: los tests que la usan afirman sobre un registro solo.
Future<Map<String, Object?>?> _storedCheckIn(
  FakeFirebaseFirestore firestore,
) async {
  final all = await _storedCheckIns(firestore);
  if (all.isEmpty) return null;
  expect(all, hasLength(1));
  return all.single;
}

void main() {
  // ── Escala de sensación ──────────────────────────────────────────────────

  testWidgets('muestra los 5 niveles y GUARDAR arranca deshabilitado',
      (tester) async {
    await tester.pumpWidget(_host(
      firestore: FakeFirebaseFirestore(),
      onClosed: (_) {},
    ));
    await _openSheet(tester);

    for (final label in ['Muy mal', 'Mal', 'Normal', 'Bien', 'Muy bien']) {
      expect(find.text(label), findsOneWidget);
    }
    // Sin nivel elegido no hay nada que registrar.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  testWidgets(
      'elegir un nivel habilita GUARDAR y persiste con id {fecha}_{millis}',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    bool? result;
    await tester.pumpWidget(_host(
      firestore: firestore,
      onClosed: (r) => result = r,
    ));
    await _openSheet(tester);

    await tester.tap(find.text('Muy bien'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );

    await tester.tap(find.text('GUARDAR'));
    await tester.pumpAndSettle();

    final today = checkInDateKey(DateTime.now());
    final stored = await _storedCheckIn(firestore);
    expect(stored, isNotNull);
    // El id ARRANCA con la fecha pero no ES la fecha: el sufijo de
    // milisegundos es lo que impide que el próximo registro del día lo pise.
    expect(stored!['__id'], startsWith('${today}_'));
    expect(stored['__id'], isNot(today));
    expect(stored['date'], today);
    expect(stored['feeling'], 'great');
    expect(stored['hasPain'], isFalse);
    expect(stored['painAreas'], isEmpty);
    expect(stored['note'], isNull);
    // Queda trazado de qué sesión lo originó, sin colgarlo de Session.
    expect(stored['sessionId'], 's1');
    expect(result, isTrue);
  });

  // ── Saltable de verdad ───────────────────────────────────────────────────

  testWidgets('AHORA NO cierra sin escribir nada', (tester) async {
    final firestore = FakeFirebaseFirestore();
    bool? result;
    var closed = false;
    await tester.pumpWidget(_host(
      firestore: firestore,
      onClosed: (r) {
        result = r;
        closed = true;
      },
    ));
    await _openSheet(tester);

    // Incluso con todo completado: saltear no cuesta nada y no deja rastro.
    await tester.tap(find.text('Bien'));
    await tester.pump();
    await tester.tap(find.text('AHORA NO'));
    await tester.pumpAndSettle();

    expect(closed, isTrue);
    expect(result, isNull);
    expect(await _storedCheckIn(firestore), isNull);
  });

  testWidgets('descartar el sheet con el back del sistema tampoco escribe',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    await tester.pumpWidget(_host(
      firestore: firestore,
      onClosed: (_) {},
    ));
    await _openSheet(tester);

    await tester.tap(find.text('Normal'));
    await tester.pump();
    // El back del sistema cierra la ruta modal.
    final NavigatorState navigator = tester.state(find.byType(Navigator));
    navigator.pop();
    await tester.pumpAndSettle();

    expect(find.text('GUARDAR'), findsNothing);
    expect(await _storedCheckIn(firestore), isNull);
  });

  // ── Dolor y zonas ────────────────────────────────────────────────────────

  testWidgets('las zonas aparecen recién al marcar dolor', (tester) async {
    await tester.pumpWidget(_host(
      firestore: FakeFirebaseFirestore(),
      onClosed: (_) {},
    ));
    await _openSheet(tester);

    expect(find.text('¿En qué zona?'), findsNothing);
    expect(find.text('Cuádriceps'), findsNothing);

    await tester.tap(find.text('SÍ'));
    await tester.pumpAndSettle();

    expect(find.text('¿En qué zona?'), findsOneWidget);
    expect(find.text('Cuádriceps'), findsOneWidget);
  });

  testWidgets('las zonas ofrecidas son la taxonomía de MuscleGroup sin cardio',
      (tester) async {
    await tester.pumpWidget(_host(
      firestore: FakeFirebaseFirestore(),
      onClosed: (_) {},
    ));
    await _openSheet(tester);
    await tester.tap(find.text('SÍ'));
    await tester.pumpAndSettle();

    for (final group in kCheckInPainAreas) {
      expect(find.text(group.label), findsOneWidget,
          reason: 'falta la zona ${group.key}');
    }
    // Cardio es una modalidad de entrenamiento, no una parte del cuerpo.
    expect(find.text(MuscleGroup.cardio.label), findsNothing);
  });

  testWidgets('guarda las zonas con sus claves canónicas y la nota libre',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    await tester.pumpWidget(_host(
      firestore: firestore,
      onClosed: (_) {},
    ));
    await _openSheet(tester);

    await tester.tap(find.text('Mal'));
    await tester.pump();
    await tester.tap(find.text('SÍ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cuádriceps'));
    await tester.tap(find.text('Espalda'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '  Molestia al bajar  ');
    await tester.pump();

    await tester.tap(find.text('GUARDAR'));
    await tester.pumpAndSettle();

    final stored = await _storedCheckIn(firestore);
    expect(stored!['feeling'], 'bad');
    expect(stored['hasPain'], isTrue);
    expect(stored['painAreas'], ['quads', 'back']);
    // La nota se guarda recortada, no como la tipeó el dedo gordo.
    expect(stored['note'], 'Molestia al bajar');
  });

  testWidgets('volver dolor a NO limpia las zonas ya marcadas', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await tester.pumpWidget(_host(
      firestore: firestore,
      onClosed: (_) {},
    ));
    await _openSheet(tester);

    await tester.tap(find.text('Normal'));
    await tester.pump();
    await tester.tap(find.text('SÍ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cuádriceps'));
    await tester.pump();
    await tester.tap(find.text('NO'));
    await tester.pumpAndSettle();

    expect(find.text('Cuádriceps'), findsNothing);

    await tester.tap(find.text('GUARDAR'));
    await tester.pumpAndSettle();

    final stored = await _storedCheckIn(firestore);
    expect(stored!['hasPain'], isFalse);
    expect(stored['painAreas'], isEmpty);
  });

  // ── Registrar, no interpretar ────────────────────────────────────────────

  testWidgets(
      'el aviso de dolor es neutro: aparece con el dolor y no diagnostica ni '
      'recomienda', (tester) async {
    await tester.pumpWidget(_host(
      firestore: FakeFirebaseFirestore(),
      onClosed: (_) {},
    ));
    await _openSheet(tester);

    const disclaimer =
        'Si el dolor persiste, consultá a un profesional de la salud.';
    expect(find.text(disclaimer), findsNothing);

    await tester.tap(find.text('SÍ'));
    await tester.pumpAndSettle();

    expect(find.text(disclaimer), findsOneWidget);
    // Límite duro del issue: nada de interpretar el dato. Si alguien agrega
    // copy sugiriendo qué hacer, este test lo frena.
    for (final forbidden in [
      'Te recomendamos',
      'Deberías',
      'Es normal',
      'No entrenes',
      'Descansá',
    ]) {
      expect(find.textContaining(forbidden), findsNothing);
    }
  });

  // ── Registro ya existente para el día ────────────────────────────────────

  testWidgets(
      'un registro existente del día precarga el sheet en vez de pisarlo a '
      'ciegas', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await tester.pumpWidget(_host(
      firestore: firestore,
      onClosed: (_) {},
      existing: CheckIn(
        id: '2026-05-18_1779000000000',
        date: '2026-05-18',
        feeling: CheckInFeeling.mal,
        hasPain: true,
        painAreas: const [MuscleGroup.gluteos],
        note: 'Vengo con la cadera',
        recordedAt: DateTime.now().toUtc(),
      ),
    ));
    await _openSheet(tester);

    expect(find.text('Vengo con la cadera'), findsOneWidget);
    expect(find.text('¿En qué zona?'), findsOneWidget);

    await tester.tap(find.text('GUARDAR'));
    await tester.pumpAndSettle();

    final stored = await _storedCheckIn(firestore);
    expect(stored!['feeling'], 'bad');
    expect(stored['painAreas'], ['glutes']);
    expect(stored['note'], 'Vengo con la cadera');
    // Editar reescribe SU documento y conserva SU fecha: corregir un registro
    // no lo re-imputa al día en que se corrigió.
    expect(stored['__id'], '2026-05-18_1779000000000');
    expect(stored['date'], '2026-05-18');
  });

  // ── No destructivo ───────────────────────────────────────────────────────

  testWidgets(
      'un segundo entreno el mismo día SUMA un registro, no pisa el anterior',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    final today = checkInDateKey(DateTime.now());

    // El registro que dejó el entreno de la mañana, con su propia sesión.
    await firestore
        .collection('users')
        .doc(_uid)
        .collection('wellbeingCheckIns')
        .doc('${today}_1700000000000')
        .set({
      'date': today,
      'feeling': 'bad',
      'hasPain': true,
      'painAreas': ['back'],
      'recordedAt': Timestamp.fromDate(DateTime.now().toUtc()),
      'sessionId': 's-manana',
    });

    // El de la tarde es OTRA sesión: abre sin `existing`, que es exactamente
    // lo que resuelve checkInForSession en el resumen post-entreno.
    await tester.pumpWidget(_host(
      firestore: firestore,
      onClosed: (_) {},
      sessionId: 's-tarde',
    ));
    await _openSheet(tester);

    await tester.tap(find.text('Muy bien'));
    await tester.pump();
    await tester.tap(find.text('GUARDAR'));
    await tester.pumpAndSettle();

    final all = await _storedCheckIns(firestore);
    // Dos documentos, no uno. Con la fecha como id, acá quedaba uno solo y el
    // dolor de la mañana desaparecía sin que nadie se enterara.
    expect(all, hasLength(2));
    expect(
      all.map((c) => c['sessionId']),
      containsAll(<String>['s-manana', 's-tarde']),
    );
    final morning = all.firstWhere((c) => c['sessionId'] == 's-manana');
    expect(morning['feeling'], 'bad');
    expect(morning['painAreas'], ['back']);
  });
}
