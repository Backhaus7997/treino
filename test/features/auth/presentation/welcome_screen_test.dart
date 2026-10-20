import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/features/auth/presentation/legal/legal_content.dart';
import 'package:treino/features/auth/presentation/welcome_screen.dart';
import 'package:treino/features/auth/presentation/widgets/auth_pill_button.dart';
import 'package:treino/features/auth/presentation/widgets/auth_secondary_button.dart';
import 'package:treino/features/auth/presentation/widgets/terms_notice_text.dart';
import 'package:treino/features/auth/presentation/widgets/trainer_inquiry_card.dart';
import 'package:treino/core/widgets/treino_logo.dart';
import 'package:treino/l10n/app_l10n.dart';

GoRouter _makeRouter(Widget home) => GoRouter(
      initialLocation: '/welcome',
      routes: [
        GoRoute(path: '/welcome', builder: (_, __) => home),
        GoRoute(
          path: '/register',
          builder: (_, __) => const Scaffold(body: Text('REGISTER')),
        ),
        GoRoute(
          path: '/login',
          builder: (_, __) => const Scaffold(body: Text('LOGIN')),
        ),
      ],
    );

Future<bool> _noAbre(Uri _) async => false;

Widget _buildApp({Future<bool> Function(Uri url) abrirUrl = _noAbre}) {
  final screen = WelcomeScreen(abrirUrl: abrirUrl);
  final router = _makeRouter(screen);
  return ProviderScope(
    child: MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
    ),
  );
}

void main() {
  // ---------------------------------------------------------------------------
  // B03: renders eyebrow, logo, headline, body, CTA
  // ---------------------------------------------------------------------------
  testWidgets('renders eyebrow text', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('ENTRENAMIENTO'), findsOneWidget);
  });

  testWidgets('renders TreinoLogo', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    expect(find.byType(TreinoLogo), findsOneWidget);
  });

  testWidgets('renders headline parts in textPrimary (not accent)',
      (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    const palette = AppPalette.mintMagenta;

    // Headline uses RichText spans — check that both LIGHT halves render in
    // textPrimary (not accent). Keyed off l10n instead of literal copy: this
    // asserts a COLOR contract, so a copy change shouldn't break it.
    final l10n = AppL10n.of(tester.element(find.byType(WelcomeScreen)));
    final lightHalves = <String>[
      l10n.authBrandHeadline1Light,
      l10n.authBrandHeadline2Light,
    ];
    final foundInPrimary = <String>{};
    for (final rt in tester.allWidgets.whereType<RichText>()) {
      final span = rt.text;
      if (span is TextSpan && span.children != null) {
        for (final child in span.children!) {
          if (child is TextSpan) {
            final text = child.text ?? '';
            final color = child.style?.color;
            for (final half in lightHalves) {
              if (text.contains(half) && color == palette.textPrimary) {
                foundInPrimary.add(half);
              }
            }
          }
        }
      }
    }
    for (final half in lightHalves) {
      expect(foundInPrimary, contains(half),
          reason: '"$half" must be textPrimary (white), not accent');
    }
  });

  testWidgets('uses a left-border accent bar, no IntrinsicHeight (F2)',
      (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    // The old IntrinsicHeight + Spacer anti-pattern is gone entirely.
    expect(find.byType(IntrinsicHeight), findsNothing);

    // The headline accent bar is now a 3px left BorderSide on a DecoratedBox.
    final hasAccentBar =
        tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).any((d) {
      final dec = d.decoration;
      if (dec is! BoxDecoration) return false;
      final border = dec.border;
      return border is Border && border.left.width == 3;
    });
    expect(hasAccentBar, isTrue,
        reason: 'headline must keep its 3px left accent bar');
  });

  // ---------------------------------------------------------------------------
  // F2: no overflow across phone / small-phone / tablet viewports. The content
  // fills the viewport (CTAs at the bottom) and scrolls instead of overflowing
  // when it is short.
  // ---------------------------------------------------------------------------
  for (final size in const [
    Size(375, 812), // iPhone
    Size(360, 640), // small Android
    Size(768, 1024), // iPad portrait
  ]) {
    testWidgets('renders without overflow at ${size.width}x${size.height}',
        (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(IntrinsicHeight), findsNothing);
    });
  }

  testWidgets('renders body text', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    expect(find.textContaining('Tu rutina, tus series'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // B03: "EMPEZAR" CTA navigates to /register
  // ---------------------------------------------------------------------------
  testWidgets('EMPEZAR CTA navigates to /register', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(AuthPillButton, 'EMPEZAR'));
    await tester.pumpAndSettle();

    expect(find.text('REGISTER'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // Spotify layout: la bienvenida muestra SOLO los dos pills. Google/Apple y su
  // leyenda legal viven en Login y Registro.
  // ---------------------------------------------------------------------------
  testWidgets('muestra exactamente dos pills y nada de Google/Apple',
      (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    expect(find.byType(AuthPillButton), findsNWidgets(2));
    expect(find.widgetWithText(AuthPillButton, 'EMPEZAR'), findsOneWidget);
    expect(
        find.widgetWithText(AuthPillButton, 'INICIAR SESIÓN'), findsOneWidget);
    expect(find.byType(AuthSecondaryButton), findsNothing);
    expect(find.textContaining('Google'), findsNothing);
    expect(find.textContaining('Apple'), findsNothing);
  });

  testWidgets(
      'el aviso de Términos y Privacidad va debajo de la tarjeta de '
      'entrenador, sin nombrar a Google/Apple', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    final aviso = find.byType(TermsNoticeText);
    expect(aviso, findsOneWidget);
    expect(tester.widget<TermsNoticeText>(aviso).lead,
        TermsNoticeText.leadGeneric);
    expect(
      tester.getRect(aviso).top,
      greaterThan(tester.getRect(find.byType(TrainerInquiryCard)).bottom),
    );
  });

  testWidgets(
      'INICIAR SESIÓN es un pill invertido a 12 px de EMPEZAR, sin pregunta '
      'en el medio, y la tarjeta de entrenador va debajo', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    final empezar =
        tester.getRect(find.widgetWithText(AuthPillButton, 'EMPEZAR'));
    final signIn = tester.getRect(find.byKey(const Key('welcome-sign-in')));
    final tarjeta = tester.getRect(find.byType(TrainerInquiryCard));

    expect(find.text('¿Ya tenés cuenta?'), findsNothing);
    expect(signIn.top - empezar.bottom, 12);
    // Mismo tamaño que EMPEZAR: es un botón, no un link.
    expect(signIn.height, empezar.height);
    expect(signIn.width, empezar.width);
    expect(tarjeta.top, greaterThan(signIn.bottom));
    final button =
        tester.widget<AuthPillButton>(find.byKey(const Key('welcome-sign-in')));
    expect(button.outlined, isTrue);
  });

  // ---------------------------------------------------------------------------
  // B03: "Iniciar sesión" link navigates to /login
  // ---------------------------------------------------------------------------
  testWidgets('"Iniciar sesión" link navigates to /login', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('INICIAR SESIÓN'));
    await tester.pumpAndSettle();

    expect(find.text('LOGIN'), findsOneWidget);
  });

  // ---------------------------------------------------------------------------
  // «Quiero ser entrenador»: los PF no tienen alta self-service (los crea el
  // equipo por Admin SDK), así que el acceso lleva al mismo contacto por mail
  // que el Coach Hub, no a un registro.
  // ---------------------------------------------------------------------------
  testWidgets(
      'muestra el acceso «Quiero ser entrenador» con la misma tarjeta '
      'que Login y Registro', (tester) async {
    await tester.pumpWidget(_buildApp());
    await tester.pumpAndSettle();

    final cta = find.byType(TrainerInquiryCard);
    expect(cta, findsOneWidget);
    expect(find.text('¿Sos entrenador?'), findsOneWidget);
    expect(find.text('Pedí tu alta al equipo TREINO'), findsOneWidget);
    expect(
      find
          .ancestor(of: cta, matching: find.byType(Semantics))
          .evaluate()
          .any((e) => (e.widget as Semantics).properties.button == true),
      isTrue,
      reason: 'el lector de pantalla tiene que anunciarlo como botón',
    );
  });

  testWidgets('tocarlo abre el mail al equipo con el asunto del Coach Hub',
      (tester) async {
    final abiertas = <Uri>[];
    await tester.pumpWidget(_buildApp(abrirUrl: (url) async {
      abiertas.add(url);
      return true;
    }));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byType(TrainerInquiryCard));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TrainerInquiryCard));
    await tester.pumpAndSettle();

    expect(abiertas, hasLength(1));
    final url = abiertas.single;
    expect(url.scheme, 'mailto');
    expect(url.path, kLegalContactEmail);
    expect(url.query, 'subject=Quiero%20ser%20entrenador%20en%20TREINO');
    expect(find.byType(SnackBar), findsNothing);
    // Abre el mail directo: no el diálogo que la tarjeta muestra en Login.
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('sin cliente de mail avisa y deja la dirección a la vista',
      (tester) async {
    await tester.pumpWidget(_buildApp(abrirUrl: (_) async => false));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byType(TrainerInquiryCard));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TrainerInquiryCard));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining(kLegalContactEmail), findsOneWidget);
  });

  testWidgets('si la plataforma lanza al abrir el mail, también avisa',
      (tester) async {
    await tester.pumpWidget(
        _buildApp(abrirUrl: (_) async => throw Exception('sin handler')));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byType(TrainerInquiryCard));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TrainerInquiryCard));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.textContaining(kLegalContactEmail), findsOneWidget);
  });
}
