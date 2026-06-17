import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
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
    // Username prellenado (volver a este step, o re-correr el onboarding):
    // disparamos la verificación de disponibilidad para que el gate de
    // SIGUIENTE arranque correcto en vez de quedar bloqueado en `unknown`.
    if (initial.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(profileSetupNotifierProvider.notifier).updateUsername(initial);
      });
    }
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
    final availability = ref.watch(
      profileSetupNotifierProvider.select(
        (ProfileSetupState s) => s.usernameAvailability,
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
          _UsernameAvailabilityStatus(availability: availability),
        ],
      ),
    );
  }
}

/// Fila de estado inline debajo del campo username: refleja el resultado de la
/// verificación de disponibilidad async (handle público único). Error
/// prevention + match con el mundo real (la gente espera que un @handle sea
/// único). No ocupa espacio cuando no hay nada que mostrar.
class _UsernameAvailabilityStatus extends StatelessWidget {
  const _UsernameAvailabilityStatus({required this.availability});

  final UsernameAvailability availability;

  @override
  Widget build(BuildContext context) {
    // Sin estado que mostrar (campo vacío / formato inválido): no ocupa lugar.
    if (availability == UsernameAvailability.unknown) {
      return const SizedBox.shrink();
    }

    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    final (String text, Color color, Widget leading) = switch (availability) {
      UsernameAvailability.checking => (
          l10n.profileSetupUsernameChecking,
          palette.textMuted,
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: palette.textMuted,
            ),
          ),
        ),
      UsernameAvailability.available => (
          l10n.profileSetupUsernameAvailable,
          palette.accent,
          Icon(TreinoIcon.check, size: 16, color: palette.accent),
        ),
      UsernameAvailability.taken => (
          l10n.profileSetupUsernameTaken,
          palette.danger,
          Icon(TreinoIcon.warning, size: 16, color: palette.danger),
        ),
      UsernameAvailability.error => (
          l10n.profileSetupUsernameCheckError,
          palette.warning,
          Icon(TreinoIcon.warning, size: 16, color: palette.warning),
        ),
      UsernameAvailability.unknown => (
          '',
          palette.textMuted,
          const SizedBox.shrink(),
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            leading,
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: TextStyle(color: color, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
