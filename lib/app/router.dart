import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/treino_bottom_bar.dart';
import '../features/auth/application/auth_providers.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/auth/presentation/welcome_screen.dart';
import '../features/chat/presentation/chat_screen.dart';
import '../features/coach/coach_screen.dart';
import '../features/coach/application/trainer_link_providers.dart';
import '../features/coach/presentation/athlete_agenda_screen.dart';
import '../features/coach/presentation/athlete_detail_screen.dart';
import '../features/coach/presentation/availability_editor_screen.dart';
import '../features/coach/presentation/trainer_public_profile_screen.dart';
import '../features/workout/application/session_providers.dart'
    show currentUidProvider;
import '../features/workout/presentation/custom_exercise_editor_screen.dart';
import '../features/workout/presentation/my_exercises_screen.dart';
import '../features/workout/presentation/routine_editor_mode.dart';
import '../features/workout/presentation/routine_editor_screen.dart';
import '../features/workout/application/session_init.dart';
import '../features/workout/presentation/exercise_detail_screen.dart';
import '../features/workout/presentation/post_workout_summary_screen.dart';
import '../features/workout/presentation/session_detail_screen.dart';
import '../features/workout/presentation/routine_detail_screen.dart';
import '../features/workout/presentation/session_player_screen.dart';
import '../features/feed/feed_screen.dart';
import '../features/feed/presentation/create_post_screen.dart';
import '../features/feed/presentation/friend_requests_inbox_screen.dart';
import '../features/profile/application/account_deletion_notifier.dart';
import '../features/feed/presentation/public_profile_screen.dart';
import '../features/feed/presentation/search_users_screen.dart';
import '../features/home/home_screen.dart';
import '../features/insights/presentation/insights_screen.dart';
import '../features/profile/application/user_providers.dart';
import '../features/profile/domain/user_profile_trainer_completeness.dart';
import '../features/profile/domain/user_role.dart';
import '../features/profile/presentation/profile_edit_personal_screen.dart';
import '../features/profile/presentation/profile_edit_trainer_screen.dart';
import '../features/profile/presentation/profile_gym_screen.dart';
import '../features/profile/presentation/profile_routines_screen.dart';
// profile_settings_screen.dart import REMOVED 2026-05-28 — /profile/settings
// route was removed as part of the PR#4 pivot. Settings surface deferred until
// real settings content exists (notifications/theme/language).
import '../features/profile/profile_screen.dart';
import '../features/profile_setup/presentation/profile_setup_flow.dart';
import '../features/workout/workout_screen.dart';
import 'theme/app_background.dart';

const _kTabs = ['/workout', '/feed', '/home', '/coach', '/profile'];

/// Key for the ShellRoute's nested Navigator. We need a handle to it so the
/// bottom bar's onTap can pop popup routes (e.g. agenda day sheets) that
/// were pushed onto the shell nav via `showModalBottomSheet`. Without this
/// key, `Navigator.of(_ShellScaffold.context)` returns the ROOT navigator
/// (because _ShellScaffold sits ABOVE the shell nav in the widget tree), so
/// the modal — which lives on the shell nav — would be unreachable.
final GlobalKey<NavigatorState> _shellNavigatorKey =
    GlobalKey<NavigatorState>(debugLabel: 'ShellNav');

/// Routes that are public (no redirect when anonymous).
const _publicRoutes = {
  '/splash',
  '/welcome',
  '/login',
  '/register',
  '/forgot-password',
};

/// Pure redirect logic — extracted as a top-level function so it is unit-testable
/// without a widget tree (REQ-AUTH-022, REQ-AUTH-023, REQ-AUTH-024).
///
/// [read] is a `Ref.read`-equivalent that returns the current state of any
/// provider. In production this is `ref.read`; in tests it is
/// `container.read`.
String? authRedirect(
    T Function<T>(ProviderListenable<T> provider) read, String location) {
  final auth = read(authNotifierProvider);

  // REQ-AUTH-024: while loading, do not redirect.
  if (auth.isLoading || !auth.hasValue) return null;

  final user = auth.valueOrNull;
  final loggedIn = user != null;
  final isPublic = _publicRoutes.any(location.startsWith);
  final isProfileSetup = location.startsWith('/profile-setup');

  // Anonymous on a protected route → /welcome.
  if (!loggedIn && !isPublic) return '/welcome';

  // Post-signup redirect a /profile-setup. Lee el UserProfile real de
  // Firestore via userProfileProvider — si todavía no tiene displayName,
  // el flow de setup no se completó y mandamos al atleta ahí.
  //
  // El UserProfile lo crea AuthService.signUpWithEmail con displayName=null;
  // el submit de ProfileSetup lo updatea con el username elegido.
  //
  // Mientras el profile está cargando bloqueamos cualquier redirect — el
  // user se queda donde está hasta que sepamos si su profile está completo
  // o no. Esto evita el flicker `/home → /profile-setup` para usuarios
  // recién registrados, y `/profile-setup → /home` para usuarios existentes.
  //
  // Role-awareness (Etapa 7, Option A): el outer 5-tab shell se comparte
  // entre athlete y trainer. No hay rutas trainer-specific en Fase 1, así
  // que tampoco hay redirects por role acá. La diferenciación visual vive
  // en CoachScreen, que despacha a AthleteCoachView o TrainerCoachView
  // según UserProfile.role. Cuando Fase 5 introduzca rutas /trainer/...,
  // el branch va EXACTAMENTE acá — después del gate de profile completo y
  // antes del redirect "/public → /home".
  if (loggedIn && !isProfileSetup) {
    // Account deletion gate: while the CF cascade is in flight, the
    // Firestore profile is deleted BEFORE the Auth user (cascade order).
    // That window opens a 1-2s gap where loggedIn=true + profile=null,
    // which would otherwise redirect mid-flow to /profile-setup before
    // the auth state transitions and lands the user on /welcome. Defer
    // any redirect while the deletion flag is active.
    if (read(accountDeletionInFlightProvider)) return null;

    final profileAsync = read(userProfileProvider);
    if (profileAsync.isLoading) return null;
    final profile = profileAsync.valueOrNull;
    if (profile == null || profile.displayName == null) {
      return '/profile-setup';
    }

    // ADR-TPO-003: trainer-incomplete onboarding gate.
    // Fires AFTER displayName check and BEFORE the public-route → /home redirect.
    // !isPublic guard ensures public routes (login, register, etc.) remain
    // accessible without being redirected to onboarding — logged-in users on
    // public routes are redirected to /home by the existing branch below.
    // Self-skip via startsWith to prevent redirect loops (covers both
    // /profile/edit-trainer and /profile/edit-trainer?mode=onboarding).
    if (!isPublic &&
        profile.role == UserRole.trainer &&
        !profile.trainerProfileComplete &&
        !location.startsWith('/profile/edit-trainer')) {
      return '/profile/edit-trainer?mode=onboarding';
    }
  }

  // Onboarding-complete gate — saca al atleta de /profile-setup una vez que el
  // submit persiste el displayName. El bloque de completitud de arriba se
  // SALTEA cuando isProfileSetup es true, así que sin esta regla no hay ningún
  // camino que abandone el flow de setup: el `context.go('/home')` manual de
  // ProfileSetupFlow corre una carrera contra el stream de userProfileProvider
  // (que todavía emite displayName==null al momento de navegar) y rebota
  // directo de vuelta acá → el usuario queda atrapado en el último step.
  //
  // Manejar la salida desde el dato real del perfil, vía RouterRefreshNotifier
  // (que ya re-dispara este redirect cuando el snapshot del profile llega),
  // elimina la carrera. Para un trainer recién salido del setup, /home reaplica
  // de inmediato el gate trainer-incompleto de arriba → /profile/edit-trainer.
  if (loggedIn && isProfileSetup) {
    final profileAsync = read(userProfileProvider);
    if (!profileAsync.isLoading &&
        profileAsync.valueOrNull?.displayName != null) {
      return '/home';
    }
  }

  // Authenticated on a public route (except /splash) → /home.
  if (loggedIn && isPublic && !location.startsWith('/splash')) return '/home';
  return null;
}

GoRouter buildRouter({
  required Listenable refreshListenable,
  required T Function<T>(ProviderListenable<T>) read,
}) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refreshListenable,
    redirect: (ctx, state) => authRedirect(read, state.matchedLocation),
    routes: [
      // Entry routes — full screen, NO bottom bar
      GoRoute(
        path: '/splash',
        pageBuilder: (_, __) => _noAnim(const SplashScreen()),
      ),
      GoRoute(
        path: '/welcome',
        pageBuilder: (_, __) => _noAnim(const WelcomeScreen()),
      ),
      // Auth routes — full screen, NO bottom bar
      GoRoute(
        path: '/login',
        pageBuilder: (_, __) => _noAnim(const LoginScreen()),
      ),
      GoRoute(
        path: '/register',
        pageBuilder: (_, __) => _noAnim(const RegisterScreen()),
      ),
      GoRoute(
        path: '/forgot-password',
        pageBuilder: (_, __) => _noAnim(const ForgotPasswordScreen()),
      ),

      // ProfileSetup — fullscreen post-signup flow. No bottom bar.
      GoRoute(
        path: '/profile-setup',
        pageBuilder: (_, __) => _noAnim(const ProfileSetupFlow()),
      ),

      // ─── Session player — TOP-LEVEL ROUTES (outside ShellRoute) ───────────
      // El player es immersive: oculta la bottom bar durante el entrenamiento.
      // Diseño §9.1. Las 3 rutas son auth-gated via authRedirect.
      // `builder` (not pageBuilder + _noAnim) so go_router uses the platform
      // default page type (CupertinoPageRoute on iOS → native slide + swipe-back
      // gesture; MaterialPageRoute on Android → back button / edge swipe).
      GoRoute(
        path: '/workout/session/resume/:sessionId',
        builder: (context, state) {
          final sessionId = state.pathParameters['sessionId']!;
          return SessionPlayerScreen(
            init: ResumeSession(sessionId: sessionId),
          );
        },
      ),
      GoRoute(
        path: '/workout/session/:routineId/:dayNumber',
        builder: (context, state) {
          final routineId = state.pathParameters['routineId']!;
          final dayNumber =
              int.tryParse(state.pathParameters['dayNumber'] ?? '') ?? 1;
          // ADR-PB-05: week passed via query param so single-week URLs are
          // identical (?week absent → default 0, backward-compat).
          // Clamp to >= 0: int.tryParse('-1') returns -1, which would persist
          // a negative weekNumber to Firestore and break derivePlanProgress.
          final weekNumber =
              (int.tryParse(state.uri.queryParameters['week'] ?? '') ?? 0)
                  .clamp(0, 1 << 31);
          return SessionPlayerScreen(
            init: FreshSession(
              routineId: routineId,
              dayNumber: dayNumber,
              weekNumber: weekNumber,
            ),
          );
        },
      ),
      GoRoute(
        path: '/workout/session-summary/:sessionId',
        builder: (context, state) {
          final sessionId = state.pathParameters['sessionId']!;
          return PostWorkoutSummaryScreen(sessionId: sessionId);
        },
      ),

      // ─── Historial detail — TOP-LEVEL ROUTE (outside ShellRoute) ──────────
      // Immersive: oculta la bottom bar. Design §11-12.
      GoRoute(
        path: '/workout/historial/:sessionId',
        builder: (context, state) => SessionDetailScreen(
          sessionId: state.pathParameters['sessionId']!,
        ),
      ),

      // ─── Routine editors — TOP-LEVEL ROUTES (outside ShellRoute) ───────────
      // Full-screen creation flow: no bottom nav bar, own Scaffold inside the
      // widget. Moved out of ShellRoute so the editor has the full screen height.
      GoRoute(
        path: '/workout/routine-editor/:athleteId',
        builder: (context, state) {
          final athleteId = state.pathParameters['athleteId']!;
          // `extra` carries an existing plan id when editing; null = create.
          final existingPlanId = state.extra as String?;
          return RoutineEditorScreen(
            mode: TrainerAssigning(
              athleteId: athleteId,
              existingPlanId: existingPlanId,
            ),
          );
        },
      ),
      GoRoute(
        path: '/workout/template-editor',
        builder: (context, state) {
          // `extra` carries an existing template id when editing; null = create.
          final existingTemplateId = state.extra as String?;
          return RoutineEditorScreen(
            mode: TrainerTemplating(existingTemplateId: existingTemplateId),
          );
        },
      ),
      GoRoute(
        path: '/workout/my-routine-editor',
        builder: (context, state) => RoutineEditorScreen(
          mode: SelfCreating(existingRoutineId: state.extra as String?),
        ),
      ),

      // ShellRoute with the existing 5 tabs.
      // Use `pageBuilder` (not `builder`) so the shell itself uses an
      // instant transition when entered from a top-level route like /splash —
      // otherwise the default iOS slide animation runs and the previous
      // screen (splash) is briefly visible behind the home content.
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        pageBuilder: (context, state, child) => _noAnim(
          _ShellScaffold(
            location: state.uri.toString(),
            child: child,
          ),
        ),
        routes: [
          // Tab roots use _noAnim so switching tabs has no slide transition.
          // Sub-routes (pushed screens) use `builder` so go_router picks the
          // platform default page: CupertinoPageRoute on iOS (native slide +
          // interactive-pop gesture), MaterialPageRoute on Android (predictive
          // back / edge swipe). iOS swipe-back cannot be tested via widget tests
          // — it is exercised on device only (see commit message).
          GoRoute(
            path: '/workout',
            pageBuilder: (_, __) => _noAnim(const WorkoutScreen()),
            routes: [
              GoRoute(
                path: 'routine/:routineId',
                builder: (context, state) {
                  final routineId = state.pathParameters['routineId']!;
                  return RoutineDetailScreen(routineId: routineId);
                },
              ),
              GoRoute(
                // `?ownerId=...` is appended by RoutineDetailScreen when
                // the slot's exercise might live in a trainer's
                // customExercises subcollection — see slotExerciseProvider.
                path: 'exercise/:exerciseId',
                builder: (context, state) {
                  final exerciseId = state.pathParameters['exerciseId']!;
                  final ownerId = state.uri.queryParameters['ownerId'];
                  return ExerciseDetailScreen(
                    exerciseId: exerciseId,
                    ownerId: ownerId,
                  );
                },
              ),
              // NOTE: routine-editor, template-editor, my-routine-editor are
              // top-level routes (outside ShellRoute) — see above. Full-screen
              // creation flow with own Scaffold, no bottom nav bar.
            ],
          ),
          GoRoute(
            path: '/feed',
            pageBuilder: (_, __) => _noAnim(const FeedScreen()),
            routes: [
              GoRoute(
                path: 'create',
                builder: (_, __) => const CreatePostScreen(),
              ),
              GoRoute(
                path: 'profile/:uid',
                builder: (context, state) {
                  final uid = state.pathParameters['uid']!;
                  return PublicProfileScreen(targetUid: uid);
                },
              ),
              GoRoute(
                path: 'search',
                builder: (_, __) => const SearchUsersScreen(),
              ),
            ],
          ),
          GoRoute(
            path: '/home',
            pageBuilder: (_, __) => _noAnim(const HomeScreen()),
            routes: [
              GoRoute(
                path: 'insights',
                builder: (_, __) => const InsightsScreen(),
              ),
            ],
          ),
          GoRoute(
            path: '/coach',
            pageBuilder: (context, state) {
              final tab = state.uri.queryParameters['tab'];
              return _noAnim(CoachScreen(initialTab: tab));
            },
            routes: [
              GoRoute(
                path: 'trainer/:uid',
                builder: (context, state) {
                  final uid = state.pathParameters['uid']!;
                  return TrainerPublicProfileScreen(uid: uid);
                },
              ),
              GoRoute(
                path: 'athlete/:athleteId',
                builder: (context, state) {
                  final athleteId = state.pathParameters['athleteId']!;
                  return AthleteDetailScreen(athleteId: athleteId);
                },
              ),
              GoRoute(
                path: 'chat/:chatId',
                builder: (context, state) {
                  final chatId = state.pathParameters['chatId']!;
                  final otherUid = state.uri.queryParameters['other'] ?? '';
                  return ChatScreen(chatId: chatId, otherUid: otherUid);
                },
              ),
              GoRoute(
                path: 'agenda',
                builder: (_, __) => const _AthleteAgendaRouteHost(),
              ),
              GoRoute(
                path: 'availability-editor',
                builder: (context, state) {
                  final uid = state.uri.queryParameters['trainerId'] ?? '';
                  return AvailabilityEditorScreen(trainerId: uid);
                },
              ),
            ],
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (_, __) => _noAnim(const ProfileScreen()),
            routes: [
              // Existing — Fase 3 Etapa 6
              GoRoute(
                path: 'friend-requests',
                builder: (_, __) => const FriendRequestsInboxScreen(),
              ),
              // NEW — Fase 3 Etapa 7 (profile-screen-rewrite)
              GoRoute(
                path: 'edit-personal',
                builder: (_, __) => const ProfileEditPersonalScreen(),
              ),
              // NEW — Fase 6 Etapa 1 (trainer-profile-onboarding)
              // ADR-TPO-005: reads ?mode=onboarding query param; any other
              // value (or missing) defaults to edit mode.
              GoRoute(
                path: 'edit-trainer',
                builder: (context, state) {
                  final mode = state.uri.queryParameters['mode'] == 'onboarding'
                      ? ProfileEditTrainerMode.onboarding
                      : ProfileEditTrainerMode.edit;
                  return ProfileEditTrainerScreen(mode: mode);
                },
              ),
              GoRoute(
                path: 'gym',
                builder: (_, __) => const ProfileGymScreen(),
              ),
              GoRoute(
                path: 'routines',
                builder: (_, __) => const ProfileRoutinesScreen(),
              ),
              // /profile/settings GoRoute REMOVED 2026-05-28 — PR#4 pivot.
              // Sign-out and eliminar-cuenta tiles now live directly in
              // ProfileScreen body. Settings surface deferred to future SDD.
              //
              // /profile/commercial-plans GoRoutes REMOVED 2026-05-28 — the
              // dual pricing model (single trainerMonthlyRate on the public
              // profile + a separate plan catalog) was confusing trainers.
              // Pricing now lives ONLY in the public profile via the EDITAR
              // CTA on the PERFIL PÚBLICO card. A future subscribe flow can
              // reintroduce a multi-tier catalog if needed.

              // Trainer custom exercise library — list + create/edit form.
              GoRoute(
                path: 'my-exercises',
                builder: (_, __) => const MyExercisesScreen(),
                routes: [
                  GoRoute(
                    path: ':exId',
                    builder: (context, state) {
                      final exId = state.pathParameters['exId'];
                      return CustomExerciseEditorScreen(exerciseId: exId);
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

CustomTransitionPage<void> _noAnim(Widget child) => CustomTransitionPage(
      child: child,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      transitionsBuilder: (_, __, ___, child) => child,
    );

/// Resuelve athleteId (currentUid) y trainerId (active link) y monta
/// AthleteAgendaScreen. Loading state mientras se resuelve el link.
class _AthleteAgendaRouteHost extends ConsumerWidget {
  const _AthleteAgendaRouteHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final athleteId = ref.watch(currentUidProvider) ?? '';
    final linkAsync = ref.watch(currentAthleteLinkProvider);

    return linkAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Scaffold(
        body: Center(child: Text('Error: $err')),
      ),
      data: (link) {
        final trainerId = link?.trainerId ?? '';
        if (trainerId.isEmpty || athleteId.isEmpty) {
          return const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Necesitás un vínculo activo con un PF para ver su agenda.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        return AthleteAgendaScreen(
          trainerId: trainerId,
          athleteId: athleteId,
        );
      },
    );
  }
}

class _ShellScaffold extends StatefulWidget {
  const _ShellScaffold({required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  State<_ShellScaffold> createState() => _ShellScaffoldState();
}

class _ShellScaffoldState extends State<_ShellScaffold> {
  int get _currentIndex {
    final i = _kTabs.indexWhere((t) => widget.location.startsWith(t));
    return i < 0 ? 2 : i;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      // bottom: false — the body must reach the physical bottom edge so the
      // main content visibly scrolls BEHIND the floating translucent bar
      // (WhatsApp-style). Scaffold still publishes the bar's height through
      // MediaQuery.padding.bottom, so scrollables without an explicit
      // padding inset their last items above the bar automatically.
      body: AppBackground(
        child: SafeArea(bottom: false, child: widget.child),
      ),
      bottomNavigationBar: TreinoBottomBar(
        currentIndex: _currentIndex,
        onTap: (i) {
          // Pop any open popup (modal bottom sheet, dialog) on the SHELL
          // navigator so it animates closed when the user switches tabs —
          // mirrors the auto-dismiss behavior the user expects from the
          // athlete agenda. We MUST use the shell navigator key here:
          // showModalBottomSheet defaults to useRootNavigator: false, so
          // the modal lives on the shell nav, which is BELOW _ShellScaffold
          // in the tree — unreachable via Navigator.of(context).
          _shellNavigatorKey.currentState
              ?.popUntil((route) => route is! PopupRoute);
          // Defensive: also pop popups on the root navigator (dialogs that
          // explicitly opted into useRootNavigator: true).
          Navigator.of(context, rootNavigator: true)
              .popUntil((route) => route is! PopupRoute);
          context.go(_kTabs[i]);
        },
      ),
    );
  }
}
