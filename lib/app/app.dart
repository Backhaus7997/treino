import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme/app_theme.dart';

class TreinoApp extends ConsumerStatefulWidget {
  const TreinoApp({super.key});

  @override
  ConsumerState<TreinoApp> createState() => _TreinoAppState();
}

class _TreinoAppState extends ConsumerState<TreinoApp> {
  late final _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'TREINO',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: _router,
    );
  }
}
