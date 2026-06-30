import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_l10n.dart';

/// Fullscreen viewer for a chat image bubble. Wraps [CachedNetworkImage] in
/// an [InteractiveViewer] so the user can pinch-zoom the photo.
class PhotoViewerScreen extends StatelessWidget {
  const PhotoViewerScreen({super.key, required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Text(
          l10n.chatMediaViewFullscreen,
          style: const TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5.0,
          child: CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.contain,
            placeholder: (context, _) => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
            errorWidget: (context, _, __) => Center(
              child: Text(
                l10n.chatMediaImageLoadError,
                style: const TextStyle(color: Colors.white54),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
