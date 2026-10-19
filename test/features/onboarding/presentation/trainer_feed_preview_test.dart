import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/onboarding/presentation/trainer_previews.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../helpers/layout_failure.dart';

/// El mock del Feed en el onboarding del PF tiene que mostrar SÓLO lo que el
/// Feed real tiene (#1472): sin comentarios, sin post con foto, sin campana.
void main() {
  Future<void> pumpPreview(WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          home: const Scaffold(body: TrainerFeedPreview()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('TrainerFeedPreview: layout sin fallas', (tester) async {
    await pumpPreview(tester);

    expect(drainLayoutFailure(tester), isNull);
  });

  testWidgets('TrainerFeedPreview: ningún post lleva foto', (tester) async {
    await pumpPreview(tester);

    expect(find.byType(Image), findsNothing);
  });

  testWidgets(
      'TrainerFeedPreview: las reacciones son las reales, sin comentarios',
      (tester) async {
    await pumpPreview(tester);

    // like / fire / clap (`ReactionType`). Los dos posts muestran like y fire;
    // sólo el primero tiene tercera reacción.
    expect(find.byIcon(TreinoIcon.reactionLike), findsNWidgets(2));
    expect(find.byIcon(TreinoIcon.reactionFire), findsNWidgets(2));
    expect(find.byIcon(TreinoIcon.reactionClap), findsOneWidget);
    // El único `chat` que queda es el de mensajes del header: en los posts
    // era el "comentarios" que el Feed no tiene.
    expect(find.byIcon(TreinoIcon.chat), findsOneWidget);
  });

  testWidgets('TrainerFeedPreview: el header no tiene campana', (tester) async {
    await pumpPreview(tester);

    // La campana se mudó a Inicio (`NotificationBell`).
    expect(find.byIcon(TreinoIcon.bell), findsNothing);
  });
}
