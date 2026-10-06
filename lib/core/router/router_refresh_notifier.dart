import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_providers.dart';
import '../../features/auth/application/email_gate_providers.dart';
import '../../features/profile/application/user_providers.dart';
import '../../features/profile/domain/user_profile.dart';

/// Listenable que dispara el redirect del go_router cuando cambia cualquiera
/// de los cuatro providers que el redirect lee:
///
/// - `authStateChangesProvider` — sign in / sign out.
/// - `userProfileProvider` — el UserProfile pasa de loading → loaded, o se
///   actualiza (ej. después de completar ProfileSetup, displayName deja de
///   ser null). Sin este segundo listener, el redirect post-signup no se
///   re-evalúa cuando el snapshot del profile llega → user queda atrapado
///   en /home hasta que toca algo manualmente.
/// - `emailGateEnabledProvider` — el interruptor `app_config/email_gate`. Sin
///   este listener, prender o apagar el gate desde la consola no se notaría
///   hasta el próximo cambio de auth o de profile.
/// - `userProfileHasPendingWritesProvider` — el gate de edad (`/birth-date`)
///   y el onboarding del Hub salen solo cuando la escritura de `users/{uid}`
///   está confirmada por el servidor. El ack cambia únicamente la metadata del
///   snapshot: `userProfileProvider` NO re-emite (no escucha metadata), así que
///   sin este listener el redirect no se re-evalúa y el usuario queda trabado
///   en la pantalla (#1335).
///
/// Las notificaciones se deduplican dentro del mismo frame con
/// `scheduleMicrotask` — si auth y profile cambian "simultáneamente"
/// (típico durante sign-out, cuando userProfileProvider se reconstruye al
/// auth state cambiar), go_router recibe un solo refresh en vez de dos
/// consecutivos. Eso evita race conditions al transicionar entre
/// ShellRoute y rutas fullscreen.
class RouterRefreshNotifier extends ChangeNotifier {
  RouterRefreshNotifier(Ref ref) {
    _authSub = ref.listen<AsyncValue<User?>>(
      authStateChangesProvider,
      (prev, next) => _scheduleNotify(),
      fireImmediately: false,
    );
    _profileSub = ref.listen<AsyncValue<UserProfile?>>(
      userProfileProvider,
      (prev, next) => _scheduleNotify(),
      fireImmediately: false,
    );
    _emailGateSub = ref.listen<AsyncValue<bool>>(
      emailGateEnabledProvider,
      (prev, next) => _scheduleNotify(),
      fireImmediately: false,
    );
    _pendingWritesSub = ref.listen<AsyncValue<bool>>(
      userProfileHasPendingWritesProvider,
      (prev, next) => _scheduleNotify(),
      fireImmediately: false,
    );
  }

  late final ProviderSubscription<AsyncValue<User?>> _authSub;
  late final ProviderSubscription<AsyncValue<UserProfile?>> _profileSub;
  late final ProviderSubscription<AsyncValue<bool>> _emailGateSub;
  late final ProviderSubscription<AsyncValue<bool>> _pendingWritesSub;

  bool _scheduled = false;
  bool _disposed = false;

  void _scheduleNotify() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (_disposed) return;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _authSub.close();
    _profileSub.close();
    _emailGateSub.close();
    _pendingWritesSub.close();
    super.dispose();
  }
}
