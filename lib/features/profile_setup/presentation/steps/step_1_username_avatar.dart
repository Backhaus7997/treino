import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/widgets/treino_icon.dart';
import '../../../auth/presentation/widgets/auth_input.dart';
import '../../application/profile_setup_notifier.dart';
import '../../application/profile_setup_providers.dart';
import '../../domain/profile_setup_validators.dart';
import '../widgets/avatar_picker_button.dart';

/// Step 1: avatar (opcional) + username. Mockup: `profile-setup-1.png`.
class Step1UsernameAvatar extends ConsumerStatefulWidget {
  const Step1UsernameAvatar({super.key});

  @override
  ConsumerState<Step1UsernameAvatar> createState() =>
      _Step1UsernameAvatarState();
}

class _Step1UsernameAvatarState extends ConsumerState<Step1UsernameAvatar> {
  late final TextEditingController _usernameCtrl;

  @override
  void initState() {
    super.initState();
    final initial = ref.read(profileSetupNotifierProvider).draft.username ?? '';
    _usernameCtrl = TextEditingController(text: initial);
    _usernameCtrl.addListener(_syncUsername);
  }

  void _syncUsername() {
    ref
        .read(profileSetupNotifierProvider.notifier)
        .updateUsername(_usernameCtrl.text);
  }

  @override
  void dispose() {
    _usernameCtrl.removeListener(_syncUsername);
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      imageQuality: 85,
    );
    if (file != null) {
      ref
          .read(profileSetupNotifierProvider.notifier)
          .updateAvatarLocalPath(file.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(
      profileSetupNotifierProvider.select(
        (ProfileSetupState s) => s.draft,
      ),
    );
    final initial = (draft.username?.trim().isNotEmpty ?? false)
        ? draft.username!.trim()[0]
        : '?';

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 32),
          Align(
            alignment: Alignment.center,
            child: AvatarPickerButton(
              localPath: draft.avatarLocalPath,
              usernameInitial: initial,
              onTap: _pickAvatar,
            ),
          ),
          const SizedBox(height: 32),
          AuthInput(
            controller: _usernameCtrl,
            label: 'USERNAME',
            hint: '@julieta',
            leadingIcon: TreinoIcon.atSign,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.done,
            validator: ProfileSetupValidators.validateUsername,
            onFieldSubmitted: (_) {},
          ),
        ],
      ),
    );
  }
}
