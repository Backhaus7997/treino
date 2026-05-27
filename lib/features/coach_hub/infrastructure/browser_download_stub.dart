import 'dart:typed_data';

/// Stub para plataformas non-web. El Coach Hub es web-only por diseño —
/// si esto se llama en VM/mobile es un bug.
void triggerBrowserDownload({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) {
  throw UnsupportedError(
    'triggerBrowserDownload is only available on Flutter Web.',
  );
}
