import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../app/theme/tokens/primitives.dart';
import '../../../core/analytics/analytics_consent.dart';
import '../../../core/widgets/motion/treino_fade_slide_in.dart';
import '../../../core/widgets/motion/treino_tappable.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../auth/application/auth_providers.dart';
import '../application/correos_promocionales_providers.dart';
import '../application/recordatorios_entrenamiento_providers.dart';
import '../application/user_providers.dart';
import '../data/user_repository.dart' show UserRepository;
import '../domain/user_role.dart';
import 'package:treino/core/widgets/treino_toast.dart';

/// Los controles de privacidad del usuario: la analítica (por dispositivo), los
/// correos promocionales (por cuenta) y, sólo para el ATLETA, los recordatorios
/// diarios de entrenamiento (por cuenta).
///
/// Existe porque la Política de Privacidad promete que el consentimiento se
/// puede **revocar en cualquier momento** y la app no tenía dónde. Un documento
/// que el usuario acepta no puede prometer un control que no existe — es la
/// misma clase de afirmación falsa que persigue la §11.1 de AGENTS.md, sólo que
/// publicada.
///
/// Son tarjetas separadas y no una lista, porque no son la misma clase de
/// preferencia. La analítica vive en este dispositivo
/// ([AnalyticsConsentNotifier]) y su explicación lo dice. Los correos
/// promocionales y los recordatorios viven en el documento del usuario y rigen
/// para la cuenta entera, en cualquier dispositivo: si compartieran tarjeta, la
/// frase «es una preferencia de ESTE dispositivo» les tocaría a los dos, y a
/// ellos les sería falsa.
///
/// ## Por qué los recordatorios están acá
///
/// No hay una pantalla de notificaciones del atleta (la superficie de ajustes
/// quedó diferida, ver `profile_screen.dart`), y los correos —que son la misma
/// clase de preferencia: un canal de avisos que se apaga por cuenta— ya viven
/// acá. Crear una pantalla, una ruta y una sección de Perfil para UN interruptor
/// sería más superficie que el cambio. El rótulo de la fila que lleva hasta acá
/// (`privacyEntryTitle`) nombra los tres controles, por la razón que ya costó
/// una vez: un control que existe pero que el rótulo esconde no se encuentra.
///
/// ## Por qué sólo el atleta
///
/// La pantalla también la abre el PF (desde `TrainerProfileView`), y a él los
/// recordatorios de racha no le llegan nunca: un interruptor que apaga algo que
/// no recibe es un control que miente. Se decide por el ROL del perfil y falla
/// CERRADO —mientras el perfil no cargó, o si el rol no es `athlete`, no se
/// dibuja—, al revés que `ProfileScreen`, que ante la duda asume atleta: acá
/// mostrarlo de más es el error.
///
/// Los interruptores aplican en el acto, no al próximo arranque: «en cualquier
/// momento» quiere decir ahora.
class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  /// Guarda una preferencia de cuenta (correos o recordatorios). Si la
  /// escritura falla, avisa.
  ///
  /// [lectura] es el provider del que el interruptor lee SU valor, y [escribir]
  /// lo que persiste la elección; el resto del contrato es el mismo para todas.
  ///
  /// No hay estado local que revertir: el interruptor lee SIEMPRE del stream
  /// del documento ([lectura]), y Firestore aplica la escritura en su caché al
  /// instante —el switch se mueve— y la deshace sola si el servidor la
  /// rechaza, re-emitiendo el valor real. Un `setState` optimista acá sería una
  /// segunda fuente de verdad que puede quedar desfasada de la primera.
  Future<void> _guardarPreferencia(
    BuildContext context,
    WidgetRef ref, {
    required ProviderListenable<AsyncValue<bool>> lectura,
    required String mensajeDeError,
    required Future<void> Function(UserRepository repo, String uid) escribir,
  }) async {
    // Se vuelve a mirar AL TOCAR, no se confía en lo que dibujó el último
    // frame: si la cuenta cambió entre ese frame y este toque, el provider
    // todavía puede estar pendiente de recalcularse con el valor del uid
    // anterior. `ref.read` fuerza ese recálculo, así que si ya no hay una
    // lectura vigente NO se escribe — la elección se hizo mirando otro
    // documento.
    if (!ref.read(lectura).tieneLecturaVigente) return;
    // El uid se lee acá, en el momento del toque, y no se captura en el build.
    final uid = ref.read(authStateChangesProvider).valueOrNull?.uid;
    // Sin sesión el interruptor ya está deshabilitado: es sólo un cinturón.
    if (uid == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await escribir(ref.read(userRepositoryProvider), uid);
    } catch (_) {
      showTreinoToastOn(
        messenger,
        mensajeDeError,
        type: TreinoToastType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final habilitada = ref.watch(analyticsConsentProvider);
    final correos = ref.watch(correosPromocionalesProvider);
    // Sólo el ATLETA ve los recordatorios (ver el dartdoc de la clase). El
    // provider ni se observa para el resto: no se abre un listener de
    // Firestore para un interruptor que no se dibuja.
    final esAtleta = ref.watch(
          userProfileProvider.select((perfil) => perfil.valueOrNull?.role),
        ) ==
        UserRole.athlete;
    final recordatorios =
        esAtleta ? ref.watch(recordatoriosEntrenamientoProvider) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header — mismo patrón que las hermanas de perfil ────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: TreinoTappable(
            onTap: () => context.pop(),
            child: Row(
              children: [
                Icon(TreinoIcon.back, size: 20, color: palette.textPrimary),
                const SizedBox(width: 14),
                Text(
                  l10n.privacyTitle.toUpperCase(),
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: AppTextSize.titleLarge,
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),

        // El contenido scrollea: con dos tarjetas y los textos al tamaño de
        // letra del sistema más grande, una Column fija desbordaba.
        //
        // `SingleChildScrollView` + `Column` y NO un `ListView(children:)`:
        // `TreinoFadeSlideIn` re-anima cada vez que un viewport desmonta y
        // vuelve a montar a su hijo, y un `ListView` desmonta lo que sale del
        // `cacheExtent`. Acá el `Column` scrollea entero, como una sola unidad.
        Expanded(
          child: SingleChildScrollView(
            // El inset inferior SUMA `MediaQuery.paddingOf(context).bottom`
            // en vez de dejar un 20 fijo. El shell corre con `extendBody: true`:
            // el `Scaffold` no le resta al body la barra flotante, la publica
            // en `padding.bottom`. Con un margen fijo, al final del scroll la
            // última línea de la tarjeta de correos quedaba DEBAJO del vidrio,
            // y sólo se notaba con los tamaños de texto de accesibilidad, donde
            // el contenido es lo bastante alto como para que scrollee. Mismo
            // patrón que `home_screen.dart` y `trainer_agenda_tab.dart`.
            padding: EdgeInsets.fromLTRB(
              AppSpacing.s20,
              0,
              AppSpacing.s20,
              AppSpacing.s20 + MediaQuery.paddingOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Analítica: preferencia de ESTE dispositivo ────────────────
                TreinoFadeSlideIn(
                  child: _PrivacySwitchCard(
                    switchKey: const ValueKey('privacy-analytics-switch'),
                    icon: TreinoIcon.shieldCheck,
                    title: l10n.privacyAnalyticsTitle,
                    subtitle: l10n.privacyAnalyticsSubtitle,
                    value: habilitada,
                    onChanged: (v) => ref
                        .read(analyticsConsentProvider.notifier)
                        .setEnabled(v),
                  ),
                ),

                // ── Qué implica, dicho sin eufemismos ─────────────────────────
                const SizedBox(height: 18),
                Text(
                  l10n.privacyAnalyticsExplainer,
                  style: GoogleFonts.barlow(
                    fontSize: AppTextSize.bodyDense,
                    height: 1.45,
                    color: palette.textMuted,
                  ),
                ),

                // La aclaración de Crashlytics va SIEMPRE visible, no detrás de
                // un "ver más". Un interruptor rotulado «analítica» que deja otra
                // recolección prendida y no lo dice es una media verdad, y una
                // media verdad en una pantalla de privacidad es peor que no
                // tener la pantalla.
                const SizedBox(height: 12),
                Text(
                  l10n.privacyAnalyticsCrashNote,
                  style: GoogleFonts.barlow(
                    fontSize: AppTextSize.caption,
                    height: 1.45,
                    color: palette.textMuted.withValues(alpha: 0.75),
                  ),
                ),

                // ── Correos promocionales: preferencia de la CUENTA ───────────
                //
                // Va DESPUÉS de todo el bloque de analítica —tarjeta, explicación
                // y nota de Crashlytics—, no entre medio: la explicación dice
                // «esta preferencia es de ESTE dispositivo» y tiene que quedar
                // pegada a la tarjeta de la que habla.
                const SizedBox(height: 20),
                TreinoFadeSlideIn(
                  child: _PrivacySwitchCard(
                    switchKey: const ValueKey('privacy-promo-emails-switch'),
                    icon: TreinoIcon.mail,
                    title: l10n.privacyPromoEmailsTitle,
                    subtitle: l10n.privacyPromoEmailsSubtitle,
                    // Ni `valueOrNull ?? true` (muestra PRENDIDO mientras
                    // carga) ni `hasValue` a secas (sigue en `true` con el
                    // valor VIEJO tras un error o un cambio de cuenta): ver
                    // `tieneLecturaVigente`. Sin respuesta vigente el
                    // interruptor queda deshabilitado, y lo que muestre su
                    // perilla no es un dato — por eso tampoco se lo anuncia al
                    // lector de pantalla (ver `_PrivacySwitchCard`).
                    value: correos.tieneLecturaVigente
                        ? correos.requireValue
                        : false,
                    sabeSuValor: correos.tieneLecturaVigente,
                    onChanged: correos.tieneLecturaVigente
                        ? (v) => _guardarPreferencia(
                              context,
                              ref,
                              lectura: correosPromocionalesProvider,
                              mensajeDeError: l10n.privacyPromoEmailsSaveError,
                              escribir: (repo, uid) =>
                                  repo.setCorreosPromocionales(uid, v),
                            )
                        : null,
                  ),
                ),

                // ── Recordatorios de entrenamiento: preferencia de la CUENTA,
                // sólo del atleta ────────────────────────────────────────────
                //
                // Última, después de los correos: las dos son preferencias de
                // la cuenta y no heredan la frase «de ESTE dispositivo» de la
                // analítica. Mismas reglas que la de correos para el estado de
                // lectura: sin respuesta vigente el interruptor va
                // deshabilitado y no anuncia un valor que nunca leyó.
                if (recordatorios != null) ...[
                  const SizedBox(height: 20),
                  TreinoFadeSlideIn(
                    child: _PrivacySwitchCard(
                      switchKey: const ValueKey(
                        'privacy-training-reminders-switch',
                      ),
                      icon: TreinoIcon.bell,
                      title: l10n.privacyTrainingRemindersTitle,
                      subtitle: l10n.privacyTrainingRemindersSubtitle,
                      value: recordatorios.tieneLecturaVigente
                          ? recordatorios.requireValue
                          : false,
                      sabeSuValor: recordatorios.tieneLecturaVigente,
                      onChanged: recordatorios.tieneLecturaVigente
                          ? (v) => _guardarPreferencia(
                                context,
                                ref,
                                lectura: recordatoriosEntrenamientoProvider,
                                mensajeDeError:
                                    l10n.privacyTrainingRemindersSaveError,
                                escribir: (repo, uid) =>
                                    repo.setRecordatoriosEntrenamiento(uid, v),
                              )
                          : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Una tarjeta con un título, una línea de explicación y un interruptor.
///
/// [onChanged] en `null` deja el interruptor deshabilitado. Cuando
/// [sabeSuValor] es `false`, [value] es sólo un relleno para dibujar la perilla
/// y NO se le expone al lector de pantalla: un `Switch` no puede dibujar «no
/// sé», así que a la vista le queda un gris apagado, pero la semántica sí puede
/// callar el estado en vez de anunciar «apagado» sobre algo que no se leyó.
class _PrivacySwitchCard extends StatelessWidget {
  const _PrivacySwitchCard({
    required this.switchKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.sabeSuValor = true,
  });

  final Key switchKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool sabeSuValor;
  final ValueChanged<bool>? onChanged;

  /// Desde qué escala de texto el interruptor deja de ir AL COSTADO del texto
  /// y pasa DEBAJO.
  ///
  /// POR QUÉ HACE FALTA. En una fila ícono + texto + switch la columna del
  /// texto es lo que sobra, y con la letra muy grande sobra menos que la
  /// palabra más larga del título: «promocionales» queda partida en el medio
  /// («Correos pr / omocional / es»). Flutter parte una palabra antes de
  /// desbordar, así que no hay excepción ni franja amarilla que lo avise.
  ///
  /// POR QUÉ UN UMBRAL Y NO MEDIR. Decidirlo midiendo la palabra con un
  /// `TextPainter` exigiría conocer el ancho del switch (lo fija el tema, no
  /// este archivo) y, en un widget test, mediría con una fuente que no es la
  /// del device. Un umbral sobre la escala es determinístico y el error cuesta
  /// distinto para cada lado: apilar de más es una fila más de alto; no apilar
  /// de menos es una palabra rota.
  ///
  /// POR QUÉ 1.5. Cae en el medio de los dos tamaños de iOS que lo rodean: el
  /// más grande SIN accesibilidad (xxxLarge, ≈1.35, que se ve bien en fila y
  /// queda igual) y el primero CON ella (≈1.65). Android tiene una escala
  /// continua y ahí 1.5 ya apila. Esos ≈ salen de la tabla de tamaños de
  /// Dynamic Type de Apple, no están medidos en el device.
  static const double _escalaQueApila = 1.5;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final apilado =
        MediaQuery.textScalerOf(context).scale(1) >= _escalaQueApila;

    final iconWidget = Icon(icon, size: 20, color: palette.textMuted);
    final textos = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.barlow(
            fontWeight: FontWeight.w600,
            fontSize: AppTextSize.body,
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.hairline),
        Text(
          subtitle,
          style: GoogleFonts.barlow(
            fontSize: AppTextSize.bodyDense,
            color: palette.textMuted,
          ),
        ),
      ],
    );
    // El `Switch` declara SU PROPIO estado (`toggled: value`) y los
    // nodos de semántica se fusionan: con `toggled: null` en este
    // wrapper el lector igual oía «apagado». Para callarlo hay que
    // excluir la semántica del hijo y describir el control desde acá.
    final control = Semantics(
      label: title,
      toggled: sabeSuValor ? value : null,
      enabled: onChanged != null,
      excludeSemantics: !sabeSuValor,
      child: Switch(
        key: switchKey,
        value: value,
        activeThumbColor: palette.accent,
        onChanged: onChanged,
      ),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: palette.textMuted.withValues(alpha: 0.12),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: apilado
            // APILADO: ícono arriba, texto a TODO el ancho, switch abajo a la
            // derecha. El ícono NO se queda en la fila del texto aunque se vea
            // más natural: se midió «promocionales» en Barlow SemiBold 14 px a
            // 3.1x (el tamaño más grande de iOS) en ≈287 px, y en un iPhone de
            // 390 pt el texto tiene 314 sin ícono y 280 con él. Con el ícono
            // al lado la palabra se seguiría partiendo.
            //
            // LÍMITE, y no se promete lo contrario: en una pantalla de 320 pt
            // a 3.1x el texto tiene 244 px y la palabra necesita ≈287, así que
            // no entra ni con todo el ancho y Flutter la parte igual.
            // `Stretch` hace que la tarjeta ocupe el ancho entero; el ícono y
            // el switch se alinean con `Align` porque un hijo `stretch` de
            // ancho fijo se centraría.
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: iconWidget,
                  ),
                  const SizedBox(height: AppSpacing.s8),
                  textos,
                  const SizedBox(height: AppSpacing.s8),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: control,
                  ),
                ],
              )
            : Row(
                children: [
                  iconWidget,
                  const SizedBox(width: 14),
                  Expanded(child: textos),
                  const SizedBox(width: 12),
                  control,
                ],
              ),
      ),
    );
  }
}
