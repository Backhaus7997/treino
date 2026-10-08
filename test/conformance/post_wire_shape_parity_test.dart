// post_wire_shape_parity_test.dart — lo que el cliente MANDA contra lo que la
// regla ACEPTA.
//
// ─── Por qué existe ─────────────────────────────────────────────────────────
//
// La forma de un post vive en DOS lugares que no se hablan:
//
//   • Dart — `Post.toJson()` (generado por json_serializable en `post.g.dart`),
//     que es literalmente el mapa que `PostRepository.create` le pasa a
//     `ref.set(...)`.
//   • Rules — el `keys().hasOnly([...])` del `allow create` de `posts` en
//     `firestore.rules`, que es la lista blanca que el servidor exige.
//
// Si el cliente emite UNA key que la lista no tiene, **todo create de post es
// PERMISSION_DENIED**. No se degrada: se rompe entero, para todos, en
// producción.
//
// Y eso ya pasó. El 2026-07-28 (#591) se escribieron el `hasOnly` y el fixture
// de `post-create-shape-rules.test.ts`, y coincidían. El 2026-07-31
// (`feat(feed): dominio y datos de reacciones`) se agregó `reactionCounts` al
// modelo. El fixture de rules, escrito a mano, no se enteró — así que el test
// siguió en verde mientras publicar un post estaba roto. Siete semanas.
//
// Es la TERCERA vez con esta forma exacta: `Block.toJson()` (docs/legal/
// ESTADO.md §11) y `feedbackCounts` (#1160). Siempre lo mismo: un fixture
// escrito a mano que jura ser el espejo del modelo y se desincroniza callado.
//
// ─── Por qué del lado Dart y no en el fixture de rules ──────────────────────
//
// Porque el fixture de `functions/src/__tests__/` es OTRA copia a mano, y
// arreglarlo produce exactamente el mismo bug dentro de tres meses. Un fixture
// no puede custodiar al modelo: es del mismo material que el modelo.
//
// Este test no copia nada. Deriva las keys de `Post(...).toJson()` en runtime
// —la fuente de verdad real, la que corre en el teléfono— y las contrasta
// contra la lista parseada del `.rules`. Para que divergan hay que romperlo.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/feed/domain/post.dart';
import 'package:treino/features/feed/domain/post_privacy.dart';
import 'package:treino/features/feed/domain/routine_tag.dart';
import 'package:treino/features/feed/domain/workout_snapshot.dart';
import 'package:treino/features/feed/domain/workout_stats.dart';

/// Las keys del `hasOnly` del `allow create` de `match /posts/{postId}`.
///
/// Devuelve `null` si no encuentra lo que busca — y eso hace fallar el test a
/// propósito. Un guard que no encuentra su ancla y pasa igual es peor que no
/// tenerlo: da la sensación de cobertura sin la cobertura.
Set<String>? _keysDelCreateDeRules(String fuente) {
  final bloquePosts = fuente.indexOf(RegExp(r'match\s+/posts/\{postId\}\s*\{'));
  if (bloquePosts == -1) return null;

  // Desde el `match` de posts, el PRIMER `allow create:` es el suyo. El
  // `allow update:` viene después y tiene su propio `hasOnly` (con
  // `reactionCounts`, porque ahí sí se pinea inmutable) — tomar el equivocado
  // dejaría el guard ciego justo para el campo que rompió todo.
  final create = fuente.indexOf(RegExp(r'allow\s+create\s*:'), bloquePosts);
  if (create == -1) return null;

  final hasOnly = RegExp(r'keys\(\)\.hasOnly\(\s*\[(.*?)\]\s*\)', dotAll: true)
      .firstMatch(fuente.substring(create));
  if (hasOnly == null) return null;

  final keys = RegExp("'([^']+)'")
      .allMatches(hasOnly.group(1)!)
      .map((m) => m.group(1)!)
      .toSet();
  return keys.isEmpty ? null : keys;
}

/// Un post con TODOS los campos opcionales poblados.
///
/// `toJson()` hoy emite cada key incondicionalmente (no hay
/// `includeIfNull: false` en este modelo), pero poblarlos igual vuelve al test
/// robusto si mañana alguien lo agrega: así se mide el conjunto MÁXIMO de keys
/// que el cliente puede llegar a mandar, que es el que la regla tiene que
/// aceptar.
Post _postConTodo() => Post(
      id: 'p1',
      authorUid: 'u1',
      authorDisplayName: 'Ana',
      authorAvatarUrl: 'https://example.test/a.jpg',
      authorGymId: 'g1',
      text: '¡Terminé mi entreno!',
      routineTag: const RoutineTag(routineId: 'r1', routineName: 'Push'),
      privacy: PostPrivacy.gym,
      createdAt: DateTime.utc(2026, 9, 17),
      workoutStats: const WorkoutStats(
        volumeKg: 1200,
        durationMin: 45,
        exerciseCount: 5,
      ),
      photoUrl: 'https://example.test/p.jpg',
      workoutSnapshot: const WorkoutSnapshot(exercises: []),
    );

void main() {
  group('Post.toJson() y el hasOnly del create de posts dicen lo mismo', () {
    final rules = File('firestore.rules');

    test('firestore.rules existe donde este test lo busca', () {
      expect(
        rules.existsSync(),
        isTrue,
        reason: 'no encontré ${rules.path} desde ${Directory.current}. Si se '
            'movió, movete este test con él en vez de borrarlo: sin esto, el '
            'cliente y la regla pueden divergir en silencio y publicar un post '
            'se rompe entero en producción.',
      );
    });

    test('el hasOnly del create se puede leer del .rules', () {
      // Si esto falla, el guard quedó ciego: alguien reescribió el bloque de
      // `posts`, renombró el `match`, o partió el `hasOnly` en un helper.
      expect(
        _keysDelCreateDeRules(rules.readAsStringSync()),
        isNotNull,
        reason: 'no pude parsear `keys().hasOnly([...])` del `allow create` de '
            '`match /posts/{postId}` en ${rules.path}. Un guard que no '
            'encuentra lo que busca y pasa igual no sirve: arreglá el parser o '
            'este test miente.',
      );
    });

    test('el cliente no manda ninguna key que el create rechace', () {
      final permitidas = _keysDelCreateDeRules(rules.readAsStringSync())!;
      final emitidas = _postConTodo().toJson().keys.toSet();

      final deMas = emitidas.difference(permitidas);
      expect(
        deMas,
        isEmpty,
        reason: 'Post.toJson() emite $deMas, que el `hasOnly` del create NO '
            'acepta. Esto no degrada nada: hace que TODO create de post sea '
            'PERMISSION_DENIED.\n\n'
            'Antes de agregar la key al `hasOnly`, preguntate si al cliente le '
            'corresponde escribirla. `reactionCounts` es Cloud-Function-only '
            '(lo fija `functions/src/__tests__/reaction-rules.test.ts`): '
            'abrirla en el create deja que cualquiera se plante 999 reacciones '
            'en su propio post. Para un campo así el fix va del lado Dart, con '
            '`@JsonKey(includeToJson: false)` — el cliente lo lee, nunca lo '
            'escribe.',
      );
    });

    test('el create no permite keys que el cliente nunca manda', () {
      final permitidas = _keysDelCreateDeRules(rules.readAsStringSync())!;
      final emitidas = _postConTodo().toJson().keys.toSet();

      final deMenos = permitidas.difference(emitidas);
      expect(
        deMenos,
        isEmpty,
        reason: 'el `hasOnly` del create acepta $deMenos, que `Post.toJson()` '
            'no emite nunca. No rompe nada hoy, pero es permiso muerto: o '
            'quedó de un campo que se borró del modelo, o alguien abrió la '
            'regla antes que el cliente. Sacalo del `hasOnly`, o mandá la key.',
      );
    });
  });
}
