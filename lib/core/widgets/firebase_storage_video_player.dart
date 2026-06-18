import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../app/theme/app_palette.dart';
import 'treino_icon.dart';

/// Public, reusable native video player for Firebase Storage download URLs.
///
/// Lifted verbatim from `_NativeVideoCard` in
/// `lib/features/workout/presentation/widgets/exercise_video_player.dart`
/// so the chat feature can use the same player without importing workout code
/// (REQ-CHATMEDIA-009 / Phase 6).
///
/// Initialises a [VideoPlayerController.networkUrl] lazily and disposes it
/// when [url] changes or the widget is removed.
class FirebaseStorageVideoPlayer extends StatefulWidget {
  const FirebaseStorageVideoPlayer({
    super.key,
    required this.url,
    required this.palette,
  });

  final String url;
  final AppPalette palette;

  @override
  State<FirebaseStorageVideoPlayer> createState() =>
      _FirebaseStorageVideoPlayerState();
}

class _FirebaseStorageVideoPlayerState
    extends State<FirebaseStorageVideoPlayer> {
  VideoPlayerController? _controller;
  bool _initFailed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(covariant FirebaseStorageVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _controller?.dispose();
      _controller = null;
      _initFailed = false;
      _init();
    }
  }

  Future<void> _init() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _controller = c);
    } catch (_) {
      await c.dispose();
      if (!mounted) return;
      setState(() => _initFailed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _toggle() {
    final c = _controller;
    if (c == null) return;
    setState(() {
      c.value.isPlaying ? c.pause() : c.play();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;

    if (_initFailed) {
      return _VideoErrorPlaceholder(palette: palette);
    }

    final c = _controller;
    if (c == null) {
      // Loading skeleton.
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            color: palette.bgCard,
            alignment: Alignment.center,
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: palette.textMuted,
              ),
            ),
          ),
        ),
      );
    }

    final isPlaying = c.value.isPlaying;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: GestureDetector(
          onTap: _toggle,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            alignment: Alignment.center,
            fit: StackFit.expand,
            children: [
              FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: c.value.size.width,
                  height: c.value.size.height,
                  child: VideoPlayer(c),
                ),
              ),
              AnimatedOpacity(
                opacity: isPlaying ? 0 : 1,
                duration: const Duration(milliseconds: 180),
                child: Container(color: Colors.black.withValues(alpha: 0.22)),
              ),
              AnimatedOpacity(
                opacity: isPlaying ? 0 : 1,
                duration: const Duration(milliseconds: 180),
                child: const _PlayOverlay(),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: VideoProgressIndicator(
                  c,
                  allowScrubbing: true,
                  colors: VideoProgressColors(
                    playedColor: palette.accent,
                    bufferedColor: Colors.white.withValues(alpha: 0.35),
                    backgroundColor: Colors.white.withValues(alpha: 0.15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Private helpers ──────────────────────────────────────────────────────────

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

class _VideoErrorPlaceholder extends StatelessWidget {
  const _VideoErrorPlaceholder({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.border, width: 1),
        ),
        alignment: Alignment.center,
        child: Icon(TreinoIcon.play, size: 28, color: palette.textMuted),
      ),
    );
  }
}
