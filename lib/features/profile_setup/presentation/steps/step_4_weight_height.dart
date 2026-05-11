import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../auth/presentation/widgets/auth_input.dart';
import '../../application/profile_setup_providers.dart';
import '../../domain/profile_setup_validators.dart';

/// Step 4: peso y altura. Mockup: `profile-setup-4.png`.
class Step4WeightHeight extends ConsumerStatefulWidget {
  const Step4WeightHeight({super.key});

  @override
  ConsumerState<Step4WeightHeight> createState() => _Step4WeightHeightState();
}

class _Step4WeightHeightState extends ConsumerState<Step4WeightHeight> {
  late final TextEditingController _weightCtrl;
  late final TextEditingController _heightCtrl;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(profileSetupNotifierProvider).draft;
    _weightCtrl = TextEditingController(
      text: draft.bodyWeightKg?.toString() ?? '',
    );
    _heightCtrl = TextEditingController(
      text: draft.heightCm?.toString() ?? '',
    );
    _weightCtrl.addListener(_syncWeight);
    _heightCtrl.addListener(_syncHeight);
  }

  void _syncWeight() {
    final n = double.tryParse(_weightCtrl.text.replaceAll(',', '.'));
    ref.read(profileSetupNotifierProvider.notifier).updateBodyWeightKg(n);
  }

  void _syncHeight() {
    final n = int.tryParse(_heightCtrl.text.trim());
    ref.read(profileSetupNotifierProvider.notifier).updateHeightCm(n);
  }

  @override
  void dispose() {
    _weightCtrl.removeListener(_syncWeight);
    _heightCtrl.removeListener(_syncHeight);
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Text(
            'Lo usamos para calcular volumen y progreso.',
            style: GoogleFonts.barlow(
              color: palette.textMuted,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          AuthInput(
            controller: _weightCtrl,
            label: 'PESO (KG)',
            hint: '82',
            leadingIcon: TreinoIcon.scales,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            validator: ProfileSetupValidators.validateBodyWeightKg,
          ),
          const SizedBox(height: 14),
          AuthInput(
            controller: _heightCtrl,
            label: 'ALTURA (CM)',
            hint: '168',
            leadingIcon: TreinoIcon.ruler,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            validator: ProfileSetupValidators.validateHeightCm,
          ),
          const SizedBox(height: 20),
          Text(
            'Podés cambiarlo cuando quieras desde Perfil → Ajustes.',
            style: GoogleFonts.barlow(
              color: palette.textMuted,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
