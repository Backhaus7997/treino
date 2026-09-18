#!/usr/bin/env python3
"""Tests del generador legal: que ningun `[[PENDIENTE]]` llegue a un usuario.

    python3 scripts/test/build_legal_content.test.py

Por que existe: `build_legal_content.py` nacio sin tests, y el guard que aborta
ante un marcador sin resolver mira SOLO el texto publicable (`publishable()`).
La fecha del encabezado —`**Ultima actualizacion:**`— se lee del archivo
COMPLETO y vive arriba del primer `## `, o sea afuera de lo que el guard
inspecciona. De los nueve documentos del ORDER, siete no tienen
`<!-- publish:start -->` y dependen de ese fallback, asi que el agujero los
alcanza a todos.

Cada caso corre el generador REAL como subproceso, pero dentro de un arbol
temporal: `ROOT` sale de `Path(__file__).resolve().parent.parent`, asi que una
copia del script en `<tmp>/scripts/` hace que `SRC` apunte a
`<tmp>/docs/legal/`. Nada toca el repo.

El aislamiento no es comodidad, es correccion: contra el `docs/legal/` real
estos tests saldrian en rojo HOY, pero por el marcador del INPI que sigue vivo
en el cuerpo de `aviso-legal.md` — o sea por el motivo equivocado. Con fixtures
limpios, un exit 2 solo puede venir de la fecha.

Los dos primeros casos son controles, y no son decorado: sin ellos un fixture
mal armado tumbaria al generador por cualquier otra razon y los tests de la
fecha pasarian en verde sin haber medido nada.
"""

import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
SCRIPT = ROOT / "scripts" / "build_legal_content.py"

FECHA_OK = "**Última actualización:** 3 de septiembre de 2026"
FECHA_PENDIENTE = "**Última actualización:** [[PENDIENTE — fecha de publicación]]"

# (archivo, slug, title, dart) — el ORDER completo de build_legal_content.py.
# Si el generador suma un documento, estos fixtures fallan con "falta
# docs/legal/X" y hay que agregarlo aca. Que duela un poco es el punto: un
# documento nuevo sin cobertura es como se abrio este agujero.
DOCS = [
    ("terminos-y-condiciones.md", "terminos", "Términos y Condiciones",
     "kTermsSections"),
    ("terminos-suscripcion.md", "suscripcion", "Términos de Suscripción",
     "kSubscriptionSections"),
    ("politica-de-privacidad.md", "privacidad", "Política de Privacidad",
     "kPrivacySections"),
    ("descargo-medico.md", "descargo-medico", "Descargo Médico",
     "kHealthDisclaimerSections"),
    ("consentimiento-datos-salud.md", "consentimiento-salud",
     "Consentimiento de datos de salud", "kHealthConsentSections"),
    ("normas-de-comunidad.md", "comunidad", "Normas de Comunidad",
     "kCommunitySections"),
    ("contrato-entrenador.md", "entrenadores", "Términos para Entrenadores",
     "kTrainerTermsSections"),
    ("retencion-y-borrado.md", "retencion", "Retención y eliminación de datos",
     "kDataRetentionSections"),
    ("aviso-legal.md", "aviso-legal", "Aviso Legal", "kLegalNoticeSections"),
]

BLANCO = "terminos-y-condiciones.md"


def doc(slug: str, title: str, dart: str, *,
        fecha: str = FECHA_OK, cuerpo: str = "Texto publicable.") -> str:
    """Un documento legal minimo pero valido para `load()`.

    Sin `<!-- publish:start -->` a proposito: es la forma que tienen siete de
    los nueve, y la que expone el agujero.
    """
    fecha_linea = f"{fecha}\n\n" if fecha else ""
    # El email es para `aviso-legal.md`, de donde sale CONTACT_EMAIL. Ponerlo
    # en todos cuesta nada y evita que el fixture dependa del orden.
    return (
        f"<!-- treino-legal\n"
        f"slug: {slug}\n"
        f"title: {title}\n"
        f"dart: {dart}\n"
        f"-->\n\n"
        f"# {title}\n\n"
        f"{fecha_linea}"
        f"## Una sección\n\n"
        f"{cuerpo}\n\n"
        f"Contacto: treino@gettreino.com\n"
    )


class GeneradorLegal(unittest.TestCase):

    def arbol(self, **overrides: str) -> Path:
        """Un repo de mentira con el generador real adentro."""
        tmp = Path(tempfile.mkdtemp(prefix="legal-gate-"))
        self.addCleanup(shutil.rmtree, tmp, ignore_errors=True)
        (tmp / "scripts").mkdir(parents=True)
        shutil.copy2(SCRIPT, tmp / "scripts" / SCRIPT.name)
        legal = tmp / "docs" / "legal"
        legal.mkdir(parents=True)
        for nombre, slug, title, dart in DOCS:
            texto = overrides.get(nombre) or doc(slug, title, dart)
            legal.joinpath(nombre).write_text(texto, encoding="utf-8")
        return tmp

    def correr(self, tmp: Path, *args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, str(tmp / "scripts" / SCRIPT.name), *args],
            capture_output=True, text=True,
        )

    # --- controles -------------------------------------------------------
    # Sin estos dos, los tests de la fecha pueden salir verdes sin medir nada.

    def test_control_todo_limpio_genera(self):
        """Los fixtures son validos: sin marcadores, el generador sale con 0.

        Si esto se pone rojo, los dos casos de la fecha no prueban nada: el
        exit 2 vendria del fixture, no del agujero.
        """
        r = self.correr(self.arbol())
        self.assertEqual(r.returncode, 0,
                         f"fixture invalido.\nstdout:{r.stdout}\nstderr:{r.stderr}")

    def test_control_marcador_en_el_cuerpo_aborta(self):
        """El guard que YA existe funciona: un `[[...]]` publicable aborta.

        Control positivo del mecanismo. Si esto fallara, el problema no seria
        la fecha sino que el guard entero esta roto.
        """
        sucio = doc("terminos", "Términos y Condiciones", "kTermsSections",
                    cuerpo="Regimos por [[PENDIENTE — ley aplicable]].")
        r = self.correr(self.arbol(**{BLANCO: sucio}))
        self.assertEqual(r.returncode, 2, r.stderr)
        self.assertIn(BLANCO, r.stderr)

    # --- el agujero ------------------------------------------------------

    def test_marcador_en_la_fecha_aborta(self):
        """Un `[[PENDIENTE]]` en la fecha tiene que abortar igual que en el cuerpo.

        Es el caso real: los nueve documentos de `docs/legal/` dicen hoy
        `**Última actualización:** [[PENDIENTE — fecha de publicación]]`, y esa
        fecha se estampa en un `const` de Dart y en el `<header>` de cada HTML.
        Sin este guard, la primera corrida real publica el marcador a la vista
        del usuario — que es exactamente lo que el gate existe para impedir.
        """
        r = self.correr(self.arbol(**{
            BLANCO: doc("terminos", "Términos y Condiciones", "kTermsSections",
                        fecha=FECHA_PENDIENTE),
        }))
        self.assertEqual(
            r.returncode, 2,
            "la fecha con [[PENDIENTE]] paso el gate y se va a publicar.\n"
            f"stdout:{r.stdout}\nstderr:{r.stderr}")
        self.assertIn(BLANCO, r.stderr,
                      "aborto, pero sin decir que archivo hay que arreglar")

    def test_documento_sin_fecha_aborta(self):
        """Sin `**Última actualización:**`, el generador no puede seguir.

        Hoy cae a `"sin fecha"` y publica eso como si fuera un valor legitimo.
        Un documento legal sin fecha de actualizacion es un defecto, no un
        default: el usuario no puede saber que version acepto.
        """
        r = self.correr(self.arbol(**{
            BLANCO: doc("terminos", "Términos y Condiciones", "kTermsSections",
                        fecha=""),
        }))
        self.assertNotEqual(
            r.returncode, 0,
            "un documento legal sin fecha se genero igual, como 'sin fecha'.\n"
            f"stdout:{r.stdout}\nstderr:{r.stderr}")
        self.assertIn(BLANCO, r.stdout + r.stderr,
                      "aborto, pero sin decir que archivo hay que arreglar")

    # --- lo que NO se puede romper al arreglar ---------------------------

    def test_allow_pending_sigue_previsualizando(self):
        """`--allow-pending` tiene que seguir dejando previsualizar.

        Es la valvula que permite ver como quedaria el texto mientras las
        decisiones legales siguen abiertas. Si el fix de la fecha la cierra,
        el equipo pierde la unica forma de revisar el borrador.
        """
        r = self.correr(self.arbol(**{
            BLANCO: doc("terminos", "Términos y Condiciones", "kTermsSections",
                        fecha=FECHA_PENDIENTE),
        }), "--preview", "--allow-pending")
        self.assertEqual(r.returncode, 0,
                         f"stdout:{r.stdout}\nstderr:{r.stderr}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
