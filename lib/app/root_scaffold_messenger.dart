import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Root [ScaffoldMessengerState] key, shared app-wide.
///
/// [TreinoApp] lo instala en `MaterialApp.router(scaffoldMessengerKey:)`, así
/// cualquier código de la capa de providers puede mostrar un SnackBar que
/// sobrevive pops de navegación sin necesitar un BuildContext montado — el
/// patrón de los push foreground (ADR-PN-010), reutilizado por
/// [ChatMediaSendController] (issue #435): cuando un adjunto falla, el usuario
/// puede haber salido del chat hace rato.
///
/// En unit tests sin [MaterialApp] montado `currentState` es null: los
/// callers deben tratarlo como no-op.
final rootScaffoldMessengerKeyProvider =
    Provider<GlobalKey<ScaffoldMessengerState>>(
  (_) => GlobalKey<ScaffoldMessengerState>(),
);
