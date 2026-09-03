// #830 — el hueco al final del scroll, medido contra la barra REAL.
//
// Las dos pantallas de este archivo rearmaban a mano el alto de la
// `TreinoBottomBar` y se lo sumaban a un `MediaQuery.padding.bottom` que ya lo
// traía entero. El síntoma es cosmético —sobra hueco, no se tapa nada—, y eso
// hace muy fácil escribir un test que no prueba nada: leer del widget el mismo
// `padding.bottom + minHeight` que escribió la pantalla pasa siempre, y encima
// pasa en un harness donde no hay barra y `padding.bottom` vale 0. Ese test
// existía (`post sliver preserves shell-safe bottom padding`) y por eso el bug
// vivió sin que nadie lo viera.
//
// Acá se mide otra cosa: con la pantalla montada en un shell de verdad —con
// `Scaffold` real, `extendBody: true` y una `TreinoBottomBar` real en el slot
// `bottomNavigationBar`— se scrollea hasta el fondo y se mide la distancia
// EFECTIVA entre el último pedazo de contenido y el borde inferior del
// viewport. Esa distancia se compara contra la caja que la barra ocupa de
// verdad, tomada con `getRect` del árbol renderizado. Ningún número está
// escrito a mano y ninguno se recalcula copiando la expresión de producción:
// si mañana la barra cambia de alto, el test sigue midiendo lo mismo.
//
// Contra el código viejo estos tests fallan por 72 y 88pt de más (medido:
// gap 166 contra una barra de 94, y gap 202 contra una de 114). El techo de
// la aserción deja 24pt de tolerancia sobre la caja de la barra —ver
// [_designGapCeiling]—, así que fallan por 48 y 64, no al filo.
//
// El shell se replica en vez de montarse: `_ShellScaffold` es privado de
// `app/router.dart` y arrancar el router de verdad arrastra auth, perfil y
// Firestore para medir geometría. Lo que importa del shell son las tres
// piezas que producen el inset, y están replicadas al pie de la letra desde
// `router.dart:1169-1181`: `extendBody: true`, el body envuelto en
// `SafeArea(bottom: false)` y la barra en `bottomNavigationBar`.

import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_bottom_bar.dart';
import 'package:treino/features/auth/application/auth_providers.dart';
import 'package:treino/features/feed/application/feed_screen_providers.dart';
import 'package:treino/features/feed/application/post_providers.dart';
import 'package:treino/features/feed/application/public_profile_providers.dart';
import 'package:treino/features/feed/domain/feed_segment.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/feed/domain/public_profile_view.dart';
import 'package:treino/features/feed/feed_screen.dart';
import 'package:treino/features/feed/presentation/public_profile_screen.dart';
import 'package:treino/features/feed/presentation/widgets/post_card.dart';
import 'package:treino/features/profile/application/user_providers.dart'
    show firestoreProvider;
import 'package:treino/l10n/app_l10n.dart';

class _MockUser extends Mock implements User {}

User _userWithUid(String uid) {
  final u = _MockUser();
  when(() => u.uid).thenReturn(uid);
  return u;
}

class _StubPublicProfileViewNotifier extends PublicProfileViewNotifier {
  _StubPublicProfileViewNotifier(this._value);
  final PublicProfileView _value;

  @override
  Future<PublicProfileView> build(String arg) async => _value;
}

/// Réplica literal del shell (`router.dart:1169-1181`). Las tres piezas que
/// importan son las que arma el inset: `extendBody`, el `SafeArea(bottom:
/// false)` —que a propósito NO consume `padding.bottom`— y la barra en su
/// slot.
Widget _shell(Widget child, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('es', 'AR'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(
          extendBody: true,
          body: SafeArea(bottom: false, child: child),
          bottomNavigationBar: TreinoBottomBar(
            currentIndex: 1,
            onTap: (_) {},
          ),
        ),
      ),
    );

/// Un teléfono con home indicator: sin inset del sistema la barra mide su
/// mínimo y el bug se achica hasta ser difícil de ver.
void _useIphone(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  tester.view.viewPadding = const FakeViewPadding(bottom: 34 * 3);
  tester.view.padding = const FakeViewPadding(bottom: 34 * 3);
  addTearDown(tester.view.reset);
}

/// La caja que la barra ocupa DE VERDAD en este frame: margen inferior propio
/// + 8 de separación + alto animado. Es exactamente lo que el `Scaffold`
/// publica en `MediaQuery.padding.bottom`, y por eso es el techo legítimo de
/// hueco que una pantalla del shell puede reservar al final del scroll.
///
/// ⚠️ Se mide, no se calcula, y no es una constante ni siquiera adentro de
/// este archivo: medido acá, el primer test ve 94 y el segundo 114, con el
/// mismo viewport. La diferencia es que GoogleFonts resuelve async y, para
/// cuando corre el segundo, los labels ya miden con la tipografía buena y
/// entran (`labelsFit`), así que la barra deja de dibujarse compacta. Correr
/// el segundo test solo vuelve a dar 94. Todas las aserciones son relativas a
/// este número tomado en el MISMO frame, así que el orden no las mueve —
/// hardcodear 94, 114 o `minHeight` sí habría hecho un test flaky.
double _barBoxHeight(WidgetTester tester) =>
    tester.getRect(find.byType(TreinoBottomBar)).height;

/// Tolerancia que se le permite a una pantalla POR ENCIMA de la caja de la
/// barra, en pt. Es el techo de las dos aserciones de arriba.
///
/// NO es `TreinoBottomBar.minHeight` (72), y la diferencia importa: contra el
/// código viejo el gap del feed valía `barBox + 72` CLAVADO, así que un techo
/// de 72 fallaba por 0.0 — pasaba de largo sólo porque `lessThan` es estricto.
/// Con ese margen, medio píxel de redondeo lo dejaba pasar CON el bug adentro,
/// y si mañana alguien escribe `padding.bottom + collapsedHeight` (52) el test
/// aprueba el bug sin chistar.
///
/// 24 es lo más chico que sigue permitiendo lo legítimo. El dartdoc de
/// [TreinoBottomBar.minHeight] sanciona sumarle a `padding.bottom` un gap de
/// diseño —"varias pantallas usan 8 o 20"— pero nunca el alto de la barra:
/// 24 deja pasar el mayor de esos gaps con 4pt de aire y falla contra el bug
/// de #830 por 48 (feed) y 64 (perfil) en vez de por 0.
///
/// ⚠️ Si esto te falla por poco, NO subas el número: quiere decir que alguien
/// volvió a sumarle el alto de la barra a un `padding.bottom` que ya lo trae.
const double _designGapCeiling = 24;

Post _post(int index) => Post(
      id: 'p$index',
      authorUid: 'a$index',
      authorDisplayName: 'Tincho $index',
      authorAvatarUrl: null,
      authorGymId: null,
      text: 'Post $index ${'contenido ' * 10}',
      routineTag: null,
      privacy: PostPrivacy.public,
      createdAt: DateTime.utc(2026, 8, 1).subtract(Duration(hours: index)),
    );

void main() {
  group('#830: el inset inferior no duplica el alto de la barra', () {
    testWidgets('/feed — el último post termina donde empieza la barra',
        (tester) async {
      _useIphone(tester);

      await tester.pumpWidget(
        _shell(const FeedScreen(), [
          feedSegmentProvider.overrideWith((ref) => FeedSegment.public),
          myFollowingFeedProvider.overrideWith((ref) async => const <Post>[]),
          myGymFeedProvider.overrideWith((ref) async => null),
          feedPublicProvider
              .overrideWith((ref) async => List.generate(24, _post)),
        ]),
      );
      await tester.pumpAndSettle();

      final scrollView = find.byType(CustomScrollView);
      final controller =
          tester.widget<CustomScrollView>(scrollView).controller!;
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();

      final barBox = _barBoxHeight(tester);
      final gap = tester.getRect(scrollView).bottom -
          tester.getRect(find.byType(PostCard).last).bottom;

      // Piso: el último post tiene que despejar la barra entera. Si esto se
      // rompe, el post queda abajo del vidrio y no se puede leer.
      expect(gap, greaterThanOrEqualTo(barBox - 0.5),
          reason: 'el último post se mete abajo de la barra');
      // Techo: reservar la caja de la barra DOS veces es el bug. Ver
      // [_designGapCeiling] para por qué 24 y no `minHeight`.
      expect(gap, lessThan(barBox + _designGapCeiling),
          reason: 'hueco duplicado: gap=$gap, la barra ocupa $barBox');
    });

    // El stub arma un perfil PÚBLICO a propósito: con `isPublic: false` el
    // `gated` de `public_profile_screen.dart:100` da `true` y la pantalla se
    // reduce a hero + botones + `_PrivateProfileNotice` — nunca renderiza el
    // `_ProfileTabBody`, que es el único contenido de esta pantalla que crece
    // sin techo y por lo tanto donde el hueco duplicado se nota. El inset lo
    // pone el `SingleChildScrollView` de afuera y es el mismo en las dos
    // ramas, así que medir la corta no era incorrecto: era medir la barata.
    testWidgets(
        'perfil público — el último post termina donde empieza la barra',
        (tester) async {
      _useIphone(tester);

      await tester.pumpWidget(
        _shell(const PublicProfileScreen(targetUid: 'target'), [
          firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
          authStateChangesProvider
              .overrideWith((_) => Stream.value(_userWithUid('viewer'))),
          visiblePostsByAuthorProvider
              .overrideWith((ref, uid) async => List.generate(8, _post)),
          publicProfileViewProvider.overrideWith(
            () => _StubPublicProfileViewNotifier(
              const PublicProfileView(
                authorDisplayName: 'Tincho',
                authorAvatarUrl: null,
                authorGymId: null,
                outgoingFollow: null,
                incomingFollow: null,
                isSelf: false,
                isPublic: true,
              ),
            ),
          ),
        ]),
      );
      await tester.pumpAndSettle();

      // La tab por defecto es RUTINAS PÚBLICAS y acá no hay rutinas sembradas.
      // ACTIVIDAD es la que trae los posts stubbeados.
      await tester.tap(find.text('ACTIVIDAD'));
      await tester.pumpAndSettle();

      // Guarda de la rama: si esto falla, el stub volvió a caer en el gate de
      // privacidad y el resto del test estaría midiendo el aviso de perfil
      // privado en vez del contenido del perfil.
      expect(find.byType(PostCard), findsWidgets,
          reason: 'el test cayó en la rama gateada y no mide lo que dice');

      final scrollView = find.byType(SingleChildScrollView);
      final position = tester
          .state<ScrollableState>(
            find.descendant(of: scrollView, matching: find.byType(Scrollable)),
          )
          .position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();

      final barBox = _barBoxHeight(tester);
      // La `Column` es el hijo directo del scroll: su borde inferior es el
      // final del contenido, y lo que sobra hasta el viewport es el inset.
      final content =
          find.descendant(of: scrollView, matching: find.byType(Column)).first;
      final gap =
          tester.getRect(scrollView).bottom - tester.getRect(content).bottom;

      expect(gap, greaterThanOrEqualTo(barBox - 0.5),
          reason: 'el final del perfil se mete abajo de la barra');
      expect(gap, lessThan(barBox + _designGapCeiling),
          reason: 'hueco duplicado: gap=$gap, la barra ocupa $barBox');
    });
  });
}
