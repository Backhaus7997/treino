// #1498 — VER PREVIEW: el PF mira su propio perfil público.
//
// Tres cosas del reporte, una por grupo:
//   (b) CONSULTAR y PEDIR VÍNCULO se veían activos y no hacían nada (ninguno
//       actúa sobre uno mismo) → en preview están deshabilitados y la pantalla
//       dice que es una vista previa;
//   (c) «AÑOS EXP —» sin que el PF supiera que el dato que falta es suyo → en
//       preview se lo avisa (y lo lleva al formulario);
//   y el control: para un alumno (sin `preview`) NADA de esto aparece.
//
// (a), el tab resaltado, se testea contra el router real en
// `test/app/router_tab_highlight_test.dart`.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_discovery_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_public_profile.dart';
import 'package:treino/features/coach/presentation/trainer_public_profile_screen.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_contact_cta_stub.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_inquiry_cta.dart';
import 'package:treino/features/coach/presentation/widgets/trainer_preview_notices.dart';
import 'package:treino/features/reviews/application/review_providers.dart';
import 'package:treino/l10n/app_l10n.dart';

const _uid = 'trainer-1';

/// `years` null = el PF no cargó sus años de experiencia.
TrainerPublicProfile _profile({int? years}) => TrainerPublicProfile(
      uid: _uid,
      displayName: 'Coach Lautaro',
      trainerExperienceYears: years,
    );

Widget _wrap({
  required bool preview,
  int? years,
  GoRouter? router,
  List<Override> extra = const [],
}) {
  final overrides = <Override>[
    trainerByIdProvider(_uid)
        .overrideWith((ref) async => _profile(years: years)),
    currentAthleteLinkAnyStatusProvider
        .overrideWith((ref) => Stream.value(null)),
    currentAthleteLinkProvider.overrideWith((ref) => Stream.value(null)),
    trainerReviewsProvider(_uid).overrideWith((ref) => Stream.value(const [])),
    ...extra,
  ];
  final theme = AppTheme.dark();
  final screen = TrainerPublicProfileScreen(uid: _uid, preview: preview);
  return ProviderScope(
    overrides: overrides,
    child: router == null
        ? MaterialApp(
            theme: theme,
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            locale: const Locale('es', 'AR'),
            home: screen,
          )
        : MaterialApp.router(
            theme: theme,
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            locale: const Locale('es', 'AR'),
            routerConfig: router,
          ),
  );
}

bool _enabled(WidgetTester tester, Finder button) =>
    tester.widget<ButtonStyleButton>(button).onPressed != null;

Finder get _inquiryButton => find.descendant(
      of: find.byType(TrainerInquiryCta),
      matching: find.byType(FilledButton),
    );

Finder get _linkButton => find.descendant(
      of: find.byType(TrainerContactCtaStub),
      matching: find.byType(OutlinedButton),
    );

void main() {
  group('con preview (el PF mirándose a sí mismo)', () {
    testWidgets('marca la pantalla como VISTA PREVIA', (tester) async {
      await tester.pumpWidget(_wrap(preview: true, years: 5));
      await tester.pumpAndSettle();

      expect(find.byType(TrainerPreviewBanner), findsOneWidget);
      expect(find.text('VISTA PREVIA'), findsOneWidget);
    });

    testWidgets('CONSULTAR y PEDIR VÍNCULO se ven pero están deshabilitados',
        (tester) async {
      await tester.pumpWidget(_wrap(preview: true, years: 5));
      await tester.pumpAndSettle();

      // Siguen a la vista (es lo que ve el alumno)…
      expect(find.text('CONSULTAR'), findsOneWidget);
      expect(find.text('PEDIR VÍNCULO'), findsOneWidget);
      // …pero no son un botón activo que no hace nada.
      expect(_enabled(tester, _inquiryButton), isFalse);
      expect(_enabled(tester, _linkButton), isFalse);
    });

    testWidgets('sin años de experiencia → avisa al PF que le falta cargarlos',
        (tester) async {
      await tester.pumpWidget(_wrap(preview: true));
      await tester.pumpAndSettle();

      expect(find.text('AÑOS EXP'), findsOneWidget);
      expect(
          find.byType(TrainerPreviewMissingExperienceNotice), findsOneWidget);
      expect(find.textContaining('años de experiencia'), findsOneWidget);
    });

    testWidgets('con años cargados no hay aviso', (tester) async {
      await tester.pumpWidget(_wrap(preview: true, years: 7));
      await tester.pumpAndSettle();

      expect(find.text('7'), findsOneWidget);
      expect(find.byType(TrainerPreviewMissingExperienceNotice), findsNothing);
    });

    testWidgets(
        'tocar el aviso lleva a editar el perfil, y al volver recarga el perfil '
        'público (el dato recién guardado se ve)', (tester) async {
      var cargas = 0;
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) =>
                const TrainerPublicProfileScreen(uid: _uid, preview: true),
          ),
          GoRoute(
            path: '/profile/edit-trainer',
            builder: (_, __) => const Scaffold(body: Text('EDITAR PERFIL')),
          ),
        ],
      );
      await tester.pumpWidget(_wrap(
        preview: true,
        router: router,
        extra: [
          // Cuenta cuántas veces se lee el perfil público.
          trainerByIdProvider(_uid).overrideWith((ref) async {
            cargas++;
            return _profile(years: cargas > 1 ? 9 : null);
          }),
        ],
      ));
      await tester.pumpAndSettle();
      expect(cargas, 1);
      expect(
          find.byType(TrainerPreviewMissingExperienceNotice), findsOneWidget);

      await tester.tap(find.byType(TrainerPreviewMissingExperienceNotice));
      await tester.pumpAndSettle();
      expect(find.text('EDITAR PERFIL'), findsOneWidget);

      router.pop();
      await tester.pumpAndSettle();

      expect(cargas, 2, reason: 'volver del formulario invalida el perfil');
      expect(find.byType(TrainerPreviewMissingExperienceNotice), findsNothing);
      expect(find.text('9'), findsOneWidget);
    });

    testWidgets('atrás sin historial cae en /profile, no en /coach',
        (tester) async {
      final router = GoRouter(
        initialLocation: '/profile/trainer-preview/$_uid',
        routes: [
          GoRoute(
            path: '/profile',
            builder: (_, __) => const Scaffold(body: Text('PERFIL')),
            routes: [
              GoRoute(
                path: 'trainer-preview/:uid',
                builder: (_, __) =>
                    const TrainerPublicProfileScreen(uid: _uid, preview: true),
              ),
            ],
          ),
          GoRoute(
            path: '/coach',
            builder: (_, __) => const Scaffold(body: Text('COACH')),
          ),
        ],
      );
      await tester.pumpWidget(_wrap(preview: true, years: 5, router: router));
      await tester.pumpAndSettle();

      // Deep link: nada que popear.
      await tester.tap(find.byType(IconButton).first);
      await tester.pumpAndSettle();

      expect(find.text('PERFIL'), findsOneWidget);
      expect(find.text('COACH'), findsNothing);
    });
  });

  group('sin preview (un alumno) nada cambia', () {
    testWidgets('ni banner, ni aviso, y los CTAs siguen activos',
        (tester) async {
      await tester.pumpWidget(_wrap(preview: false));
      await tester.pumpAndSettle();

      expect(find.byType(TrainerPreviewBanner), findsNothing);
      expect(find.byType(TrainerPreviewMissingExperienceNotice), findsNothing);
      expect(_enabled(tester, _inquiryButton), isTrue);
      expect(_enabled(tester, _linkButton), isTrue);
    });
  });
}
