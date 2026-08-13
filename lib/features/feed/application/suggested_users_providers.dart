import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/geohash.dart';
import '../../../core/utils/haversine.dart';
import '../../gyms/application/gym_providers.dart' show gymRepositoryProvider;
import '../../gyms/domain/gym.dart' show Gym, kNoGymId;
import '../../profile/application/user_providers.dart' show firestoreProvider;
import '../../profile/domain/user_public_profile.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import 'follow_providers.dart' show followRepositoryProvider;

/// Tope de valores que Firestore acepta en un `whereIn`.
const int _kWhereInLimit = 30;

const int kSuggestedUsersLimit = 20;
const int kSuggestedUsersPageSize = 8;
const int _kSuggestedUsersPostCadence = 10;

List<UserPublicProfile> suggestedUsersPage(
  List<UserPublicProfile> candidates,
  int pageIndex,
) {
  if (pageIndex < 0) return const [];
  return candidates
      .skip(pageIndex * kSuggestedUsersPageSize)
      .take(kSuggestedUsersPageSize)
      .toList(growable: false);
}

List<UserPublicProfile> suggestedUsersAfterPost(
  List<UserPublicProfile> candidates,
  int postIndex,
) {
  if (postIndex < 0 || (postIndex + 1) % _kSuggestedUsersPostCadence != 0) {
    return const [];
  }

  final pageIndex = (postIndex + 1) ~/ _kSuggestedUsersPostCadence - 1;
  return suggestedUsersPage(candidates, pageIndex);
}

/// Orden alfabético estable. El uid desempata para que dos personas con el
/// mismo nombre no bailen de posición entre recargas.
int _byName(UserPublicProfile a, UserPublicProfile b) {
  final aName = a.displayNameLowercase ?? a.displayName ?? '';
  final bName = b.displayNameLowercase ?? b.displayName ?? '';
  final byName = aName.compareTo(bName);
  return byName != 0 ? byName : a.uid.compareTo(b.uid);
}

/// Gente para seguir: primero la de [gymId], después la de gyms CERCANOS.
///
/// El mismo gym manda, y recién cuando no alcanza para llenar el cupo se sale
/// a buscar alrededor. Antes la consulta terminaba en el propio gym y nada
/// más: con un solo perfil ahí —el tuyo— devolvía cero, y la sección
/// desaparecía sin decir nada. No estaba rota, pedía una densidad de usuarios
/// que todavía no existe.
///
/// `userPublicProfiles` no guarda ubicación, solo `gymId`, así que la cercanía
/// se resuelve en dos saltos: geohash → gyms cercanos → perfiles en esos gyms.
/// Se reusa el mismo patrón del discovery de entrenadores, incluida la grilla
/// de 5×5 y no 3×3: ahí ya se descubrió que el 3×3 dejaba afuera a alguien a
/// 9,8km, y 25 celdas siguen entrando en el tope de 30 de Firestore.
///
/// La distancia se mide desde el GYM y no desde el GPS —a diferencia del
/// discovery de entrenadores— para no pedir permiso de ubicación al abrir el
/// feed. El gym ya está elegido, es estable, y no obliga a manejar la negativa.
///
/// La key de la family es a propósito un [String]: una key de tipo colección
/// usa igualdad por identidad y erraría el cache de Riverpod todo el tiempo.
///
/// La exclusión es por PRESENCIA de arista, en cualquier dirección y estado —
/// `allOf` resuelve las dos direcciones con un solo `array-contains` sobre
/// `members`. Deliberadamente NO es direccional: sugerir a alguien que ya te
/// mandó una solicitud sería ofrecerte gente que ya está en tu inbox.
final suggestedUsersProvider =
    FutureProvider.autoDispose.family<List<UserPublicProfile>, String>(
  (ref, gymId) async {
    final currentUid = ref.watch(currentUidProvider);
    if (currentUid == null || gymId.isEmpty || gymId == kNoGymId) {
      return const [];
    }

    final firestore = ref.watch(firestoreProvider);
    final edges = await ref.watch(followRepositoryProvider).allOf(currentUid);
    final excludedUids = edges
        .expand((edge) => edge.members)
        .where((uid) => uid != currentUid)
        .toSet();

    bool isCandidate(UserPublicProfile p) =>
        p.uid != currentUid && !excludedUids.contains(p.uid);

    Future<List<UserPublicProfile>> profilesInGyms(List<String> ids) async {
      if (ids.isEmpty) return const [];
      final snap = await firestore
          .collection('userPublicProfiles')
          .where('gymId', whereIn: ids)
          .get();
      return snap.docs
          .map((doc) => UserPublicProfile.fromJson(doc.data()))
          .where(isCandidate)
          .toList();
    }

    final sameGym = (await profilesInGyms([gymId]))..sort(_byName);
    if (sameGym.length >= kSuggestedUsersLimit) {
      return sameGym.take(kSuggestedUsersLimit).toList();
    }

    // Sin gym resuelto no hay desde dónde medir: se devuelve lo del propio gym
    // en vez de inventar una cercanía que no se puede calcular.
    final gymRepo = ref.watch(gymRepositoryProvider);
    final Gym? myGym = await gymRepo.getById(gymId);
    if (myGym == null) return sameGym;

    final cells = [myGym.geohash, ...geohashNeighbors5x5(myGym.geohash)];
    final distanceFromMyGym = <String, double>{};
    final nearbyGyms = (await gymRepo.listByGeohashes(cells))
        .where((g) => g.id != gymId)
        .toList();
    for (final g in nearbyGyms) {
      distanceFromMyGym[g.id] = haversineKm(myGym.lat, myGym.lng, g.lat, g.lng);
    }
    // Ordenar ANTES de recortar: el tope de 30 tiene que quedarse con los gyms
    // más cercanos, no con los primeros que haya devuelto Firestore.
    nearbyGyms.sort(
      (a, b) => distanceFromMyGym[a.id]!.compareTo(distanceFromMyGym[b.id]!),
    );
    if (nearbyGyms.isEmpty) return sameGym;

    final alreadyIn = sameGym.map((p) => p.uid).toSet();
    final nearby = (await profilesInGyms(
      nearbyGyms.take(_kWhereInLimit).map((g) => g.id).toList(),
    ))
        .where((p) => !alreadyIn.contains(p.uid))
        .toList()
      ..sort((a, b) {
        final da = distanceFromMyGym[a.gymId] ?? double.infinity;
        final db = distanceFromMyGym[b.gymId] ?? double.infinity;
        final byDistance = da.compareTo(db);
        return byDistance != 0 ? byDistance : _byName(a, b);
      });

    return [...sameGym, ...nearby].take(kSuggestedUsersLimit).toList();
  },
);
