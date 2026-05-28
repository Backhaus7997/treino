import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';

/// Embedded YouTube player for an exercise's tutorial video.
///
/// Plays inline inside the app — never kicks the user out to the YouTube app
/// or website. Handles three states:
///   - [videoUrl] is null/empty → renders [_VideoPlaceholder] ("sin video").
///   - [videoUrl] is not a parseable YouTube URL → renders [_VideoPlaceholder]
///     with an explanatory note so a bad URL doesn't crash the screen.
///   - [videoUrl] resolves to a valid video id → renders the inline player
///     with native controls and a 16:9 aspect ratio.
///
/// Accepts the full YouTube URL forms commonly pasted by trainers:
///   - https://www.youtube.com/watch?v=ID
///   - https://youtu.be/ID
///   - https://youtube.com/shorts/ID
///   - https://www.youtube.com/embed/ID
class ExerciseVideoPlayer extends StatefulWidget {
  const ExerciseVideoPlayer({super.key, required this.videoUrl});

  final String? videoUrl;

  @override
  State<ExerciseVideoPlayer> createState() => _ExerciseVideoPlayerState();
}

class _ExerciseVideoPlayerState extends State<ExerciseVideoPlayer> {
  YoutubePlayerController? _controller;
  String? _resolvedVideoId;

  @override
  void initState() {
    super.initState();
    _resolveAndInit(widget.videoUrl);
  }

  @override
  void didUpdateWidget(covariant ExerciseVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _controller?.close();
      _controller = null;
      _resolveAndInit(widget.videoUrl);
    }
  }

  void _resolveAndInit(String? url) {
    final id = parseYoutubeVideoId(url);
    setState(() => _resolvedVideoId = id);
    if (id != null) {
      _controller = YoutubePlayerController.fromVideoId(
        videoId: id,
        autoPlay: false,
        params: const YoutubePlayerParams(
          showControls: true,
          showFullscreenButton: true,
          enableCaption: false,
          strictRelatedVideos: true,
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (_resolvedVideoId == null || _controller == null) {
      return _VideoPlaceholder(palette: palette, urlGiven: widget.videoUrl);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: YoutubePlayer(controller: _controller!),
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
