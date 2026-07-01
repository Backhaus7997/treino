import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/avatar_upload_service.dart';
import 'profile_setup_notifier.dart';

/// Singleton del service que uploadea avatares a Firebase Storage.
final avatarUploadServiceProvider = Provider<AvatarUploadService>(
  (_) => AvatarUploadService(),
);

/// Estado del flow: holds draft + current step + submit state.
final profileSetupNotifierProvider =
    NotifierProvider<ProfileSetupNotifier, ProfileSetupState>(
  ProfileSetupNotifier.new,
);
