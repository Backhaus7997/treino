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
import '../features/coach/presentation/commercial_plan_editor_screen.dart';
import '../features/coach/presentation/commercial_plans_list_screen.dart';
import '../features/coach/presentation/trainer_public_profile_screen.dart';
import '../features/workout/application/session_providers.dart'
    show currentUidProvider;
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
import '../features/feed/presentation/public_profile_screen.dart';
import '../features/feed/presentation/search_users_screen.dart';
import '../features/home/home_screen.dart';
import '../features/insights/presentation/insights_screen.dart';
import '../features/profile/application/user_providers.dart';
import '../features/profile/presentation/profile_edit_personal_screen.dart';
import '../features/profile/presentation/profile_gym_screen.dart';
import '../features/profile/presentation/profile_routines_screen.dart';
import '../features/profile/presentation/profile_settings_screen.dart';
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
    final profileAsync = read(userProfileProvider);
    if (profileAsync.isLoading) return null;
    final profile = profileAsync.valueOrNull;
    if (profile == null || profile.displayName == null) {
      return '/profile-setup';
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
      GoRoute(
        path: '/workout/session/resume/:sessionId',
        pageBuilder: (context, state) {
          final sessionId = state.pathParameters['sessionId']!;
          return _noAnim(SessionPlayerScreen(
            init: ResumeSession(sessionId: sessionId),
          ));
        },
      ),
      GoRoute(
        path: '/workout/session/:routineId/:dayNumber',
        pageBuilder: (context, state) {
          final routineId = state.pathParameters['routineId']!;
          final dayNumber =
              int.tryParse(state.pathParameters['dayNumber'] ?? '') ?? 1;
          return _noAnim(SessionPlayerScreen(
            init: FreshSession(routineId: routineId, dayNumber: dayNumber),
          ));
        },
      ),
      GoRoute(
        path: '/workout/session-summary/:sessionId',
        pageBuilder: (context, state) {
          final sessionId = state.pathParameters['sessionId']!;
          return _noAnim(PostWorkoutSummaryScreen(sessionId: sessionId));
        },
      ),

      // ─── Historial detail — TOP-LEVEL ROUTE (outside ShellRoute) ──────────
      // Immersive: oculta la bottom bar. Design §11-12.
      GoRoute(
        path: '/workout/historial/:sessionId',
        pageBuilder: (context, state) => _noAnim(
          SessionDetailScreen(
            sessionId: state.pathParameters['sessionId']!,
          ),
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
          GoRoute(
            path: '/workout',
            pageBuilder: (_, __) => _noAnim(const WorkoutScreen()),
            routes: [
              GoRoute(
                path: 'routine/:routineId',
                pageBuilder: (context, state) {
                  final routineId = state.pathParameters['routineId']!;
                  return _noAnim(RoutineDetailScreen(routineId: routineId));
                },
              ),
              GoRoute(
                path: 'exercise/:exerciseId',
                pageBuilder: (context, state) {
                  final exerciseId = state.pathParameters['exerciseId']!;
                  return _noAnim(ExerciseDetailScreen(exerciseId: exerciseId));
                },
              ),
              GoRoute(
                path: 'routine-editor/:athleteId',
                pageBuilder: (context, state) {
                  final athleteId = state.pathParameters['athleteId']!;
                  return _noAnim(RoutineEditorScreen(athleteId: athleteId));
                },
              ),
            ],
          ),
          GoRoute(
            path: '/feed',
            pageBuilder: (_, __) => _noAnim(const FeedScreen()),
            routes: [
              GoRoute(
                path: 'create',
                pageBuilder: (_, __) => _noAnim(const CreatePostScreen()),
              ),
              GoRoute(
                path: 'profile/:uid',
                pageBuilder: (context, state) {
                  final uid = state.pathParameters['uid']!;
                  return _noAnim(PublicProfileScreen(targetUid: uid));
                },
              ),
              GoRoute(
                path: 'search',
                pageBuilder: (_, __) => _noAnim(const SearchUsersScreen()),
              ),
            ],
          ),
          GoRoute(
            path: '/home',
            pageBuilder: (_, __) => _noAnim(const HomeScreen()),
            routes: [
              GoRoute(
                path: 'insights',
                pageBuilder: (_, __) => _noAnim(const InsightsScreen()),
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
                pageBuilder: (context, state) {
                  final uid = state.pathParameters['uid']!;
                  return _noAnim(TrainerPublicProfileScreen(uid: uid));
                },
              ),
              GoRoute(
                path: 'athlete/:athleteId',
                pageBuilder: (context, state) {
                  final athleteId = state.pathParameters['athleteId']!;
                  return _noAnim(AthleteDetailScreen(athleteId: athleteId));
                },
              ),
              GoRoute(
                path: 'chat/:chatId',
                pageBuilder: (context, state) {
                  final chatId = state.pathParameters['chatId']!;
                  final otherUid = state.uri.queryParameters['other'] ?? '';
                  return _noAnim(
                    ChatScreen(chatId: chatId, otherUid: otherUid),
                  );
                },
              ),
              GoRoute(
                path: 'agenda',
                pageBuilder: (_, __) =>
                    _noAnim(const _AthleteAgendaRouteHost()),
              ),
              GoRoute(
                path: 'availability-editor',
                pageBuilder: (context, state) {
                  final uid = state.uri.queryParameters['trainerId'] ?? '';
                  return _noAnim(AvailabilityEditorScreen(trainerId: uid));
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
                pageBuilder: (_, __) =>
                    _noAnim(const FriendRequestsInboxScreen()),
              ),
              // NEW — Fase 3 Etapa 7 (profile-screen-rewrite)
              GoRoute(
                path: 'edit-personal',
                pageBuilder: (_, __) =>
                    _noAnim(const ProfileEditPersonalScreen()),
              ),
              GoRoute(
                path: 'gym',
                pageBuilder: (_, __) => _noAnim(const ProfileGymScreen()),
              ),
              GoRoute(
                path: 'routines',
                pageBuilder: (_, __) => _noAnim(const ProfileRoutinesScreen()),
              ),
              GoRoute(
                path: 'settings',
                pageBuilder: (_, __) => _noAnim(const ProfileSettingsScreen()),
              ),
              // Trainer commercial plans (Fase 6) — list + create/edit form.
              GoRoute(
                path: 'commercial-plans',
                pageBuilder: (_, __) =>
                    _noAnim(const CommercialPlansListScreen()),
                routes: [
                  GoRoute(
                    path: ':planId',
                    pageBuilder: (context, state) {
                      final planId = state.pathParameters['planId'];
                      return _noAnim(
                        CommercialPlanEditorScreen(planId: planId),
                      );
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

class _ShellScaffold extends StatelessWidget {
  const _ShellScaffold({required this.location, required this.child});

  final String location;
  final Widget child;

  int get _currentIndex {
    final i = _kTabs.indexWhere((t) => location.startsWith(t));
    return i < 0 ? 2 : i;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppBackground(child: SafeArea(child: child)),
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
