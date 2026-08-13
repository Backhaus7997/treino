import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';

/// Wrapper compartido para los `@Preview` del kit Coach Hub Web — Fase 1
/// (Finding W3). Provee `MaterialApp` + tema dark + padding, requisito de
/// `AppPalette.of(context)` y del resto de tokens del kit.
Widget coachHubPreviewWrapper(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: child,
          ),
        ),
      ),
    );
