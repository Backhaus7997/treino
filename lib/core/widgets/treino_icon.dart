import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Wrapper semántico sobre Phosphor para que la familia de íconos sea
/// intercambiable desde un solo archivo. Si mañana cambiamos a Material
/// Symbols, sólo se modifica esta clase.
class TreinoIcon {
  TreinoIcon._();

  // Tab bar
  // House con puerta (equivalente Phosphor del bootstrap house-fill).
  static const IconData tabHome = PhosphorIconsRegular.house;
  static const IconData tabHomeFill = PhosphorIconsFill.house;
  static const IconData tabWorkout = PhosphorIconsRegular.barbell;
  static const IconData tabWorkoutFill = PhosphorIconsFill.barbell;
  static const IconData tabFeed = PhosphorIconsRegular.newspaperClipping;
  static const IconData tabFeedFill = PhosphorIconsFill.newspaperClipping;
  static const IconData tabCoach = PhosphorIconsRegular.chalkboardTeacher;
  static const IconData tabCoachFill = PhosphorIconsFill.chalkboardTeacher;
  static const IconData tabProfile = PhosphorIconsRegular.user;
  static const IconData tabProfileFill = PhosphorIconsFill.user;

  // Esfuerzo medido por el reloj (change watch-workout-session, F4).
  //
  // Van aparte de `reactionLike` / `reactionFire` aunque compartan glifo: esos
  // son reacciones a un post del feed. Reusarlos acá ataría dos cosas que no
  // tienen nada que ver, y el día que el feed cambie de icono se llevaría
  // puesto el ritmo cardíaco.
  static const IconData heartRate = PhosphorIconsFill.heart;
  static const IconData calories = PhosphorIconsFill.flame;

  // Hero / acciones
  static const IconData streak = PhosphorIconsFill.flame;
  static const IconData play = PhosphorIconsFill.play;
  static const IconData pause = PhosphorIconsFill.pause;
  static const IconData sparkle = PhosphorIconsRegular.sparkle;
  static const IconData mapPin = PhosphorIconsRegular.mapPin;
  static const IconData bell = PhosphorIconsRegular.bell;

  /// Teléfono. Lo usa el companion de Wear OS para pedirle al atleta que abra
  /// TREINO en el celular: el reloj no puede hablar con Firestore hasta que el
  /// teléfono le mintee una credencial.
  static const IconData phone = PhosphorIconsRegular.deviceMobile;

  /// Rayo de atención — caja de ícono mint del alert banner del dashboard
  /// Coach Hub web (Fase 2, WU-02). Alias de [specialty] (mismo glyph
  /// `lightning`, distinto significado semántico según contexto de uso).
  static const IconData alertAttention = specialty;

  // Rankings (per-gym leaderboards — rachas/volumen/lifts).
  static const IconData ranking = PhosphorIconsRegular.trophy;

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

  // Métricas de sesión (resumen post-entreno). Alias semánticos: el ícono de
  // PR es un trofeo igual que [ranking], pero un récord personal no es un
  // ranking — nombrarlos distinto evita que el call site mienta.
  static const IconData statSets = PhosphorIconsRegular.rows;
  static const IconData statPr = PhosphorIconsRegular.trophy;

  // Comparación mes-a-mes (Monthly Report summary cards).
  static const IconData trendUp = PhosphorIconsRegular.trendUp;
  static const IconData trendDown = PhosphorIconsRegular.trendDown;

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
  static const IconData atSign = PhosphorIconsRegular.at;
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

  /// Agarre de arrastre (⠿). Distinto de [dotsThree] a propósito: el de tres
  /// puntos abre un menú, éste dice "podés arrastrarme". Usar el mismo glifo
  /// para las dos cosas —que es lo que pasaba en la card de ejercicio— deja al
  /// usuario sin forma de saber cuál hace qué.
  static const IconData dragHandle = PhosphorIconsRegular.dotsSixVertical;
  static const IconData verified = PhosphorIconsFill.sealCheck;
  static const IconData dumbbell = PhosphorIconsRegular.barbell;
  static const IconData chevronLeft = PhosphorIconsRegular.caretLeft;
  static const IconData chevronRight = PhosphorIconsRegular.caretRight;
  static const IconData chevronDown = PhosphorIconsRegular.caretDown;
  static const IconData chevronUp = PhosphorIconsRegular.caretUp;
  // Reacciones del feed. Cada una tiene su par contorno/relleno: el contorno
  // es el estado sin reaccionar y el relleno es la reacción propia, que además
  // se pinta con su color de AppPalette. Pintar solo el contorno no alcanza —
  // el ícono se lee como un borde de color, no como un emoji encendido.
  static const IconData reactionLike = PhosphorIconsRegular.heart;
  static const IconData reactionLikeFill = PhosphorIconsFill.heart;
  static const IconData reactionFire = PhosphorIconsRegular.flame;
  static const IconData reactionFireFill = PhosphorIconsFill.flame;
  static const IconData reactionClap = PhosphorIconsRegular.handsClapping;
  static const IconData reactionClapFill = PhosphorIconsFill.handsClapping;
  // Hamburger clásico (3 líneas) — toggle de sidebar/menú.
  static const IconData menu = PhosphorIconsRegular.list;

  // Gym / spaces
  static const IconData gym = PhosphorIconsRegular.buildings;

  // Session player
  static const IconData checkCircleFill = PhosphorIconsFill.checkCircle;
  static const IconData checkCircleEmpty = PhosphorIconsRegular.circle;

  /// Plain checkmark (no enclosing circle) — used for done-status indicators
  /// that should read as a status, not a pressable button.
  static const IconData checkBare = PhosphorIconsBold.check;

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
  static const IconData attach = PhosphorIconsRegular.paperclip;
  static const IconData image = PhosphorIconsRegular.image;
  static const IconData video = PhosphorIconsRegular.videoCamera;

  // Profile settings constant REMOVED 2026-05-28 — gear icon was removed from
  // ProfileHeader as part of the PR#4 pivot. Zero remaining usages.

  /// Ajustes de un CONTENIDO, no de la app.
  ///
  /// Deliberadamente NO es un engranaje: el de `ProfileHeader` se sacó del kit
  /// en 2026-05 y no conviene reintroducirlo con otro significado. Los faders
  /// dicen "parámetros de esto que estás editando", que es lo que abre la hoja
  /// "DATOS DEL PLAN".
  static const IconData contentSettings =
      PhosphorIconsRegular.slidersHorizontal;

  // Appearance / theme settings
  static const IconData appearance = PhosphorIconsRegular.sun;

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

  // Sidebar — Coach Hub Web (Fase W1). Aliases per ADR-CHW-007. Items que
  // reusan un alias existente apuntan a la const de esta clase para mantener
  // una sola fuente de verdad; el resto mapea a su variante phosphor.
  static const IconData sidebarDashboard = PhosphorIconsRegular.squaresFour;
  static const IconData sidebarActividad = bell;
  static const IconData sidebarAgenda = calendar;
  static const IconData sidebarAlumnos = users;
  static const IconData sidebarInvitaciones = mail;
  static const IconData sidebarCuestionario =
      PhosphorIconsRegular.clipboardText;
  static const IconData sidebarRutinas = dumbbell;
  static const IconData sidebarPlanner = PhosphorIconsRegular.calendarBlank;
  static const IconData sidebarBiblioteca = PhosphorIconsRegular.bookOpen;
  static const IconData sidebarTemplates = PhosphorIconsRegular.fileText;
  static const IconData sidebarNutricion = PhosphorIconsRegular.appleLogo;
  static const IconData sidebarRecetas = PhosphorIconsRegular.cookingPot;
  static const IconData sidebarSuplementos = PhosphorIconsRegular.pill;
  static const IconData sidebarHabitos = PhosphorIconsRegular.checkSquare;
  static const IconData sidebarPagos = PhosphorIconsRegular.creditCard;
  static const IconData sidebarPlanes = PhosphorIconsRegular.storefront;
  static const IconData sidebarReportes = PhosphorIconsRegular.chartLine;
  static const IconData sidebarChat = chat;
  static const IconData sidebarAjustes = PhosphorIconsRegular.gear;
  // Perfil público (Fase 11) — alias semántico de [globe] (misma familia
  // usada por Coach Discovery en mobile).
  static const IconData sidebarPerfilPublico = globe;

  // Alumno detail — Archivos tab (upload/download/trash/image ya existen arriba)
  static const IconData file = PhosphorIconsRegular.file;
  static const IconData filePdf = PhosphorIconsRegular.filePdf;

  // Coach Hub Web — Kit de componentes (Fase 1, EmptyState)
  static const IconData emptyState = PhosphorIconsRegular.empty;

  // Coach Hub Web — Kit de componentes (Fase 1, CoachHubDataTable)
  // Indicador de columna ordenada (ascendente/descendente); la rotación de
  // 180° la aplica el consumidor via AnimatedRotation sobre sortAscending.
  static const IconData sortAscending = PhosphorIconsRegular.sortAscending;
  // Indicador de columna ordenable sin orden activo (caret doble).
  static const IconData sortable = PhosphorIconsRegular.caretUpDown;
  // Ícono del estado de error (tabla, dialogs, etc.).
  static const IconData errorState = PhosphorIconsRegular.warningCircle;

  // Coach Hub — Alumnos roster view-mode toggle (Tabla / Cards).
  static const IconData viewTable = PhosphorIconsRegular.rows;
  static const IconData viewCards = PhosphorIconsRegular.squaresFour;
  // Coach Hub Web — acción archivar rutina (Fase 5, WU-04).
  static const IconData archive = PhosphorIconsRegular.archive;

  // Check-in de bienestar (#643) — la entrada del hub de Insights a la serie
  // subjetiva del atleta.
  //
  // Va aparte de `heartRate` y de las reacciones del feed aunque los tres sean
  // del mismo barrio semántico: heartRate es el esfuerzo que mide el reloj y
  // las reacciones son del feed. Reusar cualquiera de los dos ataría el
  // bienestar a algo que no tiene nada que ver, que es justo lo que el
  // comentario de heartRate ya pidió no hacer.
  static const IconData wellbeing = PhosphorIconsRegular.smiley;
}
