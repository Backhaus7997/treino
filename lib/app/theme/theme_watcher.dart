import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps its [child] with an [AnnotatedRegion] that keeps the system UI
/// overlay style (status-bar icon brightness) in sync with the active theme.
///
/// Place this directly around the `MaterialApp.router` builder child so it
/// sits inside the active [Theme] but above the rest of the widget tree
/// (REQ-LM-005, SCENARIO-814, SCENARIO-815, SCENARIO-816).
///
/// On web the [AnnotatedRegion] is a no-op (there is no native status bar),
/// so [child] is returned unchanged to avoid unnecessary wrapping.
class ThemeWatcher extends StatelessWidget {
  const ThemeWatcher({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return child;

    final brightness = Theme.of(context).brightness;

    // Dark theme → light icons on the status bar; light theme → dark icons.
    final overlayStyle = brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: child,
    );
  }
}
