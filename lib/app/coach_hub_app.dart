import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/application/auth_providers.dart';
import '../l10n/app_l10n.dart';
import 'coach_hub_router.dart';
import 'locale_resolver.dart';
import 'theme/app_theme.dart';

/// Root widget del TREINO Coach Hub (web).
///
/// Equivalente del `TreinoApp` mobile pero con su propio router (sin
/// bottom bar, sin tabs mobile, solo flows del Coach Hub).
class CoachHubApp extends ConsumerStatefulWidget {
  const CoachHubApp({super.key});

  @override
  ConsumerState<CoachHubApp> createState() => _CoachHubAppState();
}

class _CoachHubAppState extends ConsumerState<CoachHubApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    final refresh = ref.read(routerRefreshNotifierProvider);
    _router = buildCoachHubRouter(refreshListenable: refresh, read: ref.read);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'TREINO Coach Hub',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: _router,
      // l10n: mismos delegates/locales que TreinoApp (app.dart). Sin esto, los
      // widgets que usan AppL10n.of(context) (p. ej. PerformanceProgressChart)
      // crashean en el Coach Hub.
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      localeResolutionCallback: (locale, supported) =>
          resolveLocale(locale ?? const Locale('es', 'AR'), supported),
      // Global: tap outside an input dismisses the keyboard (see TreinoApp).
      builder: (context, child) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child,
      ),
    );
  }
}
