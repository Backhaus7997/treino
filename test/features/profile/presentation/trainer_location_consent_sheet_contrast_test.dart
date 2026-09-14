// Contraste del botón ACEPTAR del sheet de consentimiento de ubicación.
//
// POR QUÉ ESTE ARCHIVO EXISTE, y por qué no alcanzaba con el test que ya había:
//
// `trainer_location_consent_sheet_test.dart` monta el sheet con
// `AppTheme.dark()`. En dark el defecto NO se manifiesta: `palette.bg` es casi
// negro y sobre el mint da contraste de sobra. El bug vive sólo en claro, donde
// `palette.bg` es `paper50` y sobre el mint mide 1,57:1. Una suite entera en
// verde sobre un botón ilegible.
//
// Y no es hipotético: `5d3b82b4 fix(ui): usar ink invariante como foreground
// sobre accent (166 sitios) (#767)` corrigió exactamente este anti-patrón el
// 2026-08-24. Este sheet nació el 2026-09-03 y lo reintrodujo — diez días
// después, sin que nada se pusiera rojo.
//
// Tampoco alcanza un test de tokens puros (`superset_block_contrast_test.dart`
// y compañía): esos miden pares de colores. Acá el bug es que un WIDGET no
// setea `foregroundColor`, así que el par de colores nunca llega a formarse en
// el código — lo elige Flutter. Hay que pumpear el widget y preguntarle qué
// quedó.
//
// AGENTS.md, regla 2: todo par de tokens donde `accent` sea FONDO se mide en
// LAS DOS paletas.
import 'dart:math' as math;

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/features/profile/domain/user_profile.dart';
import 'package:treino/features/profile/domain/user_role.dart';
import 'package:treino/features/profile/presentation/trainer_location_consent_sheet.dart';
import 'package:treino/l10n/app_l10n.dart';

const _uid = 'trainer-contraste-1';
const _kAccept = Key('trainer_location_consent_accept_button');

/// Mínimo WCAG AA para texto chico.
const double _kTextAA = 4.5;

/// Ratio de contraste WCAG 2.x entre dos colores OPACOS.
double _ratio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

Future<void> _seedTrainer(FakeFirebaseFirestore firestore) async {
  final now = DateTime.utc(2026, 1, 1);
  await firestore.collection('users').doc(_uid).set(
        UserProfile(
          uid: _uid,
          email: 'pf@test.com',
          displayName: 'Coach',
          role: UserRole.trainer,
          createdAt: now,
          updatedAt: now,
        ).toJson(),
      );
}

Widget _host(FakeFirebaseFirestore firestore, ThemeData theme) {
  return ProviderScope(
    overrides: [firestoreProvider.overrideWithValue(firestore)],
    child: MaterialApp(
      theme: theme,
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isDismissible: false,
                enableDrag: true,
                builder: (_) => const TrainerLocationConsentSheet(uid: _uid),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

/// El color que REALMENTE termina en el framebuffer para el label y el relleno
/// del botón. Si el widget no declara el suyo, Flutter resuelve por el tema —
/// y eso es justo lo que este archivo existe para medir, así que el fallback
/// va acá adentro en vez de ser un `expect(isNotNull)` que no dice nada del
/// pixel.
({Color fg, Color bg}) _coloresEfectivos(WidgetTester tester) {
  final button = tester.widget<ElevatedButton>(find.byKey(_kAccept));
  final scheme = Theme.of(tester.element(find.byKey(_kAccept))).colorScheme;
  const estados = <WidgetState>{};
  return (
    fg: button.style?.foregroundColor?.resolve(estados) ?? scheme.onPrimary,
    bg: button.style?.backgroundColor?.resolve(estados) ?? scheme.primary,
  );
}

void main() {
  // `AppTheme.dark()` / `.light()` se construyen en el header del `for` de
  // abajo, o sea ANTES de que corra el primer test. Los dos pasan por
  // `GoogleFonts.barlowTextTheme()`, que carga el asset manifest y necesita el
  // binding vivo. Sin esta línea el archivo ni siquiera llega a cargar.
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeFirebaseFirestore firestore;

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    await _seedTrainer(firestore);
  });

  for (final (nombre, theme, palette) in <(String, ThemeData, AppPalette)>[
    ('dark', AppTheme.dark(), AppPalette.mintMagenta),
    ('light', AppTheme.light(), AppPalette.mintMagentaLight),
  ]) {
    testWidgets('$nombre: el label de ACEPTAR cumple AA sobre el relleno',
        (tester) async {
      await tester.pumpWidget(_host(firestore, theme));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final c = _coloresEfectivos(tester);
      expect(
        _ratio(c.fg, c.bg),
        greaterThanOrEqualTo(_kTextAA),
        reason:
            'El label de ACEPTAR mide ${_ratio(c.fg, c.bg).toStringAsFixed(2)}:1 '
            'sobre su propio relleno en el tema $nombre. Si esto se puso rojo, '
            'lo más probable es que alguien haya sacado el `foregroundColor: '
            'TreinoButtonTokens.foreground(context)` del ElevatedButton y el '
            'botón haya vuelto a heredar `ColorScheme.onPrimary`.',
      );
    });

    // CONTROL NEGATIVO. Sin esto, el test de arriba pasaría igual si el
    // default del tema resultara aceptable — y no probaría que el override
    // sostiene algo. En claro este expect es el bug exacto de #767; en dark
    // documenta por qué el harness viejo no lo veía.
    test('$nombre: el default del tema sobre accent mide lo que mide', () {
      final ratio = _ratio(palette.bg, palette.accent);
      if (nombre == 'light') {
        expect(
          ratio,
          lessThan(_kTextAA),
          reason: 'Si esto se puso rojo, la paleta clara cambió y `palette.bg` '
              'sobre `accent` ya cumple AA. Sería una buena noticia — pero '
              'revisá el override del botón antes de borrarlo: el argumento '
              'para tenerlo era justamente este número.',
        );
      } else {
        expect(
          ratio,
          greaterThanOrEqualTo(_kTextAA),
          reason: 'En dark el default SÍ alcanza. Por eso un harness que sólo '
              'monta en dark da verde sobre un botón ilegible en claro.',
        );
      }
    });
  }
}
