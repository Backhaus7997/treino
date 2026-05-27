import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_providers.dart';
import '../features/coach_hub/presentation/coach_hub_dashboard_screen.dart';
import '../features/coach_hub/presentation/coach_hub_login_screen.dart';
import '../features/coach_hub/presentation/coach_hub_not_allowed_screen.dart';
import '../features/coach_hub/presentation/coach_hub_plan_preview_screen.dart';
import '../features/coach_hub/presentation/coach_hub_upload_plan_screen.dart';
import '../features/profile/application/user_providers.dart';
import '../features/profile/domain/user_role.dart';

/// Rutas públicas del Coach Hub (no requieren auth).
const _coachHubPublicRoutes = {'/login'};

/// Lógica de redirect pura del Coach Hub — testeable como función standalone.
///
/// Diferencias clave vs `authRedirect` mobile:
/// 1. NO hay `/welcome`, `/register`, `/forgot-password`, `/splash` — el hub
///    es solo para PFs ya registrados desde mobile (signup vive en mobile).
/// 2. **Role gating**: usuarios con `role != trainer` se redirigen a
///    `/not-allowed`. Athletes que entran por accidente ven una info page.
/// 3. NO hay flow de profile-setup — si el PF llegó al hub es porque ya
///    tiene profile completo desde mobile.
String? coachHubRedirect(
  T Function<T>(ProviderListenable<T> provider) read,
  String location,
) {
  final auth = read(authNotifierProvider);

  // Mientras carga auth no redirigimos — evita flicker.
  if (auth.isLoading || !auth.hasValue) return null;

  final user = auth.valueOrNull;
  final loggedIn = user != null;
  final isPublic = _coachHubPublicRoutes.any(location.startsWith);
  final isNotAllowed = location.startsWith('/not-allowed');

  // Anonymous → /login (override de cualquier path protegido)
  if (!loggedIn && !isPublic) return '/login';

  // Authenticated en /login → resolver según role
  // (el switch entre dashboard / not-allowed pasa por el role check abajo)
  if (loggedIn && isPublic) {
    // Caemos al role check below — no return null acá porque queremos
    // resolver el role gate antes de mandar al dashboard.
  }

  // Authenticated → role gating
  if (loggedIn) {
    final profileAsync = read(userProfileProvider);
    if (profileAsync.isLoading) return null;
    final profile = profileAsync.valueOrNull;

    // Sin profile (caso edge: user borrado de Firestore manualmente, o
    // signup raro): tratar como no-allowed defensive.
    if (profile == null) {
      return isNotAllowed ? null : '/not-allowed';
    }

    if (profile.role != UserRole.trainer) {
      // Athletes (o cualquier role distinto a trainer) → /not-allowed
      return isNotAllowed ? null : '/not-allowed';
    }

    // Trainer autenticado → si está en /login o /not-allowed, mandalo
    // al dashboard. Si ya está en alguna ruta protegida, dejalo.
    if (isPublic || isNotAllowed) return '/dashboard';
  }

  return null;
}

/// Build del GoRouter del Coach Hub.
///
/// Mucho más chico que el router mobile — solo 3 rutas: login, dashboard,
/// not-allowed. Sin ShellRoute, sin bottom bar.
GoRouter buildCoachHubRouter({
  required Listenable refreshListenable,
  required T Function<T>(ProviderListenable<T>) read,
}) {
  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: refreshListenable,
    redirect: (ctx, state) => coachHubRedirect(read, state.matchedLocation),
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, __) => const CoachHubLoginScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (_, __) => const CoachHubDashboardScreen(),
      ),
      GoRoute(
        path: '/upload-plan',
        builder: (_, __) => const CoachHubUploadPlanScreen(),
      ),
      GoRoute(
        path: '/upload-plan/preview',
        builder: (_, __) => const CoachHubPlanPreviewScreen(),
      ),
      GoRoute(
        path: '/not-allowed',
        builder: (_, __) => const CoachHubNotAllowedScreen(),
      ),
    ],
  );
}
