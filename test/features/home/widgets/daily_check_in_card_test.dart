// Tests de la tarjeta de check-in diario en Inicio (#643 slice 2).
//
// Lo que se testea es lo que hace o rompe el slice:
//   1. SIRVE SIN HABER ENTRENADO — la tarjeta ofrece registrar aunque el día
//      no tenga sesión. Es la razón de existir del slice: Marta mide su
//      progreso al levantarse y entrena dos veces por semana.
//   2. NO PISA — si el día ya tiene registro, la tarjeta lo muestra y editar
//      reescribe ESE documento, en la subcolección de bienestar.
//   3. REGISTRAR, NO INTERPRETAR — la tarjeta no compara, no felicita, no
//      alerta y no lleva puntaje ni racha (AGENTS.md regla 4).

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/checkins/application/check_in_providers.dart';
import 'package:treino/features/checkins/domain/check_in.dart';
import 'package:treino/features/home/widgets/daily_check_in_card.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

const _uid = 'u1';

Widget _host({
  required FakeFirebaseFirestore firestore,
  List<CheckIn>? dayCheckIns,
}) {
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(firestore),
      currentUidProvider.overrideWithValue(_uid),
      if (dayCheckIns != null)
        checkInsForDateProvider.overrideWith(
          (ref, key) => Future.value(dayCheckIns),
        ),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: const Scaffold(
        body: SingleChildScrollView(child: DailyCheckInCard()),
      ),
    ),
  );
}

Future<List<Map<String, Object?>>> _stored(
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

void main() {
  testWidgets('sin registro del día ofrece la escala completa de 5 niveles',
      (tester) async {
    await tester.pumpWidget(_host(
      firestore: FakeFirebaseFirestore(),
      dayCheckIns: const [],
    ));
    await tester.pumpAndSettle();

    expect(find.text('¿CÓMO TE SENTÍS HOY?'), findsOneWidget);
    for (final feeling in CheckInFeeling.displayOrder) {
      expect(find.text(feeling.emoji), findsOneWidget);
    }
    expect(find.text('REGISTRADO'), findsNothing);
  });

  testWidgets(
      'registrar desde Inicio NO exige haber entrenado: el doc queda sin '
      'sessionId', (tester) async {
    final firestore = FakeFirebaseFirestore();
    await tester.pumpWidget(_host(firestore: firestore));
    await tester.pumpAndSettle();

    // Dos toques: el emoji abre el sheet ya precargado y GUARDAR cierra.
    await tester.tap(find.text(CheckInFeeling.mal.emoji));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GUARDAR'));
    await tester.pumpAndSettle();

    final all = await _stored(firestore);
    expect(all, hasLength(1));
    expect(all.single['feeling'], 'bad');
    expect(all.single['date'], checkInDateKey(DateTime.now()));
    // El check-in diario no sale de una sesión: ese es el punto del slice.
    expect(all.single['sessionId'], isNull);
  });

  testWidgets('el sheet abierto desde Inicio pregunta en PRESENTE',
      (tester) async {
    await tester.pumpWidget(_host(firestore: FakeFirebaseFirestore()));
    await tester.pumpAndSettle();

    await tester.tap(find.text(CheckInFeeling.bien.emoji));
    await tester.pumpAndSettle();

    // "¿Cómo te sentiste?" preguntaría por un entreno que puede no existir.
    expect(find.text('¿CÓMO TE SENTÍS HOY?'), findsWidgets);
    expect(find.text('¿CÓMO TE SENTISTE?'), findsNothing);
  });

  testWidgets('con registro del día muestra REGISTRADO y no la escala',
      (tester) async {
    await tester.pumpWidget(_host(
      firestore: FakeFirebaseFirestore(),
      dayCheckIns: [
        CheckIn(
          id: '2026-05-18_1779000000000',
          date: checkInDateKey(DateTime.now()),
          feeling: CheckInFeeling.bien,
          recordedAt: DateTime.now().toUtc(),
        ),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('REGISTRADO'), findsOneWidget);
    expect(find.text('Editar'), findsOneWidget);
    expect(find.text(CheckInFeeling.bien.emoji), findsOneWidget);
    expect(find.text(CheckInFeeling.muyMal.emoji), findsNothing);
  });

  testWidgets(
      'editar reescribe SU documento: el registro del entreno no se duplica',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    // El registro que dejó el entreno de hoy. La tarjeta lo adopta como "hoy".
    await firestore
        .collection('users')
        .doc(_uid)
        .collection('wellbeingCheckIns')
        .doc('2026-05-18_1779000000000')
        .set({'date': '2026-05-18', 'feeling': 'bad', 'sessionId': 's1'});

    await tester.pumpWidget(_host(
      firestore: firestore,
      dayCheckIns: [
        CheckIn(
          id: '2026-05-18_1779000000000',
          date: '2026-05-18',
          feeling: CheckInFeeling.mal,
          recordedAt: DateTime.now().toUtc(),
          sessionId: 's1',
        ),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Muy bien'));
    await tester.pump();
    await tester.tap(find.text('GUARDAR'));
    await tester.pumpAndSettle();

    final all = await _stored(firestore);
    expect(all, hasLength(1));
    expect(all.single['__id'], '2026-05-18_1779000000000');
    expect(all.single['feeling'], 'great');
    // Editar conserva la fecha del hecho, no la del día en que se corrigió.
    expect(all.single['date'], '2026-05-18');
  });

  testWidgets('sin uid la tarjeta se dibuja igual y no consulta nada',
      (tester) async {
    final firestore = FakeFirebaseFirestore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(firestore),
          currentUidProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          home: const Scaffold(body: DailyCheckInCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('¿CÓMO TE SENTÍS HOY?'), findsOneWidget);
    expect(await _stored(firestore), isEmpty);
  });

  // ── Registrar, no interpretar (y no gamificar) ───────────────────────────

  testWidgets('la tarjeta no interpreta, no compara y no lleva puntaje',
      (tester) async {
    await tester.pumpWidget(_host(
      firestore: FakeFirebaseFirestore(),
      dayCheckIns: [
        CheckIn(
          id: '2026-05-18_1779000000000',
          date: checkInDateKey(DateTime.now()),
          feeling: CheckInFeeling.muyMal,
          hasPain: true,
          recordedAt: DateTime.now().toUtc(),
        ),
      ],
    ));
    await tester.pumpAndSettle();

    // Límite duro del issue: registrar, nunca interpretar. Y AGENTS.md regla
    // 4: sin puntaje, racha ni recompensa por registrar.
    for (final forbidden in [
      'Te recomendamos',
      'Deberías',
      'Es normal',
      'No entrenes',
      'Descansá',
      'Mejor que ayer',
      'Peor que ayer',
      'racha',
      'Racha',
      'puntos',
      'Puntos',
      'Nivel',
    ]) {
      expect(find.textContaining(forbidden), findsNothing,
          reason: 'la tarjeta no puede decir "$forbidden"');
    }
  });
}
