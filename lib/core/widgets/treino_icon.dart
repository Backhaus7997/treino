import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Wrapper semántico sobre Phosphor para que la familia de íconos sea
/// intercambiable desde un solo archivo. Si mañana cambiamos a Material
/// Symbols, sólo se modifica esta clase.
class TreinoIcon {
  TreinoIcon._();

  // Tab bar
  static const IconData tabHome = PhosphorIconsRegular.houseSimple;
  static const IconData tabHomeFill = PhosphorIconsFill.houseSimple;
  static const IconData tabWorkout = PhosphorIconsRegular.barbell;
  static const IconData tabWorkoutFill = PhosphorIconsFill.barbell;
  static const IconData tabFeed = PhosphorIconsRegular.newspaperClipping;
  static const IconData tabFeedFill = PhosphorIconsFill.newspaperClipping;
  static const IconData tabCoach = PhosphorIconsRegular.chalkboardTeacher;
  static const IconData tabCoachFill = PhosphorIconsFill.chalkboardTeacher;
  static const IconData tabProfile = PhosphorIconsRegular.user;
  static const IconData tabProfileFill = PhosphorIconsFill.user;

  // Hero / acciones
  static const IconData streak = PhosphorIconsFill.flame;
  static const IconData play = PhosphorIconsFill.play;
  static const IconData pause = PhosphorIconsFill.pause;
  static const IconData sparkle = PhosphorIconsRegular.sparkle;
  static const IconData mapPin = PhosphorIconsRegular.mapPin;
  static const IconData bell = PhosphorIconsRegular.bell;

  // Navegación
  static const IconData back = PhosphorIconsRegular.caretLeft;
  static const IconData forward = PhosphorIconsRegular.caretRight;
  static const IconData close = PhosphorIconsRegular.x;
  static const IconData search = PhosphorIconsRegular.magnifyingGlass;

  // Stats / tiempo
  static const IconData chartBar = PhosphorIconsRegular.chartBar;
  static const IconData calendar = PhosphorIconsRegular.calendarCheck;
  static const IconData clock = PhosphorIconsRegular.clock;

  // Acciones de usuario
  static const IconData chat = PhosphorIconsRegular.chatCircle;
  static const IconData check = PhosphorIconsFill.checkCircle;
  static const IconData edit = PhosphorIconsRegular.pencilSimple;
  static const IconData trash = PhosphorIconsRegular.trashSimple;
  static const IconData signOut = PhosphorIconsRegular.signOut;
  static const IconData users = PhosphorIconsRegular.usersThree;
  static const IconData globe = PhosphorIconsRegular.globe;

  // Auth
  static const IconData lock = PhosphorIconsRegular.lock;
  static const IconData mail = PhosphorIconsRegular.envelope;
  static const IconData eye = PhosphorIconsRegular.eye;
  static const IconData eyeOff = PhosphorIconsRegular.eyeSlash;
}
