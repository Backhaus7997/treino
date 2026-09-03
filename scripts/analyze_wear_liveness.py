#!/usr/bin/env python3
"""Analiza el log del spike instrumentado. Distingue CAUSAS, no solo sintomas.

Metricas por corrida:
  callbacks   = invocaciones reales del callback (n)
  tick        = tiempo logico segun el scheduler de Dart
  skipped     = tick - n  -> callbacks que Dart se salteo
  suspend     = boot - uptime -> crecimiento = suspension REAL del SoC
  rest        = ms restantes segun el deadline nativo
"""
import re
import sys

T = re.compile(
    r'\[LIVE\] n=(\d+) tick=(\d+) skipped=(-?\d+) '
    r'boot=(-?\d+) uptime=(-?\d+) wall=(-?\d+) suspend=(-?\d+) rest=(-?\d+)')
L = re.compile(r'\[LIVE\] lifecycle=(\S+) n=(\d+)')
F = re.compile(r'\[LIVE\] fgs=(.*)')

rows, life, fgs = [], [], None
for raw in open(sys.argv[1], 'rb').read().replace(b'\r', b'\n').split(b'\n'):
    s = raw.decode('utf-8', 'replace')
    m = T.search(s)
    if m:
        rows.append(tuple(int(x) for x in m.groups()))
        continue
    m = L.search(s)
    if m:
        life.append((m.group(1), int(m.group(2))))
        continue
    m = F.search(s)
    if m and fgs is None:
        fgs = m.group(1)

if not rows:
    print("sin muestras")
    sys.exit(1)

n, tick, skipped, boot, uptime, wall, suspend, rest = rows[-1]
print(f"FGS: {fgs}")
print(f"muestras: {len(rows)}   ventana: {boot/1000:.1f} s de reloj BOOTTIME\n")

print(f"  callbacks ejecutados : {n}")
print(f"  tiempo logico (tick) : {tick}")
print(f"  SALTEADOS (tick - n) : {skipped}")
print(f"  suspend (boot-uptime): {suspend} ms")
print(f"  wall - boot          : {wall - boot} ms   (salto de hora, no suspension)")
print(f"  descanso restante    : {rest/1000:.1f} s\n")

if life:
    print("ciclo de vida:")
    for st, at in life:
        print(f"    n={at:5d}  {st}")
    print()

# Huecos: mas de 2 s de BOOTTIME entre callbacks consecutivos.
print("huecos (> 2 s de BOOTTIME entre callbacks):")
gaps = []
for a, b in zip(rows, rows[1:]):
    db, du = b[3] - a[3], b[4] - a[4]
    if db > 2000:
        gaps.append((a[0], b[0], db, du))
        causa = "SUSPENSION del SoC" if (db - du) > 500 else "proceso vivo pero hambreado"
        print(f"    n={a[0]}->{b[0]}  boot +{db/1000:6.1f}s  uptime +{du/1000:6.1f}s  -> {causa}")
if not gaps:
    print("    NINGUNO")

# El criterio correcto es COBERTURA DEL TIEMPO DESPIERTO, no del tiempo de pared.
#
# La primera version comparaba callbacks contra `boot` (tiempo de pared) y daba
# ROJO sobre corridas sanas. Estaba mal, y se descubrio midiendo en hardware:
# durante suspend-to-RAM el SoC no ejecuta codigo de NADIE, asi que contar ese
# tiempo como "perdido por la app" culpa a la app de algo que no puede evitar
# (salvo tomando un wakelock, que Google pide explicitamente NO hacer en
# entrenos largos).
#
# Lo que la app SI controla es ejecutar un callback por cada segundo que el
# procesador estuvo despierto. Eso es `uptime`, o sea CLOCK_MONOTONIC.
#
# Medido en un Samsung SM-L500 (Wear OS 6), muneca baja, ~500 s:
#   sin foreground service: 108 callbacks en 492.3 s despierto ->  21.9%
#   con foreground service: 456 callbacks en 456.5 s despierto ->  99.9%
despierto_s = uptime / 1000
cobertura = (n / despierto_s * 100) if despierto_s > 0 else 0
suspendido_s = suspend / 1000

print(f"\nSoC despierto : {despierto_s:6.1f} s   -> {n} callbacks = {cobertura:.1f}% de cobertura")
print(f"SoC suspendido: {suspendido_s:6.1f} s   -> nadie ejecuta codigo aca, no es culpa de la app")
print("\nVEREDICTO: ", end="")
if cobertura >= 98 and skipped <= 2:
    print(f"VERDE — {cobertura:.1f}% del tiempo despierto cubierto, {skipped} callbacks salteados.")
elif cobertura >= 98:
    print(f"AMARILLO — cobertura {cobertura:.1f}% pero {skipped} callbacks salteados: revisar.")
else:
    print(f"ROJO — solo {cobertura:.1f}% del tiempo DESPIERTO cubierto "
          f"({skipped} callbacks salteados). La app se esta muriendo estando el SoC activo.")
