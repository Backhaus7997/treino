import 'package:flutter/material.dart';
import 'package:treino/app/theme/app_theme.dart';

/// Wraps [child] in a minimal [MaterialApp] with the TREINO dark theme.
/// Use this in widget tests that need AppPalette.of(context) to resolve.
class TestAppWrapper extends StatelessWidget {
  const TestAppWrapper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );
  }
}
