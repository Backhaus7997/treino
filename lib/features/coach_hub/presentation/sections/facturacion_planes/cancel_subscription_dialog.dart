import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
import 'package:treino/core/widgets/motion/treino_tappable.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/coach_hub/presentation/sections/facturacion_planes/plan_cancel.dart';

/// El diálogo de baja de la suscripción.
///
/// ── Lo que tiene que decir ANTES del botón, y por qué ──
///
/// Dar de baja es **irreversible en Mercado Pago**: un preapproval cancelado no
/// se reactiva, hay que crear uno nuevo. Y el `§7` de los Términos de
/// Suscripción promete, publicado, que «conservás el acceso hasta el final del
/// período que ya pagaste».
///
/// Las dos cosas van en la confirmación, no en un tooltip ni en un párrafo
/// abajo: son lo que cambia la decisión. Un PF que cree que puede reactivar
/// mañana aprieta distinto que uno que sabe que no.
///
/// La tercera —que no se borra nada— está porque es la duda que más frena, y
/// es verdad: `docs/paywall-alumno-suelto.md` §5 lo documenta para el alumno, y
/// para el PF sus alumnos conservan rutinas, historial y chat.
Future<void> showCancelSubscriptionDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _CancelDialog(),
  );
}

class _CancelDialog extends StatefulWidget {
  const _CancelDialog();

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  /// `setState` y no Riverpod a propósito: es estado de PRESENTACIÓN de un
  /// diálogo que muere al cerrarse, no estado de negocio (AGENTS.md regla 6).
  bool _enviando = false;
  ResultadoDeBaja? _resultado;

  Future<void> _confirmar() async {
    final capacidad = resolvePlanCancel();
    if (capacidad is! PlanCancelAvailable) return;

    setState(() => _enviando = true);
    final r = await capacidad.cancelar();
    if (!mounted) return;
    setState(() {
      _enviando = false;
      _resultado = r;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final r = _resultado;

    return Dialog(
      backgroundColor: palette.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: r == null
                ? _pregunta(context, palette)
                : _respuesta(context, palette, r),
          ),
        ),
      ),
    );
  }

  List<Widget> _pregunta(BuildContext context, AppPalette palette) => [
        Text(
          'DAR DE BAJA LA SUSCRIPCIÓN', // i18n: Fase W3
          style: GoogleFonts.barlowCondensed(
            color: palette.textPrimary,
            fontSize: AppTextSize.titleLarge,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: AppSpacing.s14),
        _Punto(
          palette: palette,
          icono: TreinoIcon.check,
          destacado: true,
          texto: 'Conservás el acceso hasta el final del período que ya '
              'pagaste. No se te corta nada hoy.', // i18n: Fase W3
        ),
        const SizedBox(height: AppSpacing.s12),
        _Punto(
          palette: palette,
          icono: TreinoIcon.check,
          texto: 'No se borra nada. Tus alumnos conservan sus rutinas, su '
              'historial y su chat.', // i18n: Fase W3
        ),
        const SizedBox(height: AppSpacing.s12),
        _Punto(
          palette: palette,
          icono: TreinoIcon.warning,
          // El que cambia la decisión: sin esto, alguien aprieta creyendo que
          // puede volver atrás mañana.
          texto: 'La baja es definitiva para esta suscripción. Para volver hay '
              'que contratar de nuevo.', // i18n: Fase W3
        ),
        const SizedBox(height: AppSpacing.s20),
        _Acciones(
          palette: palette,
          enviando: _enviando,
          onConfirmar: _confirmar,
        ),
      ];

  List<Widget> _respuesta(
    BuildContext context,
    AppPalette palette,
    ResultadoDeBaja r,
  ) {
    final (titulo, cuerpo, icono) = switch (r.estado) {
      EstadoDeBaja.dadaDeBaja => (
          'LISTO, SE DIO DE BAJA', // i18n: Fase W3
          r.accesoHasta == null
              // Sin fecha igual se confirma la baja: el hecho que importa es
              // que ya no se le va a cobrar. Prometer una fecha que no tenemos
              // sería peor que no darla.
              ? 'No se te va a cobrar de nuevo. Conservás el acceso hasta que '
                  'termine el período que ya pagaste.'
              : 'No se te va a cobrar de nuevo. Conservás el acceso hasta el '
                  '${_fecha(r.accesoHasta!)}.', // i18n: Fase W3
          TreinoIcon.check,
        ),
      EstadoDeBaja.sinSuscripcion => (
          'NO HAY NADA QUE DAR DE BAJA', // i18n: Fase W3
          'No encontramos una suscripción activa a tu nombre. Si creés que es '
              'un error, escribinos.', // i18n: Fase W3
          TreinoIcon.infoCircle,
        ),
      EstadoDeBaja.noDisponible => (
          'NO PUDIMOS CONFIRMARLO', // i18n: Fase W3
          'Mercado Pago no respondió. **Tu suscripción sigue como estaba** — no '
              'se dio de baja. Probá de nuevo en unos minutos.', // i18n: Fase W3
          TreinoIcon.warning,
        ),
    };

    return [
      Row(
        children: [
          Icon(
            icono,
            size: 18,
            color: r.estado == EstadoDeBaja.noDisponible
                ? palette.warning
                : palette.accent,
          ),
          const SizedBox(width: AppSpacing.s8),
          Expanded(
            child: Text(
              titulo,
              style: GoogleFonts.barlowCondensed(
                color: palette.textPrimary,
                fontSize: AppTextSize.title,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.s12),
      Text(
        cuerpo.replaceAll('**', ''),
        style: TextStyle(
          color: palette.textMuted,
          fontSize: AppTextSize.bodyDense,
          height: 1.5,
        ),
      ),
      const SizedBox(height: AppSpacing.s20),
      Align(
        alignment: Alignment.centerRight,
        child: _Boton(
          palette: palette,
          etiqueta: 'ENTENDIDO', // i18n: Fase W3
          primario: true,
          onTap: () => Navigator.of(context).pop(),
        ),
      ),
    ];
  }

  /// `dd/mm/aaaa`. Sin `intl` a propósito: una fecha corta no justifica cargar
  /// el locale, y el formato argentino es el único que se muestra.
  String _fecha(DateTime d) {
    final l = d.toLocal();
    final dd = l.day.toString().padLeft(2, '0');
    final mm = l.month.toString().padLeft(2, '0');
    return '$dd/$mm/${l.year}';
  }
}

class _Punto extends StatelessWidget {
  const _Punto({
    required this.palette,
    required this.icono,
    required this.texto,
    this.destacado = false,
  });

  final AppPalette palette;
  final IconData icono;
  final String texto;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 16, color: palette.accent),
        const SizedBox(width: AppSpacing.s8),
        Expanded(
          child: Text(
            texto,
            style: TextStyle(
              color: destacado ? palette.textPrimary : palette.textMuted,
              fontSize: AppTextSize.bodyDense,
              height: 1.5,
              fontWeight: destacado ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

class _Acciones extends StatelessWidget {
  const _Acciones({
    required this.palette,
    required this.enviando,
    required this.onConfirmar,
  });

  final AppPalette palette;
  final bool enviando;
  final Future<void> Function() onConfirmar;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _Boton(
          palette: palette,
          etiqueta: 'VOLVER', // i18n: Fase W3
          onTap: enviando ? null : () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: AppSpacing.s12),
        _Boton(
          palette: palette,
          etiqueta: enviando
              ? 'DANDO DE BAJA…' // i18n: Fase W3
              : 'DAR DE BAJA', // i18n: Fase W3
          destructivo: true,
          onTap: enviando ? null : onConfirmar,
        ),
      ],
    );
  }
}

class _Boton extends StatelessWidget {
  const _Boton({
    required this.palette,
    required this.etiqueta,
    required this.onTap,
    this.primario = false,
    this.destructivo = false,
  });

  final AppPalette palette;
  final String etiqueta;
  final VoidCallback? onTap;
  final bool primario;
  final bool destructivo;

  @override
  Widget build(BuildContext context) {
    final color = destructivo ? palette.danger : palette.accent;
    final apagado = onTap == null;

    return Semantics(
      button: true,
      enabled: !apagado,
      label: etiqueta,
      child: TreinoTappable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s18,
            vertical: AppSpacing.s8,
          ),
          decoration: BoxDecoration(
            color: primario ? color : null,
            border: Border.all(color: apagado ? palette.textMuted : color),
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
          child: Text(
            etiqueta,
            style: GoogleFonts.barlowCondensed(
              // Sobre el acento va el token de foreground, NO `palette.bg`: en
              // el tema claro ese par da 1.57:1 (AGENTS.md regla 2).
              color: primario
                  ? TreinoButtonTokens.foreground(context)
                  : (apagado ? palette.textMuted : color),
              fontSize: AppTextSize.caption,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
    );
  }
}
