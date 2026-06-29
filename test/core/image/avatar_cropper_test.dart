import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/image/avatar_cropper.dart';
import 'package:treino/l10n/app_l10n.dart';

class _MockImageCropper extends Mock implements ImageCropper {}

class _FakePlatformUiSettings extends Fake implements PlatformUiSettings {}

void main() {
  setUpAll(() {
    registerFallbackValue('placeholder-path');
    registerFallbackValue(ImageCompressFormat.jpg);
    registerFallbackValue(<PlatformUiSettings>[_FakePlatformUiSettings()]);
  });

  group('AvatarCropper.cropToSquare', () {
    /// Pumps a tiny harness whose only purpose is to expose a real
    /// [BuildContext] under [AppL10n] + [AppTheme]. The cropper helper needs
    /// both to build its UI settings.
    Future<BuildContext> pumpContext(WidgetTester tester) async {
      late BuildContext capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          home: Builder(
            builder: (ctx) {
              capturedContext = ctx;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return capturedContext;
    }

    testWidgets('returns the cropped path when the user confirms the crop UI',
        (tester) async {
      final mock = _MockImageCropper();
      when(() => mock.cropImage(
            sourcePath: any(named: 'sourcePath'),
            compressFormat: any(named: 'compressFormat'),
            compressQuality: any(named: 'compressQuality'),
            uiSettings: any(named: 'uiSettings'),
          )).thenAnswer((_) async => CroppedFile('/tmp/cropped.jpg'));

      final ctx = await pumpContext(tester);
      final result = await AvatarCropper(cropper: mock).cropToSquare(
        sourcePath: '/tmp/source.jpg',
        context: ctx,
      );

      expect(result, '/tmp/cropped.jpg');
    });

    testWidgets('returns null when the user cancels the crop UI',
        (tester) async {
      final mock = _MockImageCropper();
      when(() => mock.cropImage(
            sourcePath: any(named: 'sourcePath'),
            compressFormat: any(named: 'compressFormat'),
            compressQuality: any(named: 'compressQuality'),
            uiSettings: any(named: 'uiSettings'),
          )).thenAnswer((_) async => null);

      final ctx = await pumpContext(tester);
      final result = await AvatarCropper(cropper: mock).cropToSquare(
        sourcePath: '/tmp/source.jpg',
        context: ctx,
      );

      expect(result, isNull);
    });

    testWidgets(
        'forwards the sourcePath verbatim and emits 1:1-locked UI settings '
        'on the 3 platforms (iOS / Android / Web)', (tester) async {
      final mock = _MockImageCropper();
      when(() => mock.cropImage(
            sourcePath: any(named: 'sourcePath'),
            compressFormat: any(named: 'compressFormat'),
            compressQuality: any(named: 'compressQuality'),
            uiSettings: any(named: 'uiSettings'),
          )).thenAnswer((_) async => CroppedFile('/tmp/cropped.jpg'));

      final ctx = await pumpContext(tester);
      await AvatarCropper(cropper: mock).cropToSquare(
        sourcePath: '/tmp/source.jpg',
        context: ctx,
      );

      final captured = verify(() => mock.cropImage(
            sourcePath: captureAny(named: 'sourcePath'),
            compressFormat: captureAny(named: 'compressFormat'),
            compressQuality: captureAny(named: 'compressQuality'),
            uiSettings: captureAny(named: 'uiSettings'),
          )).captured;

      expect(captured[0], '/tmp/source.jpg');
      expect(captured[1], ImageCompressFormat.jpg);
      expect(captured[2], 85);

      final uiSettings = captured[3] as List<PlatformUiSettings>;
      // The helper MUST emit settings for all 3 platforms — otherwise the
      // wrong platform falls back to a free-ratio UI and breaks the circular
      // preview contract.
      expect(uiSettings.whereType<AndroidUiSettings>(), hasLength(1));
      expect(uiSettings.whereType<IOSUiSettings>(), hasLength(1));
      expect(uiSettings.whereType<WebUiSettings>(), hasLength(1));
    });
  });
}
