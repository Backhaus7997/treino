// El picker de alumnos de mobile (#1695): ofrece a quien tiene vínculo VIVO
// (activo o pausado), el mismo criterio que el Hub, y no a un ex-alumno.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart'
    show trainerLinksStreamProvider;
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach/presentation/widgets/athlete_picker_sheet.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';

import '../../../../helpers/trainer_links.dart';

void main() {
  testWidgets('ofrece al activo y al pausado, no al terminado', (tester) async {
    final estados = {
      'ath-1': TrainerLinkStatus.active,
      'ath-2': TrainerLinkStatus.paused,
      'ath-3': TrainerLinkStatus.terminated,
    };
    await tester.pumpWidget(ProviderScope(
      overrides: [
        trainerLinksStreamProvider.overrideWith((ref) => Stream.value([
              for (final e in estados.entries) linkDe(e.key, status: e.value),
            ])),
        for (final id in estados.keys)
          userPublicProfileProvider(id).overrideWith((ref) => Stream.value(
              UserPublicProfile(uid: id, displayName: 'Alumno $id'))),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showAthletePickerSheet(context),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    expect(find.text('Alumno ath-1'), findsOneWidget);
    expect(find.text('Alumno ath-2'), findsOneWidget);
    expect(find.text('Alumno ath-3'), findsNothing);
  });
}
