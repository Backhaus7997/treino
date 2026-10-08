// Tests for FirebaseStorageVideoPlayer's loading treatment (#545).
//
// While the controller initialises (multi-second on cold Storage URLs) the
// slot must read unmistakably as "loading" — shimmer sweep + accent spinner —
// instead of a near-black card that QA reported as a broken video.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/firebase_storage_video_player.dart';
import 'package:treino/core/widgets/motion/treino_shimmer.dart';
import 'package:video_player/video_player.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('shows shimmer skeleton + accent spinner while initialising',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        const FirebaseStorageVideoPlayer(
          url: 'https://firebasestorage.googleapis.com/vid.mp4',
          palette: AppPalette.mintMagenta,
        ),
      ),
    );
    // Controller init never completes in the test environment (no platform
    // channel), which conveniently freezes the widget in its loading state.
    expect(find.byType(TreinoShimmer), findsOneWidget);

    final spinner = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(spinner.color, AppPalette.mintMagenta.accent);
  });

  // ---------------------------------------------------------------------------
  // Tap-to-load (#chat-video-egress)
  // ---------------------------------------------------------------------------
  //
  // `initialize()` sale a la red desde `initState`, o sea CADA VEZ que el
  // widget se construye. Adentro de un `ListView.builder` eso es cada vez que
  // el video entra al viewport, y otra vez cuando volvés a scrollear — es un
  // `State` nuevo. En una lista de mensajes eso descarga videos que nadie pidió
  // ver, a USD 0,12/GB de egress sin CDN, y de paso con los datos móviles del
  // usuario.
  //
  // Estos tests cuidan las TRES cosas que hacen que el ahorro sea real:
  // que sin tap no se pinte el estado de "cargando" (porque no hay nada
  // cargando), que el tap sí lo dispare, y que el default siga siendo el de
  // antes para las cinco superficies que muestran un solo video.

  group('autoInicializar — la descarga', () {
    // Lo que de verdad importa del cambio: que NO salga el pedido. Los tests
    // de abajo miran lo que se PINTA, y eso no alcanza — una mutacion que
    // sacaba la llamada a _init() del tap los dejaba a todos en verde, porque
    // sin platform channel "cargando" y "no pidio nada" se ven igual.
    //
    // Por eso el widget acepta un `inicializador` inyectable.

    testWidgets('con autoInicializar en false NO se pide nada al montar',
        (tester) async {
      final pedidos = <Uri>[];
      await tester.pumpWidget(
        _wrap(
          FirebaseStorageVideoPlayer(
            url: 'https://firebasestorage.googleapis.com/vid.mp4',
            palette: AppPalette.mintMagenta,
            autoInicializar: false,
            inicializador: (u) async {
              pedidos.add(u);
              throw StateError('no deberia llamarse');
            },
          ),
        ),
      );
      await tester.pump();

      expect(pedidos, isEmpty);
    });

    testWidgets('el tap pide UNA vez, y dos taps no piden dos veces',
        (tester) async {
      final pedidos = <Uri>[];
      await tester.pumpWidget(
        _wrap(
          FirebaseStorageVideoPlayer(
            url: 'https://firebasestorage.googleapis.com/vid.mp4',
            palette: AppPalette.mintMagenta,
            autoInicializar: false,
            inicializador: (u) async {
              pedidos.add(u);
              // Nunca completa: congela el widget en "cargando", igual que
              // una URL fria de verdad.
              return Completer<VideoPlayerController>().future;
            },
          ),
        ),
      );

      await tester.tap(find.byType(VideoPlayOverlay));
      await tester.pump();
      expect(pedidos, hasLength(1));

      // El afford ya no esta, pero por las dudas: un segundo pedido seria
      // una segunda descarga del mismo video.
      await tester.tap(find.byType(TreinoShimmer), warnIfMissed: false);
      await tester.pump();
      expect(pedidos, hasLength(1));
    });

    testWidgets('con el default SI se pide al montar', (tester) async {
      final pedidos = <Uri>[];
      await tester.pumpWidget(
        _wrap(
          FirebaseStorageVideoPlayer(
            url: 'https://firebasestorage.googleapis.com/vid.mp4',
            palette: AppPalette.mintMagenta,
            inicializador: (u) async {
              pedidos.add(u);
              return Completer<VideoPlayerController>().future;
            },
          ),
        ),
      );
      await tester.pump();

      expect(pedidos, hasLength(1));
    });
  });

  group('autoInicializar', () {
    testWidgets('en false muestra el afford de play y NO el shimmer',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const FirebaseStorageVideoPlayer(
            url: 'https://firebasestorage.googleapis.com/vid.mp4',
            palette: AppPalette.mintMagenta,
            autoInicializar: false,
          ),
        ),
      );

      expect(find.byType(VideoPlayOverlay), findsOneWidget);
      // El shimmer mentiría: no hay ninguna descarga en curso.
      expect(find.byType(TreinoShimmer), findsNothing);
    });

    testWidgets('el tap dispara la carga y ahí sí aparece el shimmer',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const FirebaseStorageVideoPlayer(
            url: 'https://firebasestorage.googleapis.com/vid.mp4',
            palette: AppPalette.mintMagenta,
            autoInicializar: false,
          ),
        ),
      );

      await tester.tap(find.byType(VideoPlayOverlay));
      await tester.pump();

      // Sin platform channel el init nunca completa, lo que deja al widget
      // congelado justo en el estado que queremos observar.
      expect(find.byType(TreinoShimmer), findsOneWidget);
      expect(find.byType(VideoPlayOverlay), findsNothing);
    });

    testWidgets('el default sigue inicializando solo', (tester) async {
      // El contrapeso: las cinco superficies que ya usaban este widget
      // muestran UN video en una pantalla a la que se llegó a propósito.
      // Meterles un tap de más no ahorraría nada.
      await tester.pumpWidget(
        _wrap(
          const FirebaseStorageVideoPlayer(
            url: 'https://firebasestorage.googleapis.com/vid.mp4',
            palette: AppPalette.mintMagenta,
          ),
        ),
      );

      expect(find.byType(TreinoShimmer), findsOneWidget);
      expect(find.byType(VideoPlayOverlay), findsNothing);
    });
  });
}
