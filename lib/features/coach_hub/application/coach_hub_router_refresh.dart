import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../profile/application/user_providers.dart';

/// Ping que avisa al router del Hub cuando cambia el pendiente de escrituras
/// de `users/{uid}`.
///
/// El gate de onboarding del Hub (`done && !pendiente`) lee
/// `userProfileHasPendingWritesProvider` dentro del redirect, pero un redirect
/// solo se re-evalua cuando su `refreshListenable` notifica. Sin este ping, el
/// ack del servidor (pendiente `true` -> `false`) cambia el provider y nadie
/// avisa al router: el PF queda en la pantalla hasta tocar algo.
///
/// Vive aca y no en `RouterRefreshNotifier` a proposito: ese notifier lo
/// comparte el router de mobile (`app.dart`) y su conteo de notificaciones
/// esta pineado por tests. El Hub lo envuelve con `Listenable.merge`.
///
/// Como el de `RouterRefreshNotifier`, dedupea dentro del mismo frame con
/// `scheduleMicrotask`.
class _PendingWritesPing extends ChangeNotifier {
  _PendingWritesPing(Ref ref) {
    _sub = ref.listen<AsyncValue<bool>>(
      userProfileHasPendingWritesProvider,
      (prev, next) => _scheduleNotify(),
      fireImmediately: false,
    );
  }

  late final ProviderSubscription<AsyncValue<bool>> _sub;
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
    _sub.close();
    super.dispose();
  }
}

/// `refreshListenable` del router del Coach Hub: el refresh compartido
/// (auth, perfil, email gate) mas el ping del pendiente de escrituras.
final coachHubRouterRefreshProvider = Provider<Listenable>((ref) {
  final ping = _PendingWritesPing(ref);
  ref.onDispose(ping.dispose);
  return Listenable.merge([
    ref.watch(routerRefreshNotifierProvider),
    ping,
  ]);
});
