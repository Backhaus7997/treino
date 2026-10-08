import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/auth/presentation/legal/legal_content.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_not_allowed_screen.dart';
import 'package:treino/features/coach_hub/presentation/widgets/button/treino_button.dart';
import 'package:treino/l10n/app_l10n.dart';

/// El montaje NO overridea ningún provider de auth: `/not-allowed` no puede
/// depender de `AuthNotifier`/`AuthService` (su `signOut` espera un
/// `GoogleSignIn.initialize()` que el Hub nunca hace y se cuelga). Si la
/// pantalla leyera esos providers, este montaje limpio fallaría.
Future<void> _pump(
  WidgetTester tester, {
  required ThemeData theme,
  Future<bool> Function(Uri)? abrirUrl,
  Future<void> Function()? cerrarSesion,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: theme,
        locale: const Locale('es', 'AR'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: CoachHubNotAllowedScreen(
          abrirUrl: abrirUrl ?? (_) async => true,
          cerrarSesion: cerrarSesion ?? () async {},
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  final temas = <String, ThemeData Function()>{
    'dark': AppTheme.dark,
    'light': AppTheme.light,
  };

  for (final entry in temas.entries) {
    group('CoachHubNotAllowedScreen (${entry.key})', () {
      // SCENARIO-CHW-AUTH-015
      testWidgets('nombra App Store y Play Store sin ningún link a una store',
          (tester) async {
        final abiertas = <Uri>[];
        await _pump(
          tester,
          theme: entry.value(),
          abrirUrl: (u) async {
            abiertas.add(u);
            return true;
          },
        );

        expect(find.textContaining('App Store'), findsOneWidget);
        // AGENTS.md: la marca va en mayúsculas.
        expect(find.textContaining('app de TREINO'), findsOneWidget);
        expect(find.textContaining('Play Store'), findsOneWidget);

        // Los únicos tappables son contacto y cerrar sesión: dos TreinoButton.
        // Ninguno de los dos apunta a una store (la app no está publicada).
        expect(find.byType(TreinoButton), findsNWidgets(2));
        // Y ningún texto lleva una URL ni un TextSpan tappable.
        final textos = tester.widgetList<RichText>(find.byType(RichText));
        for (final t in textos) {
          expect(t.text.toPlainText(), isNot(contains('http')));
          var conRecognizer = false;
          t.text.visitChildren((span) {
            if (span is TextSpan && span.recognizer != null) {
              conRecognizer = true;
            }
            return true;
          });
          expect(conRecognizer, isFalse, reason: 'hay un link tappable');
        }
        expect(abiertas, isEmpty);
      });

      // SCENARIO-CHW-AUTH-016
      testWidgets(
          'el contacto abre un mailto a kLegalContactEmail con el asunto en %20',
          (tester) async {
        final abiertas = <Uri>[];
        await _pump(
          tester,
          theme: entry.value(),
          abrirUrl: (u) async {
            abiertas.add(u);
            return true;
          },
        );

        // La dirección es visible como texto: sin cliente de mail configurado
        // el mailto no hace nada y el usuario la tiene que poder copiar.
        expect(find.textContaining(kLegalContactEmail), findsWidgets);

        final cta = find.widgetWithText(
          TreinoButton,
          AppL10n.of(tester.element(find.byType(CoachHubNotAllowedScreen)))
              .coachHubNotAllowedContactCta,
        );
        expect(cta, findsOneWidget);
        await tester.tap(cta);
        await tester.pump();

        expect(abiertas, hasLength(1));
        final uri = abiertas.single;
        expect(uri.scheme, 'mailto');
        expect(uri.path, kLegalContactEmail);
        final asunto = AppL10n.of(
          tester.element(find.byType(CoachHubNotAllowedScreen)),
        ).coachHubNotAllowedMailSubject;
        expect(asunto, contains(' '), reason: 'el control necesita espacios');
        expect(asunto, endsWith('TREINO'));
        expect(Uri.decodeComponent(uri.query), contains('en TREINO'));
        expect(
            uri.toString(), contains('subject=${Uri.encodeComponent(asunto)}'));
        expect(uri.toString(), isNot(contains('+')));
        expect(uri.toString(), contains('%20'));
      });

      for (final falla in <String, Future<bool> Function(Uri)>{
        'devuelve false': (_) async => false,
        'lanza': (_) async => throw StateError('sin handler de mailto'),
      }.entries) {
        testWidgets(
            'si abrirUrl ${falla.key} muestra el aviso de escribir a la '
            'dirección visible, sin error sin manejar', (tester) async {
          await _pump(tester, theme: entry.value(), abrirUrl: falla.value);

          final l10n =
              AppL10n.of(tester.element(find.byType(CoachHubNotAllowedScreen)));
          expect(
              find.text(l10n.coachHubNotAllowedContactFallback), findsNothing);

          await tester.tap(
            find.widgetWithText(
                TreinoButton, l10n.coachHubNotAllowedContactCta),
          );
          await tester.pump();
          await tester.pump();

          expect(find.text(l10n.coachHubNotAllowedContactFallback),
              findsOneWidget);
          // La dirección sigue visible para copiarla.
          expect(find.text(kLegalContactEmail), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }

      testWidgets('si abrirUrl devuelve true no muestra el aviso',
          (tester) async {
        await _pump(tester, theme: entry.value());
        final l10n =
            AppL10n.of(tester.element(find.byType(CoachHubNotAllowedScreen)));
        await tester.tap(
          find.widgetWithText(TreinoButton, l10n.coachHubNotAllowedContactCta),
        );
        await tester.pump();
        await tester.pump();
        expect(find.text(l10n.coachHubNotAllowedContactFallback), findsNothing);
      });

      // SCENARIO-CHW-AUTH-017
      testWidgets('Cerrar sesión invoca cerrarSesion, sin AuthService/Notifier',
          (tester) async {
        var cerradas = 0;
        await _pump(
          tester,
          theme: entry.value(),
          cerrarSesion: () async => cerradas++,
        );

        final l10n =
            AppL10n.of(tester.element(find.byType(CoachHubNotAllowedScreen)));
        await tester.tap(
          find.widgetWithText(TreinoButton, l10n.authProfileSignOut),
        );
        await tester.pump();

        expect(cerradas, 1);
        expect(find.text(l10n.coachHubSignOutError), findsNothing);
      });

      testWidgets('si cerrarSesion falla muestra coachHubSignOutError',
          (tester) async {
        await _pump(
          tester,
          theme: entry.value(),
          cerrarSesion: () async => throw StateError('boom'),
        );

        final l10n =
            AppL10n.of(tester.element(find.byType(CoachHubNotAllowedScreen)));
        await tester.tap(
          find.widgetWithText(TreinoButton, l10n.authProfileSignOut),
        );
        await tester.pump();
        await tester.pump();

        expect(find.text(l10n.coachHubSignOutError), findsOneWidget);
      });
    });
  }
}
