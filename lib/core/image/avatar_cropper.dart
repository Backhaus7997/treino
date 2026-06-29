import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';

import '../../app/theme/app_palette.dart';
import '../../l10n/app_l10n.dart';

/// Wrapper centralizado del `image_cropper` para el flujo de foto de perfil.
///
/// Toma el `sourcePath` (típicamente el `XFile.path` que devuelve
/// `image_picker`), abre la UI de recorte con viewport CIRCULAR y aspect ratio
/// CUADRADO FIJO (decisión 2026-06-29: foto de perfil siempre va a un círculo,
/// dar libertad de aspect ratio no aporta), y devuelve el path del archivo
/// recortado o `null` si el usuario cancela.
///
/// El user NUNCA debe instanciar `ImageCropper()` directamente — usar siempre
/// este helper así las opciones (toolbar color, locked aspect ratio, copy)
/// quedan consistentes entre las 3 surfaces que pickean avatar:
///   - `profile_edit_personal_screen` (editar perfil mobile)
///   - `profile_setup/step_1_username_avatar` (onboarding inicial)
///   - `coach_hub/.../avatar_web_uploader` (Coach Hub web)
class AvatarCropper {
  AvatarCropper({ImageCropper? cropper}) : _cropper = cropper ?? ImageCropper();

  final ImageCropper _cropper;

  /// Returns the path of the cropped square image, or `null` if the user
  /// cancelled the crop UI. The original `sourcePath` is left untouched —
  /// callers can fall back to it on a `null` return if they want to.
  Future<String?> cropToSquare({
    required String sourcePath,
    required BuildContext context,
  }) async {
    final l10n = AppL10n.of(context);
    final palette = AppPalette.of(context);

    final cropped = await _cropper.cropImage(
      sourcePath: sourcePath,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 85,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: l10n.avatarCropperTitle,
          toolbarColor: palette.bg,
          toolbarWidgetColor: palette.textPrimary,
          activeControlsWidgetColor: palette.accent,
          backgroundColor: palette.bg,
          // Square is the only valid aspect for a circular profile preview.
          lockAspectRatio: true,
          initAspectRatio: CropAspectRatioPreset.square,
          aspectRatioPresets: const [CropAspectRatioPreset.square],
          hideBottomControls: true,
        ),
        IOSUiSettings(
          title: l10n.avatarCropperTitle,
          doneButtonTitle: l10n.avatarCropperDone,
          cancelButtonTitle: l10n.avatarCropperCancel,
          // Circular preview overlay (the photo itself is still cropped to a
          // square JPG — Storage gets the square; the circular mask is purely
          // a UX hint matching the in-app avatar render).
          aspectRatioLockEnabled: true,
          aspectRatioPickerButtonHidden: true,
          resetAspectRatioEnabled: false,
          aspectRatioPresets: const [CropAspectRatioPreset.square],
        ),
        WebUiSettings(
          context: context,
          presentStyle: WebPresentStyle.dialog,
          size: const CropperSize(width: 480, height: 480),
          // Lock the crop box to a 1:1 ratio so the user can only pan/zoom
          // — they cannot resize it into a non-square shape.
          initialAspectRatio: 1,
          cropBoxResizable: false,
          dragMode: WebDragMode.move,
          zoomable: true,
          translations: WebTranslations(
            title: l10n.avatarCropperTitle,
            // Rotation buttons aren't shown in our flow, but the package
            // requires non-empty tooltip strings.
            rotateLeftTooltip: l10n.avatarCropperTitle,
            rotateRightTooltip: l10n.avatarCropperTitle,
            cancelButton: l10n.avatarCropperCancel,
            cropButton: l10n.avatarCropperDone,
          ),
        ),
      ],
    );

    return cropped?.path;
  }
}
