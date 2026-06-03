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
  static const IconData timer = PhosphorIconsRegular.timer;

  // Acciones de usuario
  static const IconData chat = PhosphorIconsRegular.chatCircle;
  static const IconData check = PhosphorIconsFill.checkCircle;
  static const IconData copy = PhosphorIconsRegular.copy;
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

  // Social / third-party
  static const IconData googleLogo = PhosphorIconsRegular.googleLogo;
  static const IconData appleLogo = PhosphorIconsRegular.appleLogo;

  // Directional
  static const IconData arrowRight = PhosphorIconsRegular.arrowRight;

  // Security / trust
  static const IconData shieldCheck = PhosphorIconsRegular.shieldCheck;

  // Info
  static const IconData infoCircle = PhosphorIconsRegular.info;

  // ProfileSetup
  static const IconData plus = PhosphorIconsRegular.plus;
  static const IconData ruler = PhosphorIconsRegular.ruler;
  static const IconData scales = PhosphorIconsRegular.scales;

  // Feed / social
  static const IconData dotsThree = PhosphorIconsRegular.dotsThreeVertical;
  static const IconData verified = PhosphorIconsFill.sealCheck;
  static const IconData dumbbell = PhosphorIconsRegular.barbell;
  static const IconData chevronLeft = PhosphorIconsRegular.caretLeft;
  static const IconData chevronRight = PhosphorIconsRegular.caretRight;
  static const IconData chevronDown = PhosphorIconsRegular.caretDown;
  static const IconData chevronUp = PhosphorIconsRegular.caretUp;

  // Gym / spaces
  static const IconData gym = PhosphorIconsRegular.buildings;

  // Session player
  static const IconData checkCircleFill = PhosphorIconsFill.checkCircle;
  static const IconData checkCircleEmpty = PhosphorIconsRegular.circle;

  // Coach discovery
  static const IconData specialty = PhosphorIconsRegular.lightning;
  static const IconData money = PhosphorIconsRegular.currencyDollar;
  static const IconData star = PhosphorIconsRegular.star;
  static const IconData mapToggle = PhosphorIconsRegular.mapTrifold;

  // Reviews — star rating input/display. Fase 6 Etapa 7.
  static const IconData starFill = PhosphorIconsFill.star;
  static const IconData starOutline = PhosphorIconsRegular.star;

  // Chat
  static const IconData send = PhosphorIconsFill.paperPlaneTilt;
  static const IconData chatEmpty = PhosphorIconsRegular.chatsCircle;

  // Profile settings constant REMOVED 2026-05-28 — gear icon was removed from
  // ProfileHeader as part of the PR#4 pivot. Zero remaining usages.

  // Coach Hub (web) — import flow
  static const IconData arrowLeft = PhosphorIconsRegular.arrowLeft;
  static const IconData download = PhosphorIconsRegular.downloadSimple;
  static const IconData upload = PhosphorIconsRegular.uploadSimple;
  static const IconData fileXls = PhosphorIconsRegular.fileXls;
  static const IconData warning = PhosphorIconsRegular.warning;

  // Equipment filter aliases (T-RER-016) — used by EquipmentFilterSheet.
  // equipDumbbell and equipBarbell both alias barbell because Phosphor has no
  // distinct dumbbell glyph; the row label ("Mancuerna" vs "Barra") disambiguates.
  static const IconData equipDumbbell = PhosphorIconsRegular.barbell;
  static const IconData equipBarbell = PhosphorIconsRegular.barbell;
  static const IconData equipMachine = PhosphorIconsRegular.gearSix;
  static const IconData equipCable = PhosphorIconsRegular.lightning;
  static const IconData equipBand = PhosphorIconsRegular.waveTriangle;
  static const IconData equipBodyweight = PhosphorIconsRegular.personSimple;
  static const IconData equipCardio = PhosphorIconsRegular.heartbeat;
  static const IconData equipOther = PhosphorIconsRegular.shapes;
  static const IconData equipNone = PhosphorIconsRegular.minus;
}
