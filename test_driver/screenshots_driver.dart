// Host-side driver for integration_test/screenshots_test.dart.
//
// The test running on the device hands each screenshot back to the host through
// this callback, which is the only place with filesystem access. Written PNGs
// land in build/store-screenshots/ and are collected by
// store/capture_screenshots.sh.

import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

const _outDir = 'build/store-screenshots';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (
      String name,
      List<int> bytes, [
      Map<String, Object?>? args,
    ]) async {
      final dir = Directory(_outDir)..createSync(recursive: true);
      final file = File('${dir.path}/$name.png')..writeAsBytesSync(bytes);
      stdout.writeln('WROTE ${file.path} (${bytes.length} bytes)');
      return true;
    },
  );
}
