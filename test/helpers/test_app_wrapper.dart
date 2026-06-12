import 'package:flutter/material.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/l10n/app_l10n.dart';

/// Wraps [child] in a minimal [MaterialApp] with the TREINO dark theme.
/// Use this in widget tests that need AppPalette.of(context) to resolve.
class TestAppWrapper extends StatelessWidget {
  const TestAppWrapper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: child),
    );
  }
}
