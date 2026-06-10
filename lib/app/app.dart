import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_providers.dart';
import '../features/notifications/application/notification_providers.dart';
import '../features/notifications/application/notification_router.dart';
import '../l10n/app_l10n.dart';
import 'locale_resolver.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class TreinoApp extends ConsumerStatefulWidget {
  const TreinoApp({super.key});

  @override
  ConsumerState<TreinoApp> createState() => _TreinoAppState();
}

class _TreinoAppState extends ConsumerState<TreinoApp> {
  late final GoRouter _router;

  /// Root ScaffoldMessenger key used by the foreground SnackBar handler.
  /// Passed to [MaterialApp.router] so the SnackBar can be shown from
  /// [_onForeground] without needing a BuildContext. (ADR-PN-010)
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  /// Foreground message subscription — cancelled on dispose.
  StreamSubscription<RemoteMessage>? _fgSub;

  @override
  void initState() {
    super.initState();
    final refresh = ref.read(routerRefreshNotifierProvider);
    _router = buildRouter(refreshListenable: refresh, read: ref.read);

    // (c) Eagerly read fcmLifecycleProvider to register the auth-state listener
    //     for the app lifetime. Without this, all of PR#2a is dead code —
    //     no tokens are ever registered. ADR-PN-003, REQ-PN-CLIENT-004.
    ref.read(fcmLifecycleProvider);

    // (a) Attach foreground SnackBar listener. (ADR-PN-010, REQ-PN-HANDLER-001)
    final fcm = ref.read(fcmServiceProvider);
    _fgSub = fcm.onForegroundMessage.listen(_onForeground);

    // (b) Cold-start gate: wait for router to be ready before navigating.
    //     addPostFrameCallback guarantees GoRouter is fully mounted.
    //     ADR-PN-011, REQ-PN-HANDLER-003, SCENARIO-657, 658.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final message = await fcm.getInitialMessage();
      if (message == null) return;
      final ctx = _router.routerDelegate.navigatorKey.currentContext;
      if (ctx == null || !ctx.mounted) return;
      goDeepLink(ctx, message.data['deepLink'] as String?);
    });
  }

  @override
  void dispose() {
    _fgSub?.cancel();
    super.dispose();
  }

  /// Foreground message handler — shows SnackBar via root ScaffoldMessenger.
  /// ADR-PN-010, REQ-PN-HANDLER-001, SCENARIO-652, 653, 654.
  void _onForeground(RemoteMessage message) {
    final messenger = _scaffoldMessengerKey.currentState;
    if (messenger == null) return;

    final title = message.notification?.title ?? '';
    final body = message.notification?.body ?? '';
    final deepLink = message.data['deepLink'] as String?;

    // Capture context from the navigator so goDeepLink has GoRouter access.
    final ctx = _router.routerDelegate.navigatorKey.currentContext;

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
            if (ctx == null || !ctx.mounted) return;
            goDeepLink(ctx, deepLink);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'TREINO',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: _router,
      // i18n — ADR-I18N-004, ADR-I18N-005
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      localeResolutionCallback: (locale, supported) =>
          resolveLocale(locale ?? const Locale('es', 'AR'), supported),
      // Root ScaffoldMessenger key for foreground push SnackBars. (ADR-PN-010)
      scaffoldMessengerKey: _scaffoldMessengerKey,
      // Global: tap anywhere outside an input dismisses the keyboard.
      // translucent so buttons/scroll still win the tap; only empty-area
      // taps reach this and unfocus the current field.
      builder: (context, child) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child,
      ),
    );
  }
}
