import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../application/notification_router.dart';
import '../data/fcm_service.dart';

/// Invisible widget that attaches the foreground message SnackBar listener.
///
/// Must be placed inside a [Scaffold] so [ScaffoldMessenger.of] can resolve.
/// Uses [scaffoldMessengerKey] to show SnackBars from outside the widget tree
/// (e.g. from [TreinoApp.initState]) — ADR-PN-010.
///
/// REQ-PN-HANDLER-001, SCENARIO-652, 653, 654, ADR-PN-010.
class ForegroundSnackBarHandler extends StatefulWidget {
  const ForegroundSnackBarHandler({
    super.key,
    required this.scaffoldMessengerKey,
    required this.fcmService,
  });

  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey;
  final FcmService fcmService;

  @override
  State<ForegroundSnackBarHandler> createState() =>
      _ForegroundSnackBarHandlerState();
}

class _ForegroundSnackBarHandlerState extends State<ForegroundSnackBarHandler> {
  StreamSubscription<RemoteMessage>? _fgSub;

  /// Holds the most-recent build context so SnackBar action can call goDeepLink.
  /// Updated every build so it stays current even after hot-reload / rebuilds.
  BuildContext? _routerContext;

  @override
  void initState() {
    super.initState();
    _fgSub = widget.fcmService.onForegroundMessage.listen(_onForeground);
  }

  @override
  void dispose() {
    _fgSub?.cancel();
    _routerContext = null;
    super.dispose();
  }

  void _onForeground(RemoteMessage message) {
    final messenger = widget.scaffoldMessengerKey.currentState;
    if (messenger == null) return;

    final title = message.notification?.title ?? '';
    final body = message.notification?.body ?? '';
    final deepLink = message.data['deepLink'] as String?;

    // Capture a navigator context reachable from inside the SnackBar action.
    // We use the widget's own build context (set in _routerContext via didChangeDependencies)
    // which is inside InheritedGoRouter and has access to the router.
    final routerCtx = _routerContext;

    messenger.showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title.isNotEmpty)
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            if (body.isNotEmpty) Text(body),
          ],
        ),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Ver', // i18n: Fase 6 Etapa 2
          onPressed: () {
            // ADR-PN-010: check mounted before calling go to avoid
            // navigating on a dead tree.
            if (routerCtx == null) return;
            goDeepLink(routerCtx, deepLink);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _routerContext = context;
    return const SizedBox.shrink();
  }
}
