# Brief de copy para las fichas de store

Los archivos de `metadata/` están **vacíos a propósito**. Este documento es la
lista exacta de lo que hay que escribir, con su límite y sus restricciones, para
que quien escriba el copy no tenga que ir a buscar nada.

Los límites verificados y sus fuentes están en [`README.md`](./README.md) §1.

---

## Reglas que aplican a todo el copy

**Naming** (AGENTS.md §1 · `docs/product.md`) — esto no es negociable, es lo que
más fácil se rompe en texto de marketing:

- **TREINO** es la marca. Va en mayúsculas.
- **Coach** es el módulo del PF. No decirle "TREINO" al módulo.
- **Entreno IA** es el feature de IA. **Nunca** "Coach IA".

**Tono** (`docs/product.md`):

- Voseo rioplatense: *entrená*, *empezá*, *no rompas la racha*.
- CTAs imperativos en mayúsculas.
- Sin signos de apertura (`¡` `¿`).
- Sin copy corporativo. *"¡Bienvenido a tu viaje fitness!"* ❌
- Frases cortas, directas, accionables.

**No mencionar** (fuera de scope, AGENTS.md §4): Retos, Missions, Bets,
Levels/XP, Gamificación.

**Sí mencionar**: Rankings. Es per-gym, opt-in explícito del atleta, ya está
implementado, y es un diferencial vendible. No es "gamificación".

---

## Lo que hay que escribir

### App Store — `ios/metadata/es-AR/`

| # | Archivo | Límite | Qué es |
|---|---|---|---|
| 1 | `name.txt` | 30 | El nombre que se ve abajo del ícono |
| 2 | `subtitle.txt` | 30 | Línea bajo el nombre. Es lo segundo que se lee |
| 3 | `keywords.txt` | 100 | Separadas por coma **sin espacio**. No repetir palabras que ya estén en nombre o subtítulo |
| 4 | `promotional_text.txt` | 170 | Se puede cambiar **sin** subir build nuevo. Ideal para novedades |
| 5 | `description.txt` | 4000 | Los primeros ~170 caracteres son lo único visible sin tocar "más" |
| 6 | `release_notes.txt` | 4000 | Novedades de esta versión |

### Play Store — `android/metadata/es-AR/`

| # | Archivo | Límite | Qué es |
|---|---|---|---|
| 7 | `title.txt` | 30 | |
| 8 | `short_description.txt` | 80 | Lo primero que se ve en la ficha |
| 9 | `full_description.txt` | 4000 | |
| 10 | `release_notes.txt` | 500 | Más corto que el de Apple |

### `en-US/` — bloqueado

No escribir todavía. Ver [`README.md`](./README.md) §6.1: el inglés de la app
está incompleto (317 de 1055 claves vacías) y hay strings en castellano
hardcodeados. Traducir la ficha antes de que la app hable inglés produce una
ficha que promete algo que el usuario no recibe.

---

## Dato de contexto para escribir la descripción

Sobre el precio, TREINO tiene hoy esta asimetría: **el atleta no paga nada** y
el PF le paga a TREINO por capacidad de alumnos. Pero **la decisión de producto
está abierta** (#644, congelada). Hasta que se cierre, **el copy no debe afirmar
ni negar que la app es gratis** — ni "gratis para siempre", ni "prueba gratis",
ni mención de precio. Un cambio de modelo después del lanzamiento con una
promesa escrita en la ficha es el peor escenario posible.

---

## Checklist de verificación antes de cargar

- [ ] Contar los caracteres de cada campo (`wc -m`, no `wc -c` — hay acentos)
- [ ] Ninguna mención de Retos / Missions / Bets / XP / gamificación
- [ ] "Entreno IA", nunca "Coach IA"
- [ ] Voseo consistente, sin `¡` ni `¿`
- [ ] Ninguna afirmación sobre precio mientras #644 esté abierta
- [ ] Ningún nombre de gimnasio o persona real
