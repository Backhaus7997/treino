import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/avatar_upload_service.dart';
import '../domain/gym.dart';
import 'profile_setup_notifier.dart';

/// Catálogo hardcodeado de gyms mientras no exista una colección `gyms/` en
/// Firestore. Cuando se cree, reemplazar este provider por un StreamProvider.
const List<Gym> _kHardcodedGyms = [
  Gym(
    id: 'smart-fit-palermo',
    name: 'SMART FIT',
    address: 'Av. Santa Fe 2543 - Palermo',
  ),
  Gym(
    id: 'sportclub-belgrano',
    name: 'SPORTCLUB',
    address: 'Cabildo 1789 - Belgrano',
  ),
  Gym(
    id: 'megatlon-recoleta',
    name: 'MEGATLON',
    address: 'Av. Pueyrredón 1232 - Recoleta',
  ),
];

/// Query actual de búsqueda de gym (step 2). La UI escribe acá desde el search bar.
final gymSearchQueryProvider = StateProvider<String>((_) => '');

/// Lista de gyms filtrada por el query. Mientras está vacío, devuelve el
/// catálogo completo.
final filteredGymsProvider = Provider<List<Gym>>((ref) {
  final query = ref.watch(gymSearchQueryProvider).trim().toLowerCase();
  if (query.isEmpty) return _kHardcodedGyms;
  return _kHardcodedGyms
      .where((g) =>
          g.name.toLowerCase().contains(query) ||
          g.address.toLowerCase().contains(query))
      .toList(growable: false);
});

/// Singleton del service que uploadea avatares a Firebase Storage.
final avatarUploadServiceProvider = Provider<AvatarUploadService>(
  (_) => AvatarUploadService(),
);

/// Estado del flow: holds draft + current step + submit state.
final profileSetupNotifierProvider =
    NotifierProvider<ProfileSetupNotifier, ProfileSetupState>(
  ProfileSetupNotifier.new,
);
