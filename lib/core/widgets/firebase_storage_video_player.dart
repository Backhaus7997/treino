import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../app/theme/app_motion.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_theme.dart';
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
///
/// The rendered aspect ratio adapts to the actual video's aspect ratio once
/// the controller reports [VideoPlayerValue.aspectRatio]. Before init and on
/// failure a 16:9 skeleton is shown. [maxHeight] caps the vertical extent so
/// portrait clips (typical for phones) do not push the chat list out of view.
class FirebaseStorageVideoPlayer extends StatefulWidget {
  const FirebaseStorageVideoPlayer({
    super.key,
    required this.url,
    required this.palette,
    this.maxHeight = 400,
  });

  final String url;
  final AppPalette palette;

  /// Hard cap on the rendered height. Portrait videos at their natural
  /// aspect ratio would otherwise take ~2x the width in height and overflow
  /// the chat message list. Set to `double.infinity` to opt out.
  final double maxHeight;

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
    return Theme(
      data: AppTheme.dark(),
      child: _buildContent(palette),
    );
  }

  Widget _buildContent(AppPalette palette) {
    if (_initFailed) {
      return _VideoErrorPlaceholder(palette: palette);
    }

    final c = _controller;
    if (c == null) {
      // Loading skeleton — 16:9 default, capped by [maxHeight] so it does
      // not exceed the same envelope as a wide video. Layout may shift
      // once init completes and the real aspect ratio is known; this is
      // limited to first-render (browser caches the manifest afterwards).
      return _CappedAspectRatio(
        aspectRatio: 16 / 9,
        maxHeight: widget.maxHeight,
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
    // Use the real aspect ratio the controller reports (portrait clips are
    // < 1, landscape > 1). Guarded by _CappedAspectRatio so portrait videos
    // do not overflow the chat list vertically.
    final aspect = c.value.aspectRatio > 0 ? c.value.aspectRatio : 16 / 9;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: _CappedAspectRatio(
        aspectRatio: aspect,
        maxHeight: widget.maxHeight,
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
                duration: AppMotion.fast,
                child: Container(
                    color: Colors.black
                        .withValues(alpha: 0.22)), // intentional: media surface
              ),
              AnimatedOpacity(
                opacity: isPlaying ? 0 : 1,
                duration: AppMotion.fast,
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
                    bufferedColor: Colors.white
                        .withValues(alpha: 0.35), // intentional: media surface
                    backgroundColor: Colors.white
                        .withValues(alpha: 0.15), // intentional: media surface
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
          color: Colors.white
              .withValues(alpha: 0.92), // intentional: media surface
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black
                  .withValues(alpha: 0.35), // intentional: media surface
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
            color: Colors.black, // intentional: media surface
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

/// Aspect-ratio box that respects an outer [maxHeight] cap.
///
/// A raw [AspectRatio] uses the incoming width to derive height (or vice
/// versa) without any cap, so a portrait video (aspect < 1) at a fixed
/// parent width can produce a very tall box (e.g. 320 × 570 for 9:16).
/// This wraps the ratio calc and clamps the resulting height, then centers
/// the ratio-preserved child inside the clamped box. Landscape videos are
/// unaffected because they naturally produce a short-height box.
class _CappedAspectRatio extends StatelessWidget {
  const _CappedAspectRatio({
    required this.aspectRatio,
    required this.maxHeight,
    required this.child,
  });

  final double aspectRatio;
  final double maxHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Prefer the tightest available width; if unbounded, fall back to a
        // sane default so the layout still resolves.
        final width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 320.0;
        final naturalHeight = width / aspectRatio;
        final height = naturalHeight > maxHeight ? maxHeight : naturalHeight;
        // Recompute width from the clamped height to keep the aspect ratio
        // — the child is centered within the parent's width so cropping
        // does not occur.
        final adjustedWidth = height * aspectRatio;
        return SizedBox(
          width: width,
          height: height,
          child: Center(
            child: SizedBox(
              width: adjustedWidth,
              height: height,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
