import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';
import '../../l10n/app_l10n.dart';

/// Visor de una foto a pantalla completa: [CachedNetworkImage] adentro de un
/// [InteractiveViewer] para pinch-zoom, sobre fondo negro.
///
/// Vive en `core/widgets/` y no en una feature porque lo usan dos canales
/// distintos —la foto del chat y la que el alumno adjunta en un reporte
/// (#628)— y el §1 del plan del PF suma un tercero cuando el reporte acepte
/// video. Su gemelo, [FirebaseStorageVideoPlayer], ya estaba acá; que el de
/// foto siguiera en `features/chat/presentation/` era la asimetría, no el
/// diseño.
///
/// **Sus bounds son propios, no los del thumbnail que lo abre.** El caller
/// pinta miniaturas con `memCacheWidth/Height` chicos (AGENTS.md regla 6);
/// acá la foto se muestra entera, así que esos límites NO se heredan — si se
/// heredaran, ampliar mostraría la versión pixelada.
///
/// El `errorWidget` no es decorativo: la URL lleva el token adentro y vive
/// dentro del documento, así que un 403 es esperable —el objeto puede haberse
/// borrado por el cascade de cuenta mientras el doc sigue en caché local. El
/// visor tiene que tratarlo tan bien como el thumbnail, con un cartel y no con
/// una excepción.
class PhotoViewerScreen extends StatelessWidget {
  const PhotoViewerScreen({super.key, required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Theme(
      data: AppTheme.dark(),
      child: Scaffold(
        backgroundColor: Colors.black, // intentional: media surface
        appBar: AppBar(
          backgroundColor: Colors.black, // intentional: media surface
          elevation: 0,
          title: Text(
            l10n.chatMediaViewFullscreen,
            style: const TextStyle(
                color: Colors.white), // intentional: media surface
          ),
          iconTheme: const IconThemeData(
              color: Colors.white), // intentional: media surface
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.contain,
              placeholder: (context, _) => const Center(
                child: CircularProgressIndicator(
                    color: Colors.white), // intentional: media surface
              ),
              errorWidget: (context, _, __) => Center(
                child: Text(
                  l10n.chatMediaImageLoadError,
                  style: const TextStyle(
                      color: Colors.white54), // intentional: media surface
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
