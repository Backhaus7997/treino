package com.treino.app.workout

/**
 * Lógica PURA del descanso. Sin Android, sin `SystemClock`, sin corrutinas:
 * el "ahora" entra siempre por parámetro. Se testea con JUnit, sin emulador.
 *
 * Existe separada del servicio por la misma razón por la que en watchOS
 * `WorkoutSessionLifecycle` (enum puro) vive aparte de `WorkoutSessionController`
 * (framework): la regla se puede verificar sin levantar un dispositivo.
 *
 * ## Por qué un deadline y no un contador
 *
 * El descanso de watchOS decrementa un contador por tick. Sobrevive únicamente
 * porque el proceso sigue vivo — si el sistema lo congela, la cuenta se atrasa
 * en silencio. En Android los kills agresivos son mucho más comunes, así que
 * copiar ese diseño es heredar la fragilidad y multiplicarla.
 *
 * Acá el descanso es un INSTANTE FUTURO. Cuántos ticks corrieron no importa: lo
 * que queda se deriva restando. Si la app no corrió un solo tick durante todo el
 * descanso, al volver muestra el número correcto igual.
 *
 * ## Qué reloj, y por qué NO los dos obvios
 *
 * | reloj | sobrevive suspensión | monotónico | |
 * |---|---|---|---|
 * | `Stopwatch` de Dart → `CLOCK_MONOTONIC` | NO, se congela | sí | inservible |
 * | `DateTime.now()` → wall clock | sí | NO, salta con NTP | sólo timestamps |
 * | `SystemClock.elapsedRealtime()` → `CLOCK_BOOTTIME` | sí | sí | **éste** |
 *
 * Android lo dice textual sobre `elapsedRealtime()`: "is guaranteed to be
 * monotonic, and continues to tick even when the CPU is in power saving modes,
 * so is the recommended basis for general purpose interval timing".
 *
 * Todos los `elapsedMs` de este archivo son de ESE reloj.
 */
data class RestDeadline(
    /** Instante de fin, en el reloj de `SystemClock.elapsedRealtime()`. */
    val endsAtElapsedMs: Long,
    /** Duración pedida. Se guarda para poder detectar un reboot (ver [isSaneAt]). */
    val totalMs: Long,
) {
    /**
     * Milisegundos que faltan. Nunca negativo: una vez vencido, es 0.
     *
     * No se satura hacia arriba a propósito — si [nowElapsedMs] viene de antes
     * del arranque del descanso, devolver [totalMs] escondería el bug.
     */
    fun remainingMsAt(nowElapsedMs: Long): Long =
        (endsAtElapsedMs - nowElapsedMs).coerceAtLeast(0L)

    fun isFinishedAt(nowElapsedMs: Long): Boolean = nowElapsedMs >= endsAtElapsedMs

    /**
     * Si el deadline sigue teniendo sentido con el "ahora" que llega.
     *
     * `elapsedRealtime()` cuenta desde el BOOT, así que un reinicio del reloj lo
     * manda de vuelta a cero y un deadline persistido queda apuntando a un
     * futuro imposible. Se detecta así: si falta MÁS de lo que duraba el
     * descanso entero, el reloj se reinició en el medio.
     *
     * El caso importa de verdad: un atleta con el reloj sin batería a mitad del
     * entreno vuelve con un descanso que "faltan 4 horas". Preferible descartarlo
     * y arrancar limpio.
     */
    fun isSaneAt(nowElapsedMs: Long): Boolean =
        remainingMsAt(nowElapsedMs) <= totalMs

    companion object {
        /** Arranca un descanso de [durationMs] a partir de [nowElapsedMs]. */
        fun startingAt(nowElapsedMs: Long, durationMs: Long): RestDeadline =
            RestDeadline(endsAtElapsedMs = nowElapsedMs + durationMs, totalMs = durationMs)
    }
}
