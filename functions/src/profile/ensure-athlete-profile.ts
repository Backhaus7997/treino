/**
 * ensure-athlete-profile.ts — crea el perfil de un alumno que se dio de alta
 * desde la WEB.
 *
 * ── Por que esto tiene que existir del lado del servidor ──
 *
 * La landing (`gettreino.com`, repo `treino-app`) no toca Firestore y no deberia
 * empezar a hacerlo. El alta de un usuario en TREINO **no es escribir un
 * documento**: es un dual-write atomico a `users/{uid}` y a
 * `userPublicProfiles/{uid}` en el mismo batch, y hacer sólo el primero es un
 * bug conocido y caro.
 *
 * Lo documenta `lib/features/profile/data/user_repository.dart:101-114`, y vale
 * la pena citarlo porque el modo de falla no es obvio:
 *
 * > «las cuentas cuyo doc de `users` es anterior al dual-write nunca tuvieron
 * > doc publico — su submit de ProfileSetup pegaba contra un merge-as-create en
 * > `userPublicProfiles` y era denegado → permission-denied → rollback del
 * > batch → el atleta quedaba VARADO en la pantalla de onboarding.»
 *
 * O sea: un alta a medias no falla al crearse. Falla despues, cuando la persona
 * abre la app por primera vez, y la deja sin poder entrar.
 *
 * Reimplementar ese batch en TypeScript, en otro repositorio, sin ningun gate
 * de sincronismo, es reproducir ese bug a plazo. Por eso el alta web pasa por
 * acá: un callable, con Admin SDK, que hace exactamente lo mismo que el cliente
 * Flutter.
 *
 * ── Idempotente a proposito ──
 *
 * Se llama despues de TODO login exitoso, no sólo del alta. Cuesta una lectura
 * y cubre al usuario legacy cuyo `users/{uid}` existe pero nunca tuvo doc
 * publico — que es exactamente la poblacion del bug de arriba.
 *
 * ── Lo que NO hace, y es deliberado ──
 *
 * No escribe `displayName`. El alta nace con `displayName: null` igual que
 * `createIfAbsent` del cliente, y el nombre lo pone ProfileSetup la primera vez
 * que la persona abre la app. Inventar uno desde el mail seria peor que
 * ninguno: queda pegado y nadie lo corrige.
 *
 * No escribe `role` distinto de `athlete`. El signup publico SIEMPRE crea
 * `athlete` (AGENTS.md regla 3, y `firestore.rules` lo fuerza para el cliente);
 * el Admin SDK se saltea las reglas, asi que la garantia acá tiene que ser del
 * codigo. Esta escrito literal y no parametrizado: un `role` que viniera del
 * request seria escalacion de privilegios directa, y el update pinea `role`
 * inmutable — o sea que seria PERMANENTE.
 */

import { App, getApp, initializeApp } from "firebase-admin/app";
import { Timestamp, getFirestore } from "firebase-admin/firestore";
import * as functions from "firebase-functions/v2/https";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions";

export const USERS_COLLECTION = "users";
export const USER_PUBLIC_PROFILES_COLLECTION = "userPublicProfiles";

export interface EnsureAthleteProfileResult {
  /** `true` cuando se creo el documento de usuario en esta llamada. */
  created: boolean;
  /**
   * `true` cuando se creo el doc PUBLICO sobre un `users/{uid}` que ya existia.
   *
   * Es el backfill del bug de arriba, y se reporta aparte de `created` porque
   * es un caso distinto: una cuenta vieja que estaba rota y se arreglo. Verlo
   * en los logs dice cuanta de esa poblacion queda.
   */
  backfilled: boolean;
}

export interface EnsureAthleteProfileDeps {
  /** Reloj inyectable: las fechas del documento se testean sin mockear Date. */
  nowMs: number;
}

function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}

/**
 * El handler. Recibe el `uid` y el `email` YA extraidos del token: ninguno de
 * los dos puede venir del body.
 *
 * El email es el del token y no el del request por el mismo motivo que el uid:
 * si viajara, cualquiera podria crear una cuenta a nombre del mail de otro, y
 * el documento de usuario es lo que despues resuelve a quien pertenece un
 * vinculo con un entrenador.
 */
export async function runEnsureAthleteProfile(
  app: App,
  uid: string,
  email: string,
  deps: EnsureAthleteProfileDeps,
): Promise<EnsureAthleteProfileResult> {
  const db = getFirestore(app);
  const userRef = db.collection(USERS_COLLECTION).doc(uid);
  const publicRef = db.collection(USER_PUBLIC_PROFILES_COLLECTION).doc(uid);

  const [userSnap, publicSnap] = await Promise.all([
    userRef.get(),
    publicRef.get(),
  ]);

  if (userSnap.exists && publicSnap.exists) return {
    created: false,
    backfilled: false,
  };

  const ahora = Timestamp.fromMillis(deps.nowMs);
  const batch = db.batch();

  if (!userSnap.exists) {
    batch.set(
      userRef,
      {
        uid,
        email,
        // `null` explicito y no ausente: espeja lo que escribe el cliente
        // Flutter (`createIfAbsent`), y ProfileSetup lo completa despues.
        displayName: null,
        // LITERAL. Ver el encabezado: parametrizarlo seria escalacion de
        // privilegios, y el update pinea `role` inmutable — o sea permanente.
        role: "athlete",
        createdAt: ahora,
        updatedAt: ahora,
      },
      // `merge` aunque el doc no exista: hace que una carrera entre dos
      // llamadas simultaneas —dos pestañas, un doble click— no pise nada.
      { merge: true },
    );
  }

  // El subset publico, espejo de `_publicSubsetFromProfile`
  // (`user_repository.dart:91-99`). `uid` va SIEMPRE: la regla de CREATE de
  // `userPublicProfiles` exige `request.resource.data.uid == uid`, y sin el un
  // merge-as-create es denegado. Con `merge`, reescribirlo sobre un doc que ya
  // existe es un no-op.
  batch.set(
    publicRef,
    {
      uid,
      displayName: null,
      displayNameLowercase: null,
      avatarUrl: null,
      gymId: null,
    },
    { merge: true },
  );

  await batch.commit();

  const resultado = {
    created: !userSnap.exists,
    backfilled: userSnap.exists && !publicSnap.exists,
  };

  logger.info("profile/ensure-athlete: alta desde la web", { uid, ...resultado });

  return resultado;
}

export const ensureAthleteProfile = functions.onCall(
  // SIN enforceAppCheck, por el mismo motivo de plataforma que el resto del
  // flujo web: la landing no lo activa. La cerradura es que NO HAY BODY — el
  // uid y el mail salen del token y no se puede escribir nada a nombre de otro.
  { region: "southamerica-east1" },
  async (request): Promise<EnsureAthleteProfileResult> => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "hay que estar logueado");
    }
    // El mail puede faltar: un login con Apple y relay oculto puede no traerlo
    // en el token si el usuario lo escondio. Se acepta vacio en vez de fallar —
    // la cuenta tiene que poder existir igual, y el mail no es lo que la
    // identifica.
    const email = request.auth?.token?.email ?? "";
    return runEnsureAthleteProfile(ensureApp(), uid, String(email), {
      nowMs: Date.now(),
    });
  },
);
