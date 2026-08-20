package com.treino.app.workout

import android.content.Context
import android.os.SystemClock

/**
 * Persistencia del descanso en curso.
 *
 * ## Por qué existe
 *
 * Un deadline guardado sólo en memoria sobrevive a que la app deje de tickear,
 * pero NO a que el proceso muera. Y "el proceso muere" es exactamente el caso
 * que separa este diseño del contador de ticks de watchOS: si el keep-alive
 * bastara, no haría falta el deadline. Sin persistir, el deadline es un contador
 * de ticks con pasos extra.
 *
 * En Android el kill del proceso NO es hipotético: los power managers de los
 * OEM matan apps sin previo aviso y sin callback de lifecycle, y varía por
 * marca. Ésa es la diferencia de entorno con watchOS que hace que copiar el
 * diseño de allá sea heredar una fragilidad multiplicada.
 *
 * ## El reloj y el reboot
 *
 * Se persiste el instante de fin en el reloj de [SystemClock.elapsedRealtime],
 * que es monotónico Y sobrevive a la suspensión. Pero cuenta desde el BOOT: al
 * reiniciarse el reloj vuelve a cero, y un deadline guardado queda apuntando a
 * un futuro imposible.
 *
 * Se detecta con [RestDeadline.isSaneAt]: si falta más de lo que duraba el
 * descanso entero, hubo reboot en el medio y el descanso se descarta. El caso
 * es real — un atleta que se queda sin batería a mitad del entreno volvería con
 * un descanso de "faltan 4 horas".
 *
 * Se guarda además [KEY_BOOT_ID] como segunda defensa: dos reboots muy rápidos
 * podrían dejar un `elapsedRealtime` pequeño que pase el chequeo de sanidad.
 */
class RestStore(
    context: Context,
    /**
     * Archivo de preferencias donde vive el deadline.
     *
     * Se parametriza para que el temporizador de EJERCICIO POR TIEMPO pueda
     * reusar toda esta maquinaria —deadline persistido, defensa contra reboot,
     * borrado de basura— sin compartir estado con el descanso. Son dos
     * temporizadores distintos y guardarlos en el mismo lugar haria que arrancar
     * uno cancelara el otro en silencio.
     *
     * El default conserva el nombre historico: cambiarlo dejaria huerfano el
     * descanso persistido de una instalacion que se actualiza en el medio.
     */
    prefsName: String = PREFS_REST,
) {

    companion object {
        /** El descanso entre series. */
        const val PREFS_REST = "treino_rest"

        /** El ejercicio por tiempo. */
        const val PREFS_EXERCISE = "treino_exercise_timer"
        private const val KEY_ENDS_AT = "endsAtElapsedMs"
        private const val KEY_TOTAL = "totalMs"

        /**
         * Marca de arranque del sistema, en WALL CLOCK: `ahora - elapsedRealtime()`.
         * Se mantiene estable entre lecturas dentro del mismo boot y cambia con
         * cada reinicio, así que sirve de identificador de boot sin permisos.
         */
        private const val KEY_BOOT_ID = "bootId"

        /** Tolerancia del boot id: el wall clock deriva y puede saltar con NTP. */
        private const val BOOT_ID_TOLERANCE_MS = 10_000L
    }

    private val prefs = context.getSharedPreferences(prefsName, Context.MODE_PRIVATE)

    private fun currentBootId(): Long =
        System.currentTimeMillis() - SystemClock.elapsedRealtime()

    fun save(deadline: RestDeadline) {
        prefs.edit()
            .putLong(KEY_ENDS_AT, deadline.endsAtElapsedMs)
            .putLong(KEY_TOTAL, deadline.totalMs)
            .putLong(KEY_BOOT_ID, currentBootId())
            .apply()
    }

    fun clear() {
        prefs.edit().clear().apply()
    }

    /**
     * Devuelve el descanso guardado, o null si no hay o si dejó de tener sentido.
     *
     * Un descuadre lo BORRA además de devolver null: dejar basura persistida es
     * lo que hace que el bug vuelva tres pantallas después.
     */
    fun load(nowElapsedMs: Long): RestDeadline? {
        if (!prefs.contains(KEY_ENDS_AT)) return null

        val savedBootId = prefs.getLong(KEY_BOOT_ID, Long.MIN_VALUE)
        if (kotlin.math.abs(currentBootId() - savedBootId) > BOOT_ID_TOLERANCE_MS) {
            clear()
            return null
        }

        val d = RestDeadline(
            endsAtElapsedMs = prefs.getLong(KEY_ENDS_AT, 0L),
            totalMs = prefs.getLong(KEY_TOTAL, 0L),
        )
        if (!d.isSaneAt(nowElapsedMs)) {
            clear()
            return null
        }
        return d
    }
}
