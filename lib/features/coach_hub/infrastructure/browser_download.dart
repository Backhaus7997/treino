import 'dart:typed_data';

import 'browser_download_stub.dart'
    if (dart.library.js_interop) 'browser_download_web.dart' as impl;

/// Dispara una descarga de archivo en el browser usando un Blob + anchor.
///
/// La implementación real vive en `browser_download_web.dart` y usa
/// `package:web`. Para builds non-web (VM, mobile) se usa el stub que
/// solo lanza UnsupportedError — el hub es web-only por diseño.
///
/// El conditional import (`if (dart.library.js_interop)`) hace que el
/// analyzer NO siga la rama web en compilación VM y permite que los
/// tests Flutter normales sigan corriendo.
void triggerBrowserDownload({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
}) {
  impl.triggerBrowserDownload(
    bytes: bytes,
    filename: filename,
    mimeType: mimeType,
  );
}
