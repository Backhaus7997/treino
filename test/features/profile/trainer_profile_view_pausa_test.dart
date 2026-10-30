// Pausa del PF en su propia pestaña de perfil. Regresión vista en device: el
// PF pausaba y la card seguía diciendo VISIBLE —el badge sólo miraba si
// existía el perfil público— y el aviso para reanudar no estaba en esta
// pestaña, que es justo donde el PF mira si se lo ve.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_discovery_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_public_profile.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/trainer_profile_view.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

const _uid = 'trainer-uid';

Future<void> _pump(
  WidgetTester tester, {
  required bool acceptingAthletes,
  bool publicado = true,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      currentUidProvider.overrideWithValue(_uid),
      userProfileProvider.overrideWith(
        (_) => Stream.value(UserProfile(
          uid: _uid,
          email: 'pf@test.com',
          displayName: 'Coach Ana',
          role: UserRole.trainer,
          createdAt: DateTime(2025),
          updatedAt: DateTime(2025),
          acceptingAthletes: acceptingAthletes,
        )),
      ),
      trainerLinksStreamProvider.overrideWith((_) => Stream.value(const [])),
      // El doc público dice ABIERTO a propósito: el badge tiene que leer la
      // pausa del perfil propio, en vivo, y no de este doc leído una vez.
      trainerByIdProvider(_uid).overrideWith(
        (_) async => publicado ? const TrainerPublicProfile(uid: _uid) : null,
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: const Scaffold(body: TrainerProfileView()),
    ),
  ));
  await tester.pumpAndSettle();
}

String _estado(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('perfil_publico_estado'))).data!;

void main() {
  testWidgets('pausado: el badge dice PAUSADO y está el aviso para reanudar',
      (tester) async {
    await _pump(tester, acceptingAthletes: false);

    expect(_estado(tester), 'PAUSADO');
    expect(find.byKey(const Key('perfil_pausado_aviso')), findsOneWidget);
  });

  testWidgets('abierto: VISIBLE y sin aviso', (tester) async {
    await _pump(tester, acceptingAthletes: true);

    expect(_estado(tester), 'VISIBLE');
    expect(find.byKey(const Key('perfil_pausado_aviso')), findsNothing);
  });

  testWidgets('sin perfil público: OCULTO, pausado o no', (tester) async {
    await _pump(tester, acceptingAthletes: false, publicado: false);

    expect(_estado(tester), 'OCULTO');
  });
}
