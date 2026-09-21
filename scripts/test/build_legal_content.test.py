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

El aislamiento no es comodidad, es correccion: un exit 2 contra el `docs/legal/`
real puede venir de cualquier marcador vivo en cualquiera de los nueve
documentos, o sea por el motivo equivocado. Con fixtures limpios solo puede
venir de la fecha. (Cuando estos tests se escribieron el ruido era concreto: el
marcador del INPI seguia vivo en `aviso-legal.md`. Se cerro el 2026-09-21, pero
el argumento no dependia de ese marcador en particular.)

Los tres casos de `<!-- fecha:auto -->` usan `arbol_git()` en vez de `arbol()`,
porque necesitan historial. El tercero es el control negativo y usa `arbol()` a
proposito: sin repo, el generador tiene que abortar en vez de inventar una
fecha.

Los dos primeros casos son controles, y no son decorado: sin ellos un fixture
mal armado tumbaria al generador por cualquier otra razon y los tests de la
fecha pasarian en verde sin haber medido nada.
"""

import datetime
import os
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
FECHA_AUTO = "**Última actualización:** <!-- fecha:auto -->"

# Una fecha de commit fija, para poder asertar contra un valor concreto en vez
# de contra "algo que parezca una fecha". Un test que acepta cualquier fecha
# pasa igual si el generador estampa la de hoy cuando deberia leer el historial.
COMMIT_ISO = "2026-03-14"
COMMIT_ES = "14 de marzo de 2026"
DART_OUT = Path("lib/features/auth/presentation/legal/legal_content.dart")

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

    def arbol_git(self, **overrides: str) -> Path:
        """Como `arbol()`, pero con historial: un repo con todo commiteado.

        `arbol()` NO hace `git init` a proposito —los tests de marcadores no
        necesitan historial— asi que los de `<!-- fecha:auto -->` necesitan su
        propia version. La fecha del commit se fija con las variables de
        entorno de git para poder asertar contra un valor exacto.
        """
        tmp = self.arbol(**overrides)
        env = {
            **os.environ,
            "GIT_AUTHOR_DATE": f"{COMMIT_ISO}T12:00:00",
            "GIT_COMMITTER_DATE": f"{COMMIT_ISO}T12:00:00",
        }

        def git(*args: str, **kw) -> None:
            subprocess.run(("git", "-C", str(tmp), *args),
                           capture_output=True, check=True, **kw)

        git("init", "-q")
        git("config", "user.email", "test@treino.local")
        git("config", "user.name", "test")
        git("add", "-A")
        git("commit", "-q", "-m", "fixture", env=env)
        return tmp

    def dart_generado(self, tmp: Path) -> str:
        destino = tmp / DART_OUT
        self.assertTrue(destino.exists(),
                        f"el generador no escribio {DART_OUT}")
        return destino.read_text(encoding="utf-8")

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

        Los nueve documentos de `docs/legal/` decian
        `**Última actualización:** [[PENDIENTE — fecha de publicación]]` hasta
        el 2026-09-21; hoy usan `<!-- fecha:auto -->`. El guard sigue haciendo
        falta igual: la fecha se estampa en un `const` de Dart y en el
        `<header>` de cada HTML, asi que un marcador escrito ahi a mano —en un
        documento nuevo, o al revertir el centinela— se publicaria a la vista
        del usuario.
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

    # --- `<!-- fecha:auto -->`: la fecha sale del historial ---------------

    def test_fecha_auto_sale_del_ultimo_commit(self):
        """Con historial limpio, la fecha es la del commit que toco el archivo.

        Es el caso que justifica el mecanismo: nadie tiene que acordarse de
        mover la fecha porque no la escribe nadie. Se asierta contra una fecha
        EXACTA y no contra "algo con forma de fecha": un test que acepta
        cualquiera pasa igual si el generador estampa hoy.
        """
        tmp = self.arbol_git(**{
            BLANCO: doc("terminos", "Términos y Condiciones", "kTermsSections",
                        fecha=FECHA_AUTO),
        })
        r = self.correr(tmp)
        self.assertEqual(r.returncode, 0,
                         f"stdout:{r.stdout}\nstderr:{r.stderr}")
        self.assertIn(
            f"kTermsLastUpdated = '{COMMIT_ES}'", self.dart_generado(tmp),
            "la fecha no salio del commit. Si dice la de hoy, el generador "
            "esta inventandola en vez de leer el historial.")

    def test_fecha_auto_con_cambios_sin_commitear_usa_hoy(self):
        """Con el archivo sucio, la fecha es HOY, no la del commit anterior.

        Sin esto el flujo normal —editar, generar, commitear los dos juntos—
        estamparia la fecha del cambio ANTERIOR: una fecha vieja para un texto
        nuevo, que es justo lo que este mecanismo existe para impedir.
        """
        tmp = self.arbol_git(**{
            BLANCO: doc("terminos", "Términos y Condiciones", "kTermsSections",
                        fecha=FECHA_AUTO),
        })
        # editar DESPUES del commit: el texto cambia, el historial todavia no
        destino = tmp / "docs" / "legal" / BLANCO
        destino.write_text(
            destino.read_text(encoding="utf-8").replace(
                "Texto publicable.", "Texto publicable, recien cambiado."),
            encoding="utf-8")

        r = self.correr(tmp)
        self.assertEqual(r.returncode, 0,
                         f"stdout:{r.stdout}\nstderr:{r.stderr}")
        dart = self.dart_generado(tmp)
        self.assertNotIn(
            f"kTermsLastUpdated = '{COMMIT_ES}'", dart,
            "el texto cambio y la fecha quedo en la del commit anterior: "
            "una fecha vieja sobre un texto nuevo.")
        hoy = datetime.date.today()
        meses = ("enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
                 "agosto", "septiembre", "octubre", "noviembre", "diciembre")
        esperado = f"{hoy.day} de {meses[hoy.month - 1]} de {hoy.year}"
        self.assertIn(f"kTermsLastUpdated = '{esperado}'", dart)

    def test_fecha_auto_sin_repo_aborta(self):
        """CONTROL NEGATIVO: sin git no hay fecha, y no se inventa una.

        Es el caso que decide si el mecanismo es confiable. Caer a hoy cuando
        no se puede leer el historial seria estampar una fecha inventada en un
        documento legal, y el usuario no tiene forma de distinguir una fecha
        derivada de una fabricada. Por el mismo criterio del resto del
        generador —un defecto no es un default— aca se aborta.

        `arbol()` no hace `git init`, asi que el arbol no es un repo.
        """
        r = self.correr(self.arbol(**{
            BLANCO: doc("terminos", "Términos y Condiciones", "kTermsSections",
                        fecha=FECHA_AUTO),
        }))
        self.assertNotEqual(
            r.returncode, 0,
            "sin repo git el generador invento una fecha y la publico.\n"
            f"stdout:{r.stdout}\nstderr:{r.stderr}")
        self.assertIn(BLANCO, r.stdout + r.stderr,
                      "aborto, pero sin decir que archivo hay que arreglar")

    # --- tablas ----------------------------------------------------------

    def test_la_tabla_conserva_la_etiqueta_de_fila(self):
        """Con el encabezado de la 1ª columna vacío, esa columna es la ETIQUETA.

        Sin esto se perdía: el `zip(header, row)` filtra por `if v and h`, y ahi
        `h` es "". En `terminos-suscripcion.md` eso producia DOS BULLETS
        IDENTICOS para «quién gestiona la baja» y «quién gestiona el reembolso»
        —los dos «Contratado en la web: TREINO — Contratado desde la app: La
        tienda»— asi que el usuario no podia distinguirlos. En un documento
        legal sobre bajas y reembolsos. Lo encontro Codex en el PR #1207 (P1).
        """
        import importlib.util
        spec = importlib.util.spec_from_file_location("blc", SCRIPT)
        blc = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(blc)

        filas = [
            "| | En la web | En la app |",
            "|---|---|---|",
            "| Baja | TREINO | La tienda |",
            "| Reembolso | TREINO | La tienda |",
        ]
        salida = blc.flatten_table(filas)

        self.assertEqual(len(salida), 2)
        self.assertNotEqual(
            salida[0], salida[1],
            "dos filas distintas dieron el MISMO bullet: se perdio la etiqueta")
        self.assertIn("Baja", salida[0])
        self.assertIn("Reembolso", salida[1])

    def test_la_tabla_normal_no_cambia(self):
        """CONTROL: con encabezado en la 1ª columna, el formato es el de antes.

        Sin este control, el arreglo de arriba podria estar metiendo la etiqueta
        en TODAS las tablas y el otro test pasaria igual.
        """
        import importlib.util
        spec = importlib.util.spec_from_file_location("blc", SCRIPT)
        blc = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(blc)

        salida = blc.flatten_table([
            "| Dato | Quién lo ve |",
            "|---|---|",
            "| Tu peso | Sólo vos |",
        ])
        self.assertEqual(salida, ["• Tu peso: Sólo vos"])

    # --- el split app/web ------------------------------------------------

    def test_al_dart_solo_van_los_de_en_el_binario(self):
        """El Dart lleva SOLO `EN_EL_BINARIO`, no los nueve de `ORDER`.

        No es preferencia de presentacion: el texto de los otros siete no puede
        estar en el archivo aunque no se muestre. `terminos-suscripcion.md`
        dice «Contratado en la web: Mercado Pago», y meter esa frase en el
        binario de iOS es un *call to action* para pagar afuera — prohibido por
        el intro de la Guideline 3.1.3 de Apple fuera de la storefront de EEUU.

        Lo cuida tambien `anti_steering_movil_test`, pero ese solo se entera si
        el documento nuevo ADEMAS trae una de sus frases. Este fija el split.
        """
        import importlib.util
        spec = importlib.util.spec_from_file_location("blc", SCRIPT)
        blc = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(blc)

        self.assertTrue(
            set(blc.EN_EL_BINARIO).issubset(set(blc.ORDER)),
            "EN_EL_BINARIO nombra un documento que no esta en ORDER")

        tmp = self.arbol_git()
        r = self.correr(tmp)
        self.assertEqual(r.returncode, 0, f"{r.stdout}\n{r.stderr}")
        dart = self.dart_generado(tmp)

        adentro = {n for n, _, _, const in DOCS if n in blc.EN_EL_BINARIO}
        for nombre, _, _, const in DOCS:
            if nombre in adentro:
                self.assertIn(f"{const} =", dart,
                              f"falta {nombre}, que SI tiene que viajar")
            else:
                self.assertNotIn(
                    f"{const} =", dart,
                    f"{nombre} se emitio al Dart y no esta en EN_EL_BINARIO: "
                    "su texto viaja en el binario movil")

    # --- el tercer eslabon: la landing -----------------------------------

    def test_al_json_de_la_landing_van_los_NUEVE(self):
        """El JSON lleva los nueve, no los dos de `EN_EL_BINARIO`.

        El split del binario existe por la Guideline 3.1.3 de Apple, que habla
        de lo que pasa «within the app». Un sitio web no es la app: filtrar ahi
        tambien dejaria a `gettreino.com` sin siete documentos legales que la
        Guideline 1.2 y la ley de consumidor SI le piden publicar.

        O sea: los dos filtros son opuestos a proposito, y este test lo fija
        para que nadie los unifique «por consistencia».
        """
        import json as _json
        tmp = self.arbol_git()
        r = self.correr(tmp)
        self.assertEqual(r.returncode, 0, f"{r.stdout}\n{r.stderr}")

        destino = tmp / "web" / "legal" / "legal-content.json"
        self.assertTrue(destino.exists(), "no se emitio el JSON de la landing")
        d = _json.loads(destino.read_text(encoding="utf-8"))

        self.assertEqual(
            [x["slug"] for x in d["documents"]],
            [slug for _, slug, _, _ in DOCS],
            "el JSON no lleva los nueve documentos, o cambio el orden")
        self.assertTrue(d.get("sourceSha"),
                        "falta el sha: sin el, el control cruzado con "
                        "`treino-app` tiene que re-derivar todo")

    def test_el_sha_cambia_si_cambia_el_texto(self):
        """CONTROL: el sha tiene que MOVERSE con el contenido.

        Un sha que no se mueve es peor que ninguno: los dos repos comparan una
        cadena que siempre coincide y el control cruzado pasa en verde sobre
        textos distintos.
        """
        import json as _json

        def sha_de(cuerpo: str) -> str:
            tmp = self.arbol_git(**{
                BLANCO: doc("terminos", "Términos y Condiciones",
                            "kTermsSections", cuerpo=cuerpo),
            })
            self.assertEqual(self.correr(tmp).returncode, 0)
            destino = tmp / "web" / "legal" / "legal-content.json"
            return _json.loads(destino.read_text(encoding="utf-8"))["sourceSha"]

        self.assertNotEqual(sha_de("Texto publicable."),
                            sha_de("Texto publicable, distinto."),
                            "el sha no se movio al cambiar el texto")

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
