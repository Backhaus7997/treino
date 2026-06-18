import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/firebase_storage_video_player.dart';
import '../../../../core/widgets/treino_icon.dart';

/// Tappable card for an exercise's tutorial video. Dual-mode:
///
///   * Firebase Storage URL (`firebasestorage.googleapis.com`) → renders a
///     native [VideoPlayer] inline with play/pause controls.
///   * YouTube URL → renders the YouTube thumbnail with a subtle play
///     overlay; tap opens youtube.com in a Safari View Controller (iOS) or
///     Chrome Custom Tab (Android) via `url_launcher`'s `inAppBrowserView`
///     mode. The user never leaves TREINO — the browser is a modal sheet.
///   * Null / empty / unparseable URL → renders the empty-state placeholder.
///
/// Why YouTube isn't embedded inline: every Flutter WebView option we tried
/// hit YouTube's server-side embed rejection on iOS WKWebView (errors
/// 152 / 153). Native uploads are the path forward for true in-app
/// playback.
class ExerciseVideoPlayer extends StatelessWidget {
  const ExerciseVideoPlayer({super.key, required this.videoUrl});

  final String? videoUrl;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final url = videoUrl?.trim() ?? '';

    if (url.isEmpty) {
      return _VideoPlaceholder(palette: palette, urlGiven: null);
    }

    if (isFirebaseStorageVideo(url)) {
      return FirebaseStorageVideoPlayer(url: url, palette: palette);
    }

    final id = parseYoutubeVideoId(url);
    if (id != null) {
      return _YoutubeThumbCard(videoId: id, palette: palette);
    }

    return _VideoPlaceholder(palette: palette, urlGiven: url);
  }
}

/// YouTube thumbnail card. Tap → opens the watch page in an in-app browser
/// sheet via `url_launcher`. We don't try to embed inline anymore.
class _YoutubeThumbCard extends StatelessWidget {
  const _YoutubeThumbCard({required this.videoId, required this.palette});

  final String videoId;
  final AppPalette palette;

  Future<void> _open(BuildContext context) async {
    final uri = Uri.parse('https://www.youtube.com/watch?v=$videoId');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (!ok && context.mounted) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No pudimos abrir el video.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Material(
          color: palette.bgCard,
          child: InkWell(
            onTap: () => _open(context),
            child: Stack(
              alignment: Alignment.center,
              fit: StackFit.expand,
              children: [
                CachedNetworkImage(
                  imageUrl: 'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
                  fit: BoxFit.cover,
                  placeholder: (context, _) => Container(color: palette.bgCard),
                  errorWidget: (context, _, __) =>
                      Container(color: palette.bgCard),
                ),
                Container(color: Colors.black.withValues(alpha: 0.22)),
                const _PlayOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Subtle, brand-neutral play overlay reused by every video card. Sits
/// 40×40 in the middle with a soft drop shadow — no big black puck.
class _PlayOverlay extends StatelessWidget {
  const _PlayOverlay();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: const Padding(
          // Optical centering — play triangles read offset-left without it.
          padding: EdgeInsets.only(left: 3),
          child: Icon(
            TreinoIcon.play,
            color: Colors.black,
            size: 20,
          ),
        ),
      ),
    );
  }
}

/// Empty-state shown when no playable URL is available.
class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder({required this.palette, required this.urlGiven});

  final AppPalette palette;
  final String? urlGiven;

  @override
  Widget build(BuildContext context) {
    final isBadUrl = urlGiven != null && urlGiven!.trim().isNotEmpty;
    final label = isBadUrl
        ? 'No pudimos leer el video.'
        : 'Próximamente — el entrenador puede agregar un video.';
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border, width: 1),
        ),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(TreinoIcon.play, size: 28, color: palette.textMuted),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w400,
                  fontSize: 13,
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── URL helpers ─────────────────────────────────────────────────────────────

/// True for Firebase Storage download URLs.
/// Shape: `https://firebasestorage.googleapis.com/v0/b/{bucket}/o/{path}?...`
bool isFirebaseStorageVideo(String? raw) {
  if (raw == null) return false;
  final url = raw.trim();
  if (url.isEmpty) return false;
  Uri? uri;
  try {
    uri = Uri.parse(url);
  } catch (_) {
    return false;
  }
  return uri.host.toLowerCase() == 'firebasestorage.googleapis.com';
}

/// Extracts the storage object path from a Firebase Storage download URL,
/// or `null` if [url] is not such a URL. Used to delete the underlying
/// object when a custom exercise is removed.
String? extractFirebaseStoragePath(String? raw) {
  if (raw == null) return null;
  final url = raw.trim();
  if (url.isEmpty) return null;
  Uri? uri;
  try {
    uri = Uri.parse(url);
  } catch (_) {
    return null;
  }
  if (uri.host.toLowerCase() != 'firebasestorage.googleapis.com') return null;
  final segs = uri.pathSegments;
  final oIdx = segs.indexOf('o');
  if (oIdx == -1 || oIdx + 1 >= segs.length) return null;
  return Uri.decodeComponent(segs[oIdx + 1]);
}

/// Extracts the 11-char YouTube video id from a URL, or `null` if the URL
/// can't be parsed.
///
/// Top-level + `@visibleForTesting` shape so unit tests can pin URL parsing
/// without spinning up the player.
String? parseYoutubeVideoId(String? raw) {
  if (raw == null) return null;
  final url = raw.trim();
  if (url.isEmpty) return null;

  // Bare 11-char ID (e.g. user pasted just the id).
  if (RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(url)) return url;

  Uri? uri;
  try {
    uri = Uri.parse(url);
  } catch (_) {
    return null;
  }
  final host = uri.host.toLowerCase().replaceFirst('www.', '');

  // youtu.be/ID
  if (host == 'youtu.be' && uri.pathSegments.isNotEmpty) {
    return _ifValidId(uri.pathSegments.first);
  }

  // youtube.com/watch?v=ID
  if ((host == 'youtube.com' || host == 'm.youtube.com') &&
      uri.path == '/watch') {
    return _ifValidId(uri.queryParameters['v']);
  }

  // youtube.com/shorts/ID or /embed/ID
  if (host == 'youtube.com' || host == 'm.youtube.com') {
    final segs = uri.pathSegments;
    if (segs.length >= 2 && (segs.first == 'shorts' || segs.first == 'embed')) {
      return _ifValidId(segs[1]);
    }
  }

  return null;
}

String? _ifValidId(String? candidate) {
  if (candidate == null) return null;
  return RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(candidate) ? candidate : null;
}
