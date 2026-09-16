import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:treino/app/theme/tokens/tokens.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/presentation/widgets/auth_pill_button.dart';
import '../../profile/application/user_providers.dart';
import '../domain/profile_setup_validators.dart';
import 'widgets/born_at_field.dart';

/// Gate de edad mínima para cuentas que YA existían cuando se introdujo el
/// requisito, y que por lo tanto nunca declararon su fecha de nacimiento.
///
/// **Por qué es una pantalla propia y no el flow de ProfileSetup.** Reusar el
/// flow para estas cuentas parecía lo económico y rompe por dos lados:
///
/// 1. El bloque "onboarding-completo" del router saca al usuario de
///    `/profile-setup` en cuanto `displayName != null`. Una cuenta vieja tiene
///    displayName cargado, así que entraría y saldría en el mismo frame —
///    loop de redirect infinito para toda la base existente.
/// 2. El paso 1 verifica que el username esté libre. El de una cuenta vieja
///    está tomado *por ella misma*, así que el chequeo la rechazaría a ella.
///
/// Un solo campo, sin barra inferior y sin salida lateral: es un gate, no una
/// pantalla de edición. La única salida sin cargar la fecha es cerrar sesión,
/// que existe para que alguien que no llega a la edad mínima no quede con la
/// app bloqueada y sin ninguna acción posible.
class BirthDateGateScreen extends ConsumerStatefulWidget {
  const BirthDateGateScreen({super.key});

  @override
  ConsumerState<BirthDateGateScreen> createState() =>
      _BirthDateGateScreenState();
}

class _BirthDateGateScreenState extends ConsumerState<BirthDateGateScreen> {
  DateTime? _picked;
  bool _saving = false;
  String? _saveError;

  Future<void> _save() async {
    final validation = ProfileSetupValidators.validateBornAt(_picked);
    if (validation != null) return;

    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid == null) return;

    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await ref.read(userRepositoryProvider).update(uid, {'bornAt': _picked});
      // NO navegamos a mano. El redirect del router saca al usuario de acá en
      // cuanto `userProfileProvider` emite el bornAt recién guardado. Es la
      // misma lección que ProfileSetupFlow: un `context.go` manual corre una
      // carrera contra el stream, navega antes de que el snapshot actualice y
      // el gate rebota al usuario de vuelta a esta pantalla.
      if (mounted) setState(() => _saving = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = 'No pudimos guardar la fecha. Probá de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final signingOut = ref.watch(authNotifierProvider).isLoading;
    final validation =
        _picked == null ? null : ProfileSetupValidators.validateBornAt(_picked);
    final canSave = _picked != null && validation == null && !_saving;

    return Scaffold(
      backgroundColor: palette.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '¿CUÁNDO NACISTE?', // i18n: Fase 6 Etapa 3
                  style: GoogleFonts.barlowCondensed(
                    color: palette.textPrimary,
                    fontSize: AppTextSize.displayLarge,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'TREINO ahora pide una edad mínima de '
                  '${ProfileSetupValidators.kMinAgeYears} años. Para seguir '
                  'usando tu cuenta necesitamos que cargues tu fecha de '
                  'nacimiento una sola vez.', // i18n: Fase 6 Etapa 3
                  style: GoogleFonts.barlow(
                    color: palette.textMuted,
                    fontSize: AppTextSize.body,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                BornAtField(
                  key: const Key('birth_date_gate_field'),
                  value: _picked,
                  errorText: validation ?? _saveError,
                  onTap: () async {
                    final picked = await pickBornAt(context, _picked);
                    if (picked == null || !mounted) return;
                    setState(() {
                      _picked = picked;
                      _saveError = null;
                    });
                  },
                ),
                const SizedBox(height: 20),
                AuthPillButton(
                  key: const Key('birth_date_gate_save'),
                  label: 'GUARDAR', // i18n: Fase 6 Etapa 3
                  isLoading: _saving,
                  showArrow: false,
                  onPressed: canSave ? _save : null,
                ),
                const SizedBox(height: 12),
                // Única salida sin cargar la fecha. Que exista NO es la
                // política para un menor de la edad mínima: qué pasa con esa
                // cuenta y con los datos que ya cargó es una decisión del
                // titular (bloqueo inmediato, ventana de gracia, o congelado),
                // y mientras no esté tomada el botón GUARDAR simplemente queda
                // deshabilitado con el error a la vista. Acá no se borra nada.
                Center(
                  child: TextButton.icon(
                    onPressed: signingOut
                        ? null
                        : () =>
                            ref.read(authNotifierProvider.notifier).signOut(),
                    style: TextButton.styleFrom(
                      foregroundColor: palette.textMuted,
                    ),
                    icon: const Icon(TreinoIcon.signOut, size: 18),
                    label: const Text('Cerrar sesión'), // i18n: Fase 6 Etapa 3
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
