import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:video_player/video_player.dart';

import '../../app/theme/app_motion.dart';
import '../../app/theme/app_palette.dart';
import '../../app/theme/app_theme.dart';
import 'motion/treino_shimmer.dart';
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
    this.autoInicializar = true,
    @visibleForTesting this.inicializador,
  });

  /// Cómo se crea e inicializa el controller. Inyectable SÓLO para tests.
  ///
  /// Existe porque sin esto **el punto entero de [autoInicializar] no se puede
  /// testear**. Un widget test puede ver que cambia lo que se pinta, pero no
  /// que haya salido —o no— un pedido a la red: `VideoPlayerController` habla
  /// por platform channel, que en tests no contesta nunca, así que «cargando»
  /// y «no pidió nada» se ven igual.
  ///
  /// Lo descubrió una mutación: sacando la llamada a `_init()` del tap y
  /// dejando sólo el `setState`, los tests seguían TODOS en verde. Estaban
  /// mirando el shimmer, no la descarga.
  ///
  /// Con la costura, el test afirma lo que importa de verdad: que sin tap la
  /// función NO se llama ni una vez.
  final Future<VideoPlayerController> Function(Uri url)? inicializador;

  final String url;
  final AppPalette palette;

  /// Si el controller se crea solo al montar, o recién cuando el usuario toca.
  ///
  /// ## Por qué existe: el egress es la línea cara
  ///
  /// `initialize()` sale a la red. Con `true`, ese pedido ocurre en
  /// `initState`, o sea **cada vez que el widget se construye** — y adentro de
  /// un `ListView.builder` eso es cada vez que el video entra al viewport.
  /// Scrolleás para atrás y vuelve a salir, porque es un `State` nuevo.
  ///
  /// En una pantalla de detalle eso está perfecto: el usuario navegó hasta ahí
  /// a propósito. En una LISTA DE MENSAJES no: scrollear una conversación
  /// dispara una descarga por cada video que pasa, sin que nadie pida ver
  /// ninguno.
  ///
  /// Y el egress es el eje caro del storage: USD 0,12/GB contra USD
  /// 0,026/GB-mes de guardarlo — 4,6x, y sin CDN adelante porque la URL
  /// `?alt=media&token=` de `getDownloadURL()` es GCS directo
  /// (`docs/costos-storage.md` §2). Encima esos bytes también se los gasta el
  /// usuario, de sus datos móviles, en videos que no pidió.
  ///
  /// ## Por qué el default sigue en `true`
  ///
  /// Porque las cinco superficies que ya lo usaban muestran UN video en una
  /// pantalla a la que se llegó a propósito. Cambiarles el comportamiento
  /// sería meter un tap de más sin ahorrar nada. Los que lo apagan son los
  /// bubbles de chat, que son los únicos que viven en una lista.
  ///
  /// ## Qué se ve con `false`
  ///
  /// El mismo envelope, con el [VideoPlayOverlay] encima: un afford de play.
  /// No hay poster del primer frame, y no puede haberlo — sacarlo exigiría
  /// bajar el video, que es justo lo que esto evita. `Message` tampoco guarda
  /// un thumbnail.
  ///
  /// El tap carga **y reproduce**: sería hostil pedir dos taps para ver un
  /// video.
  final bool autoInicializar;

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

  /// True entre el pedido de carga y el primer frame.
  ///
  /// Distingue los dos estados que con [FirebaseStorageVideoPlayer
  /// .autoInicializar] en `false` se ven iguales si no se los separa:
  /// «todavía no pidió nada» (afford de play) y «está cargando» (shimmer).
  bool _cargando = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoInicializar) _init();
  }

  @override
  void didUpdateWidget(covariant FirebaseStorageVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _controller?.dispose();
      _controller = null;
      _initFailed = false;
      _cargando = false;
      if (widget.autoInicializar) _init();
    }
  }

  /// Lo que dispara el tap sobre el afford de play.
  ///
  /// Idempotente a propósito: dos taps rápidos sobre el placeholder no crean
  /// dos controllers —ni dos descargas— para el mismo video.
  void _pedirCarga() {
    if (_cargando || _controller != null) return;
    setState(() => _cargando = true);
    _init(reproducirAlTerminar: true);
  }

  /// El camino real: crea el controller y lo inicializa contra la red.
  ///
  /// La limpieza del fallo vive ACÁ y no en el `catch` de `_init` porque el
  /// controller se crea acá: quien lo crea es quien sabe que hay algo que
  /// liberar. Sin esto, un init fallido deja el controller colgado.
  static Future<VideoPlayerController> _inicializarDeVerdad(Uri url) async {
    final c = VideoPlayerController.networkUrl(url);
    try {
      await c.initialize();
    } catch (_) {
      await c.dispose();
      rethrow;
    }
    return c;
  }

  Future<void> _init({bool reproducirAlTerminar = false}) async {
    _cargando = true;
    final crear = widget.inicializador ?? _inicializarDeVerdad;
    final VideoPlayerController c;
    try {
      c = await crear(Uri.parse(widget.url));
      if (!mounted) {
        await c.dispose();
        return;
      }
      // Antes del `setState` para que el primer frame ya se pinte andando: el
      // usuario tocó PLAY, no «cargar».
      if (reproducirAlTerminar) unawaited(c.play());
      setState(() {
        _controller = c;
        _cargando = false;
      });
    } catch (_) {
      // No se libera nada acá: si `crear` falló, el controller o no llegó a
      // existir o ya se limpió solo. Antes este `catch` hacía `c.dispose()`
      // porque el controller se creaba afuera del `try`; con la creación
      // adentro, `c` puede no estar asignado y ni siquiera compila.
      if (!mounted) return;
      setState(() {
        _initFailed = true;
        _cargando = false;
      });
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

    // Todavía no se pidió nada: el afford de play, y CERO bytes.
    //
    // Va antes del skeleton porque son estados distintos y se veían iguales:
    // un shimmer acá mentiría —no hay nada cargando— y el usuario esperaría
    // un video que nunca va a empezar solo.
    if (c == null && !widget.autoInicializar && !_cargando) {
      return _CappedAspectRatio(
        aspectRatio: 16 / 9,
        maxHeight: widget.maxHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: GestureDetector(
            onTap: _pedirCarga,
            behavior: HitTestBehavior.opaque,
            child: Container(
              color: palette.bgCard,
              alignment: Alignment.center,
              child: const VideoPlayOverlay(),
            ),
          ),
        ),
      );
    }

    if (c == null) {
      // Loading skeleton — 16:9 default, capped by [maxHeight] so it does
      // not exceed the same envelope as a wide video. Layout may shift
      // once init completes and the real aspect ratio is known; this is
      // limited to first-render (browser caches the manifest afterwards).
      //
      // Cold Storage URLs take multi-second inits, and `bgCard` reads as
      // plain black in a video slot — a muted 22px spinner got missed and the
      // state was reported as "broken video" (#545). Shimmer sweep + accent
      // spinner make "loading" unmistakable at a glance.
      return _CappedAspectRatio(
        aspectRatio: 16 / 9,
        maxHeight: widget.maxHeight,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: TreinoShimmer(
            child: Container(
              color: palette.bgCard,
              alignment: Alignment.center,
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.6,
                  color: palette.accent,
                ),
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
      borderRadius: BorderRadius.circular(AppRadius.sm),
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
                duration: AppMotion.resolve(context, AppMotion.fast),
                child: Container(
                    color: Colors.black
                        .withValues(alpha: 0.22)), // intentional: media surface
              ),
              AnimatedOpacity(
                opacity: isPlaying ? 0 : 1,
                duration: AppMotion.resolve(context, AppMotion.fast),
                child: const VideoPlayOverlay(),
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

/// Subtle, brand-neutral play affordance shared by every video surface —
/// 44px white circle with a soft drop shadow, no big black puck. Public so
/// the feature-side video cards (exercise_video_player.dart) and the
/// exercise-detail video hero reuse the exact same overlay instead of
/// keeping per-file copies.
class VideoPlayOverlay extends StatelessWidget {
  const VideoPlayOverlay({super.key});

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

// ─── Private helpers ──────────────────────────────────────────────────────────

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
          borderRadius: BorderRadius.circular(AppRadius.sm),
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
