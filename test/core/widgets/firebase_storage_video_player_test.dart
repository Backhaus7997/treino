// Tests for FirebaseStorageVideoPlayer's loading treatment (#545).
//
// While the controller initialises (multi-second on cold Storage URLs) the
// slot must read unmistakably as "loading" — shimmer sweep + accent spinner —
// instead of a near-black card that QA reported as a broken video.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/firebase_storage_video_player.dart';
import 'package:treino/core/widgets/motion/treino_shimmer.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('shows shimmer skeleton + accent spinner while initialising',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const FirebaseStorageVideoPlayer(
          url: 'https://firebasestorage.googleapis.com/vid.mp4',
          palette: AppPalette.mintMagenta,
        ),
      ),
    );
    // Controller init never completes in the test environment (no platform
    // channel), which conveniently freezes the widget in its loading state.
    expect(find.byType(TreinoShimmer), findsOneWidget);

    final spinner = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(spinner.color, AppPalette.mintMagenta.accent);
  });
}
