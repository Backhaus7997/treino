import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart'
    show trainerLinksStreamProvider;
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/presentation/trainer_dashboard_tab.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart'
    show userPublicProfileProvider;
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

// The dashboard header avatar was a bare decoration — no tap handler at all
// (unlike the bell right next to it, which was already wired to the
// pending-requests modal and only looked inert at badgeCount == 0). It now
// opens the professional-profile EDITOR: from the dashboard the useful
// destination is the form, not the PERFIL tab root the trainer would then
// have to tap through.

const _kTrainer = 'trainer-1';

UserProfile _trainerProfile() => UserProfile(
      uid: _kTrainer,
      email: 'mateo@test.com',
      displayName: 'Mateo Presset',
      role: UserRole.trainer,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// Records what the editor route was actually entered with.
///
/// Asserting on `router.currentConfiguration.uri` does NOT work here: with an
/// imperative `push` it keeps reporting the declarative location (`/home`)
/// even though the pushed page is on screen. Capturing the route's own
/// [GoRouterState] is the accurate read.
Uri? _editorEnteredWith;

Future<GoRouter> _pumpDashboard(WidgetTester tester) async {
  _editorEnteredWith = null;
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, __) => const Scaffold(body: TrainerDashboardTab()),
      ),
      GoRoute(
        path: '/profile',
        builder: (_, __) => const Scaffold(body: Text('PERFIL-TAB-STUB')),
        routes: [
          GoRoute(
            path: 'edit-trainer',
            builder: (_, state) {
              _editorEnteredWith = state.uri;
              return const Scaffold(body: Text('EDITOR-STUB'));
            },
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue(_kTrainer),
        userProfileProvider
            .overrideWith((ref) => Stream.value(_trainerProfile())),
        userPublicProfileProvider.overrideWith(
          (ref, uid) => Stream<UserPublicProfile?>.value(null),
        ),
        trainerLinksStreamProvider.overrideWith(
          (ref) => Stream.value(const <TrainerLink>[]),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return router;
}

void main() {
  group('trainer dashboard header avatar', () {
    testWidgets(
        'tapping the avatar opens the professional-profile EDITOR, not the '
        'PERFIL tab root', (tester) async {
      await _pumpDashboard(tester);

      // The initials come from the trainer's own display name.
      expect(find.text('MP'), findsOneWidget);

      await tester.tap(find.text('MP'));
      await tester.pumpAndSettle();

      expect(find.text('EDITOR-STUB'), findsOneWidget);
      expect(find.text('PERFIL-TAB-STUB'), findsNothing);
      expect(_editorEnteredWith?.path, equals('/profile/edit-trainer'));
    });

    // `push`, not `go`: the editor ends its edit-mode save with
    // `context.pop()` (ADR-TPO-006). With `go` there would be nothing to pop
    // and the trainer would be stranded on the form after saving.
    testWidgets('it is PUSHED — popping returns to the dashboard',
        (tester) async {
      final router = await _pumpDashboard(tester);

      await tester.tap(find.text('MP'));
      await tester.pumpAndSettle();
      expect(find.text('EDITOR-STUB'), findsOneWidget);

      // Exactly what the editor does after a successful save.
      router.pop();
      await tester.pumpAndSettle();

      expect(find.text('MP'), findsOneWidget, reason: 'back on the dashboard');
      expect(find.text('EDITOR-STUB'), findsNothing);
    });

    // The editor carries no ?mode: that param drives the first-run onboarding
    // gate, and any other value falls through to edit mode.
    testWidgets('does not request onboarding mode', (tester) async {
      await _pumpDashboard(tester);

      await tester.tap(find.text('MP'));
      await tester.pumpAndSettle();

      expect(_editorEnteredWith?.queryParameters, isEmpty);
    });

    // A label and the button flag are NOT enough, and this test used to check
    // only those. The Semantics carried `excludeSemantics: true` to keep the
    // decorative initials out of the label, but that flag drops the semantics
    // of EVERY descendant — including the tap action the GestureDetector
    // contributes. VoiceOver announced a button whose double-tap fired
    // nothing, while an ordinary touch kept working, so only the a11y path was
    // broken. The fix is the bell's shape: no `excludeSemantics` on the
    // annotation, an `ExcludeSemantics` around the decorative subtree only.
    //
    // `isSemantics`, not `matchesSemantics`: its parameters are nullable, so
    // this pins the two properties that carry the contract and stays silent
    // about every other flag the framework may add. (`matchesSemantics` and
    // `containsSemantics` are both deprecated in favour of it.)
    testWidgets('the avatar is an ACTIVATABLE button, not just a labelled one',
        (tester) async {
      // Disposed inline, not via addTearDown: the framework's
      // "SemanticsHandle was active at the end of the test" check runs BEFORE
      // tear-downs, so a deferred dispose fails the test.
      final handle = tester.ensureSemantics();
      await _pumpDashboard(tester);

      final avatar = find.bySemanticsLabel('Editar tu perfil profesional');
      expect(avatar, findsOneWidget);
      expect(
        tester.getSemantics(avatar),
        isSemantics(isButton: true, hasTapAction: true),
      );

      // The initials must still be excluded, or the label reads
      // "Editar tu perfil profesional MP".
      expect(find.bySemanticsLabel(RegExp('perfil profesional.*MP')),
          findsNothing);
      handle.dispose();
    });

    // Both header controls need `container: true` on their Semantics or the
    // annotation merges into the enclosing node — the whole header was being
    // announced as ONE blob ("MARTES 28 JULIO HOLA, MATEO 0 solicitudes
    // pendientes Ver tu perfil"). The bell had this defect before the avatar
    // was ever wired.
    testWidgets('bell and avatar are SEPARATE nodes, not one merged header',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpDashboard(tester);

      expect(find.bySemanticsLabel('0 solicitudes pendientes'), findsOneWidget);
      expect(find.bySemanticsLabel('Editar tu perfil profesional'),
          findsOneWidget);
      // The greeting must NOT carry either control's label.
      expect(
        find.bySemanticsLabel(RegExp(r'HOLA, MATEO.*(solicitudes|perfil)')),
        findsNothing,
      );
      handle.dispose();
    });

    testWidgets('the avatar meets the 44pt minimum touch target',
        (tester) async {
      await _pumpDashboard(tester);

      // The painted circle is only 36px; measure the GESTURE DETECTOR — the
      // actual tap target — not the avatar, and not the inner ConstrainedBox
      // the 36px Container mounts of its own.
      final box = tester.getSize(
        find
            .ancestor(
              of: find.byType(ConstrainedBox),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      expect(box.width, greaterThanOrEqualTo(44));
      expect(box.height, greaterThanOrEqualTo(44));
    });
  });
}
