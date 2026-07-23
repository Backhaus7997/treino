// Widget tests for the Chat detail pane composer (Fase 8, WU-08) — estados
// enabled/disabled/sending vía tokens v2.
//
// Cubre:
//   - Con `sending == true` (envío en curso O upload en curso, según arma
//     `_ChatDetailPaneState.build`), el botón de enviar queda deshabilitado
//     (sin gesture — TreinoTappable.onTap == null) y el campo de texto queda
//     `enabled: false`.
//   - Con `sending == false`, el botón queda habilitado (onTap != null) y el
//     campo `enabled: true`.
//
// Los tests V2 (`chat_web_v2_media_test.dart`, botón adjuntar habilitado con
// tooltip "Adjuntar foto") y V3 (`chat_web_v3_video_test.dart`, menú
// Foto/Video) NO se duplican acá — se preservan corriéndolos junto a este
// archivo; este WU no tocó `_openAttachMenu` ni sus keys.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/motion/treino_tappable.dart';
import 'package:treino/features/coach_hub/presentation/sections/chat/widgets/chat_detail_pane.dart';
import 'package:treino/l10n/app_l10n.dart';

Widget _wrapComposer(Widget child, {required bool dark}) => MediaQuery(
      data: const MediaQueryData(size: Size(1200, 800)),
      child: MaterialApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(body: child),
      ),
    );

void main() {
  group('ChatDetailPane composer — estados (WU-08)', () {
    testWidgets(
      'sending == true: botón enviar deshabilitado (sin gesture) y campo '
      'de texto enabled:false',
      (tester) async {
        final ctrl = TextEditingController(text: 'hola');
        addTearDown(ctrl.dispose);

        await tester.pumpWidget(_wrapComposer(
          Builder(builder: (context) {
            final palette = AppPalette.of(context);
            return chatDetailPaneComposerForTest(
              controller: ctrl,
              sending: true,
              onSend: () {},
              onAttach: () {},
              palette: palette,
            );
          }),
          dark: true,
        ));
        await tester.pump();

        final tappable = tester.widget<TreinoTappable>(
          find.byKey(const Key('chat_send_button')),
        );
        expect(tappable.onTap, isNull,
            reason: 'sending==true debe deshabilitar el botón enviar');

        final field = tester.widget<TextField>(
          find.byKey(const Key('chat_composer_field')),
        );
        expect(field.enabled, isFalse);

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
      },
    );

    testWidgets(
      'sending == false: botón enviar habilitado (con gesture) y campo de '
      'texto enabled:true',
      (tester) async {
        final ctrl = TextEditingController(text: 'hola');
        addTearDown(ctrl.dispose);
        var tapped = false;

        await tester.pumpWidget(_wrapComposer(
          Builder(builder: (context) {
            final palette = AppPalette.of(context);
            return chatDetailPaneComposerForTest(
              controller: ctrl,
              sending: false,
              onSend: () => tapped = true,
              onAttach: () {},
              palette: palette,
            );
          }),
          dark: false,
        ));
        await tester.pump();

        final tappable = tester.widget<TreinoTappable>(
          find.byKey(const Key('chat_send_button')),
        );
        expect(tappable.onTap, isNotNull,
            reason: 'sending==false debe habilitar el botón enviar');

        final field = tester.widget<TextField>(
          find.byKey(const Key('chat_composer_field')),
        );
        expect(field.enabled, isTrue);

        await tester.tap(find.byKey(const Key('chat_send_button')));
        expect(tapped, isTrue);
      },
    );

    testWidgets(
      'botón enviar expone Semantics(button: true, label: "Enviar") — '
      'remediación a11y (adversarial WARNING-1)',
      (tester) async {
        final handle = tester.ensureSemantics();
        final ctrl = TextEditingController(text: 'hola');
        addTearDown(ctrl.dispose);

        await tester.pumpWidget(_wrapComposer(
          Builder(builder: (context) {
            final palette = AppPalette.of(context);
            return chatDetailPaneComposerForTest(
              controller: ctrl,
              sending: false,
              onSend: () {},
              onAttach: () {},
              palette: palette,
            );
          }),
          dark: false,
        ));
        await tester.pump();

        final semantics =
            tester.getSemantics(find.byKey(const Key('chat_send_button')));
        expect(
          semantics.flagsCollection.isButton,
          isTrue,
          reason: 'el CTA principal del composer debe anunciarse como '
              'botón para screen readers (TreinoTappable pelado no lo '
              'hacía)',
        );
        expect(semantics.label, 'Enviar');

        handle.dispose();
      },
    );
  });
}
