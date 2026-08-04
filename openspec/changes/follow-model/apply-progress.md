# Apply progress — `follow-model`

> Registro de ejecución del plan. Se actualiza a medida que avanzan los PRs.
> **No se anotan uids ni contenido de documentos**: los datos crudos viven solo
> en los dumps de `functions/scripts/migrations/`, que están gitignoreados.

---

## PR 0 — Backup y gate de volumen (M-00, M-01) ✅

**Commit**: `e8b4020d` · **Fecha**: 2026-08-04

| Tarea | Estado |
|---|---|
| 0.1 [RED] test de `buildSnapshotPayload` | ✅ 8 casos |
| 0.2 [GREEN] `export-friendships-snapshot.ts` | ✅ |
| 0.3 [GATE] jest verde | ✅ 8/8 · `tsc` limpio |
| 0.4 [MANUAL] correr contra `treino-dev` real | ✅ ver abajo |
| 0.5 [MANUAL] evidencia de M-00 / Rama A | ✅ ver abajo |

### M-00 — Gate de volumen (evidencia, 2026-08-04T15:13:08Z)

```
friendships.count() = 6
```

Desglose del dump (agregados, sin identidades):

| Métrica | Valor |
|---|---|
| Documentos totales | **6** |
| `status: accepted` | 4 |
| `status: pending` | 2 |
| Malformados | **0** |
| uids distintos involucrados | 8 |

**Rama A CONFIRMADA con evidencia.** El dueño ya la había fijado por decisión
(2026-08-04: los uids son del equipo y de testers conocidos); el conteo la
sostiene: 6 relaciones entre 8 personas es exactamente el orden de magnitud de
un equipo de 3 más testers de TestFlight. No hay usuarios de afuera. Queda firme
LD-03 (cutover sin dual-write) y no se activa la Rama B de ADR-FOLLOW-010.

Cero documentos malformados: la guarda de exclusión del `--apply` (M-02) no va a
descartar nada en esta corrida, y la fórmula de cardinalidad —que distingue
bien formados de malformados— colapsa al caso simple.

### M-01 — Snapshot

```
functions/scripts/migrations/friendships-snapshot-2026-08-04T15-13-08-855Z.json
```

3579 bytes · 6 documentos · `count` declarado coincide con `docs.length` ·
verificado que **no aparece en `git status`** (ignorado por la regla
`functions/scripts/migrations/` agregada en el mismo commit).

⚠️ **Este archivo es el único mecanismo de reversibilidad de toda la migración.**
Vive fuera del repo a propósito, porque contiene el grafo social con uids reales.
Antes de correr M-04 hay que asegurarse de que exista una copia fuera de esta
máquina — si se pierde el disco, se pierde la posibilidad de revertir.

### Proyección para la verificación posterior

Con 4 `accepted` y 2 `pending`, y la regla de LD-06 (dos aristas por accepted,
una por pending):

```
aristas esperadas = 2 × 4 + 2 = 10
M-06 ① : count(follows) == 10
```

Ese número es la aserción concreta que tiene que dar la verificación después de
M-04. Cualquier otro valor significa que se perdió, se duplicó o se inventó una
relación.

---

## Pendiente

- **PR 1** — modelo `Follow` inerte (dominio + data + providers + rules aditivas
  + índices). Base: PR0.
- Copy del aviso de chat bloqueado (única decisión abierta del proposal, se
  cierra con el resto de los ARBs en PR4).
