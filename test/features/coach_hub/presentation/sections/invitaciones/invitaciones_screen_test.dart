// WU-04 (Fase 4) — InvitacionesScreen + tab Pendientes.
//
// Widget tests: estados (loading/error/empty/data) del stream, filtrado por
// tab (chips), y el flujo aceptar/rechazar (TreinoDialog de confirmación →
// trainerLinkRepositoryProvider.accept/decline + snackbar), pumpeados con
// providers stub (sin Firestore). Mismo patrón que alumnos_screen_test.dart.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/trainer_link_repository.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/invitaciones/invitaciones_screen.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockRepo extends Mock implements TrainerLinkRepository {}

TrainerLink _link(
  String athleteId,
  TrainerLinkStatus status, {
  String? id,
  DateTime? requestedAt,
}) =>
    TrainerLink(
      id: id ?? 'l_$athleteId',
      trainerId: 't1',
      athleteId: athleteId,
      status: status,
      requestedAt: requestedAt ?? DateTime.now(),
    );

UserPublicProfile _prof(String uid, String name) =>
    UserPublicProfile(uid: uid, displayName: name);

Future<void> _pump(
  WidgetTester tester, {
  Stream<List<TrainerLink>>? linksStream,
  List<TrainerLink>? links,
  List<UserPublicProfile> profiles = const [],
  TrainerLinkRepository? repo,
  // `false` cuando el stream de links queda colgado en loading a propósito
  // (TreinoShimmer corre en loop infinito — pumpAndSettle no termina nunca).
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final profileByUid = {for (final p in profiles) p.uid: p};

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        trainerLinksStreamProvider.overrideWith(
          (ref) => linksStream ?? Stream.value(links ?? const []),
        ),
        userPublicProfileProvider.overrideWith(
          (ref, uid) => Stream.value(profileByUid[uid]),
        ),
        if (repo != null) trainerLinkRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(body: InvitacionesScreen()),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  setUpAll(() => registerFallbackValue(''));

  group('InvitacionesScreen — estados', () {
    testWidgets('loading → shimmer visible, sin tarjetas', (tester) async {
      final controller = StreamController<List<TrainerLink>>();
      addTearDown(controller.close);

      await _pump(tester, linksStream: controller.stream, settle: false);

      expect(find.byKey(const Key('list_row_skeleton')), findsWidgets);
      expect(
        find.byWidgetPredicate((w) =>
            w.key is ValueKey &&
            (w.key! as ValueKey)
                .value
                .toString()
                .startsWith('solicitud_card_')),
        findsNothing,
      );
    });

    testWidgets('error → mensaje de error + retry', (tester) async {
      await _pump(
        tester,
        linksStream: Stream<List<TrainerLink>>.error(Exception('boom')),
      );

      expect(find.text('No pudimos cargar esta sección.'), findsOneWidget);
      expect(find.byKey(const Key('invitaciones_retry')), findsOneWidget);
    });

    testWidgets('sin solicitudes pendientes → estado vacío honesto',
        (tester) async {
      await _pump(tester, links: const []);

      expect(find.text('No tenés solicitudes pendientes.'), findsOneWidget);
    });

    testWidgets('data → una SolicitudCard por solicitud pendiente',
        (tester) async {
      await _pump(
        tester,
        links: [
          _link('a1', TrainerLinkStatus.pending),
          _link('a2', TrainerLinkStatus.pending),
          _link('a3', TrainerLinkStatus.active),
        ],
        profiles: [
          _prof('a1', 'Ana García'),
          _prof('a2', 'Beto López'),
          _prof('a3', 'Caro Díaz'),
        ],
      );

      expect(find.byKey(const Key('solicitud_card_l_a1')), findsOneWidget);
      expect(find.byKey(const Key('solicitud_card_l_a2')), findsOneWidget);
      // a3 está active → no aparece en el tab Pendientes (default).
      expect(find.byKey(const Key('solicitud_card_l_a3')), findsNothing);
    });
  });

  group('InvitacionesScreen — tabs', () {
    testWidgets('cambiar a Aceptadas filtra solo active/paused',
        (tester) async {
      await _pump(
        tester,
        links: [
          _link('a1', TrainerLinkStatus.pending),
          _link('a2', TrainerLinkStatus.active),
          _link('a3', TrainerLinkStatus.paused),
        ],
        profiles: [
          _prof('a1', 'Ana García'),
          _prof('a2', 'Beto López'),
          _prof('a3', 'Caro Díaz'),
        ],
      );

      await tester.tap(find.byKey(const Key('filter_chip_Aceptadas')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('solicitud_card_l_a1')), findsNothing);
      expect(find.byKey(const Key('solicitud_card_l_a2')), findsOneWidget);
      expect(find.byKey(const Key('solicitud_card_l_a3')), findsOneWidget);
    });

    testWidgets('los chips muestran badge con el conteo real', (tester) async {
      await _pump(
        tester,
        links: [
          _link('a1', TrainerLinkStatus.pending),
          _link('a2', TrainerLinkStatus.pending),
          _link('a3', TrainerLinkStatus.terminated),
        ],
        profiles: [
          _prof('a1', 'Ana García'),
          _prof('a2', 'Beto López'),
          _prof('a3', 'Caro Díaz'),
        ],
      );

      expect(
        find.descendant(
          of: find.byKey(const Key('filter_chip_Pendientes')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('filter_chip_Rechazadas')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
    });
  });

  group('InvitacionesScreen — acciones aceptar/rechazar', () {
    testWidgets(
        'aceptar → dialog de confirmación → repo.accept + snackbar de éxito',
        (tester) async {
      final repo = _MockRepo();
      when(() => repo.accept(any())).thenAnswer((_) async {});

      await _pump(
        tester,
        links: [_link('a1', TrainerLinkStatus.pending, id: 'l1')],
        profiles: [_prof('a1', 'Ana García')],
        repo: repo,
      );

      await tester.tap(find.byKey(const Key('accept_l1')));
      await tester.pumpAndSettle();

      verifyNever(() => repo.accept(any()));
      expect(find.byKey(const Key('dialog_primary_button')), findsOneWidget);

      // No pumpAndSettle: tras aceptar, la tarjeta queda `busy` (spinner
      // indeterminado en loop) hasta que el stream real-time la saca de la
      // lista — acá el stream stub es estático, así que se pumpea acotado.
      await tester.tap(find.byKey(const Key('dialog_primary_button')));
      await tester.pump(); // cierra el dialog
      await tester.pump(const Duration(milliseconds: 300)); // anim de cierre
      await tester.pump(); // resuelve el Future de repo.accept + snackbar

      verify(() => repo.accept('l1')).called(1);
      expect(find.text('Vínculo aceptado.'), findsOneWidget);
    });

    testWidgets(
        'rechazar → dialog de confirmación → repo.decline + snackbar de éxito',
        (tester) async {
      final repo = _MockRepo();
      when(() => repo.decline(any())).thenAnswer((_) async {});

      await _pump(
        tester,
        links: [_link('a1', TrainerLinkStatus.pending, id: 'l1')],
        profiles: [_prof('a1', 'Ana García')],
        repo: repo,
      );

      await tester.tap(find.byKey(const Key('decline_l1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('dialog_primary_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      verify(() => repo.decline('l1')).called(1);
      expect(find.text('Solicitud rechazada.'), findsOneWidget);
    });

    testWidgets('cancelar el diálogo NO llama al repo', (tester) async {
      final repo = _MockRepo();
      when(() => repo.accept(any())).thenAnswer((_) async {});

      await _pump(
        tester,
        links: [_link('a1', TrainerLinkStatus.pending, id: 'l1')],
        profiles: [_prof('a1', 'Ana García')],
        repo: repo,
      );

      await tester.tap(find.byKey(const Key('accept_l1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dialog_secondary_button')));
      await tester.pumpAndSettle();

      verifyNever(() => repo.accept(any()));
    });
  });
}
