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

Los casos de `<!-- fecha:auto -->` ya no usan git: desde el #1220 la fecha sale
del REGISTRO —`web/legal/legal-content.json`, el artefacto que viaja en el mismo
commit que el markdown— y no del historial. `sembrar_registro()` deja el arbol
como si se hubiera generado otro dia, que es todo lo que hace falta para
reproducir el bug que motivo el cambio; `commitear()` fecha el commit aparte,
para probar que esa fecha ya no entra en ningun lado.

Los dos primeros casos son controles, y no son decorado: sin ellos un fixture
mal armado tumbaria al generador por cualquier otra razon y los tests de la
fecha pasarian en verde sin haber medido nada.
"""

import datetime
import json
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

# DOS fechas fijas y DISTINTAS, para poder asertar contra valores concretos en
# vez de contra "algo que parezca una fecha". Un test que acepta cualquier fecha
# pasa igual si el generador estampa la de hoy cuando deberia leer el registro.
#
# `REGISTRADA` es la que tiene que salir publicada. `COMMIT_*` es la del commit,
# o sea la que NO. Distintas a proposito: si fueran la misma, el test del #1217
# no podria decir cual de las dos produjo la salida.
COMMIT_ISO = "2026-03-14"
COMMIT_ES = "14 de marzo de 2026"
REGISTRADA = "5 de febrero de 2026"

DART_OUT = Path("lib/features/auth/presentation/legal/legal_content.dart")
# El registro de fechas. Es tambien el tercer eslabon —lo que consume la
# landing— y desde el #1220 las dos cosas son la misma: la fecha vive donde se
# publica, no en el historial.
REGISTRO = Path("web/legal/legal-content.json")

MESES_ES = ("enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
            "agosto", "septiembre", "octubre", "noviembre", "diciembre")


def hoy_es() -> str:
    """Hoy en el formato que emite el generador."""
    h = datetime.date.today()
    return f"{h.day} de {MESES_ES[h.month - 1]} de {h.year}"

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

    def commitear(self, tmp: Path, iso: str) -> None:
        """Commitea todo el arbol con una fecha FIJA de autor y de commit.

        Existe para un solo test —el del #1217— y lo que ese test mide es una
        AUSENCIA: que la fecha del commit no entra en lo que emite el
        generador. Hasta el #1220 si entraba, y por eso `main` se ponia en rojo
        cada vez que un PR de `docs/legal/` se mergeaba un dia distinto del que
        se habia generado.
        """
        env = {
            **os.environ,
            "GIT_AUTHOR_DATE": f"{iso}T12:00:00",
            "GIT_COMMITTER_DATE": f"{iso}T12:00:00",
        }

        def git(*args: str, **kw) -> None:
            subprocess.run(("git", "-C", str(tmp), *args),
                           capture_output=True, check=True, **kw)

        git("init", "-q")
        git("config", "user.email", "test@treino.local")
        git("config", "user.name", "test")
        git("add", "-A")
        git("commit", "-q", "-m", "fixture", env=env)

    def sembrar_registro(self, tmp: Path, fecha: str = REGISTRADA) -> Path:
        """Deja el arbol como si se hubiera generado el dia `fecha`.

        Genera una vez —lo que estampa HOY en los nueve—, reescribe las fechas
        a una fija, y vuelve a generar. La segunda pasada no es plomeria: es la
        que prueba que el generador ADOPTA la fecha registrada en vez de volver
        a estampar hoy, y ademas deja el `sourceSha` consistente con ella.

        Se siembra con el generador real y no con un JSON escrito a mano a
        proposito. La clave del registro es la entrada COMPLETA que emite
        `emit_landing()`; un fixture a mano que se desincronizara de ese
        formato daria "contenido distinto" SIEMPRE, y los tests de abajo
        pasarian en verde midiendo el camino equivocado.
        """
        r = self.correr(tmp)
        self.assertEqual(
            r.returncode, 0,
            f"la siembra fallo.\nstdout:{r.stdout}\nstderr:{r.stderr}")
        reg = tmp / REGISTRO
        self.assertTrue(reg.exists(), "la siembra no escribio el registro")
        d = json.loads(reg.read_text(encoding="utf-8"))
        for entrada in d["documents"]:
            entrada["lastUpdated"] = fecha
        reg.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n",
                       encoding="utf-8")
        r = self.correr(tmp)
        self.assertEqual(
            r.returncode, 0,
            f"la resiembra fallo.\nstdout:{r.stdout}\nstderr:{r.stderr}")
        return reg

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

    # --- `<!-- fecha:auto -->`: la fecha sale del REGISTRO ----------------
    #
    # Hasta el #1220 salia de `git log`. Con **squash merge** —la convencion
    # del repo— el commit que git encuentra despues del merge no es aquel en el
    # que se escribio el texto: es el del MERGE. Entonces la fecha derivada
    # CAMBIABA despues de commiteada, y todo PR que tocara `docs/legal/` y se
    # mergeara un dia distinto del que se genero dejaba `main` en rojo (los
    # cuatro shards, porque el gate corre una vez por shard). Paso con el #1217.
    #
    # Ahora la fecha se REGISTRA en el artefacto —que viaja en el mismo commit
    # que el markdown— y solo se mueve cuando se mueve el contenido publicado.
    # Estos cuatro tests son las cuatro mitades de eso: que se conserve, que se
    # mueva, que el commit no la toque, y que el gate siga mordiendo.

    def test_la_fecha_registrada_sobrevive_a_regenerar(self):
        """Regenerar sobre un texto sin cambios devuelve la MISMA fecha.

        Es la propiedad de la que depende el gate entero: si regenerar moviera
        la fecha, `--check` compararia contra un artefacto que el propio
        generador acaba de invalidar. Se asierta contra un valor EXACTO y no
        contra "algo con forma de fecha": un test que acepta cualquiera pasa
        igual si el generador vuelve a estampar hoy.
        """
        tmp = self.arbol(**{
            BLANCO: doc("terminos", "Términos y Condiciones", "kTermsSections",
                        fecha=FECHA_AUTO),
        })
        self.sembrar_registro(tmp)

        r = self.correr(tmp, "--check")
        self.assertEqual(
            r.returncode, 0,
            "regenerar movio la fecha sin que cambiara el texto: el gate se "
            "pone rojo solo.\n"
            f"stdout:{r.stdout}\nstderr:{r.stderr}")
        self.assertIn(f"kTermsLastUpdated = '{REGISTRADA}'",
                      self.dart_generado(tmp),
                      "la fecha registrada no sobrevivio a la regeneracion")

    def test_la_fecha_del_commit_no_entra(self):
        """EL CASO DEL #1217: artefacto de un dia, commit de otro, gate VERDE.

        Reproduce la forma exacta del bug —un artefacto fechado el 5 de febrero
        dentro de un commit fechado el 14 de marzo— y exige que `--check` pase.
        Con la derivacion por `git log` esto salia ROJO: el generador leia el
        14 de marzo del commit, lo comparaba contra el 5 de febrero del archivo
        y reportaba desfasaje. El autor no podia evitarlo: al commitear, la
        fecha del merge todavia no existia.

        Las dos fechas son DISTINTAS a proposito. Si fueran la misma este test
        no podria distinguir cual de las dos produjo la salida, que es
        literalmente lo unico que mide.
        """
        tmp = self.arbol(**{
            BLANCO: doc("terminos", "Términos y Condiciones", "kTermsSections",
                        fecha=FECHA_AUTO),
        })
        self.sembrar_registro(tmp)
        self.commitear(tmp, COMMIT_ISO)

        r = self.correr(tmp, "--check")
        self.assertEqual(
            r.returncode, 0,
            "el gate se puso rojo por la fecha del COMMIT, no por el "
            "contenido. Es el #1217 otra vez.\n"
            f"stdout:{r.stdout}\nstderr:{r.stderr}")
        dart = self.dart_generado(tmp)
        self.assertIn(f"kTermsLastUpdated = '{REGISTRADA}'", dart)
        self.assertNotIn(
            COMMIT_ES, dart,
            "la fecha del commit se filtro a la salida: alguien volvio a "
            "derivarla del historial")

    def test_texto_nuevo_estampa_hoy(self):
        """Si el texto publicable cambio, la fecha pasa a ser HOY.

        Es la otra mitad del mecanismo. Sin ella el registro seria una fecha
        congelada: el documento avanzaria y la linea "Ultima actualizacion"
        seguiria diciendo cuando se genero la primera vez. No es hipotetico —es
        lo que paso con las paginas del sitio, que quedaron en marzo mientras
        el documento real avanzaba.

        El segundo assert fija que la fecha es POR DOCUMENTO: tocar Terminos no
        puede re-fechar Privacidad, que nadie edito.
        """
        tmp = self.arbol(**{
            BLANCO: doc("terminos", "Términos y Condiciones", "kTermsSections",
                        fecha=FECHA_AUTO),
            # Privacidad va con el centinela A PROPOSITO: es el testigo. El
            # resto del fixture usa `FECHA_OK`, una fecha escrita a mano, que
            # sale del markdown y no toca el registro — con esa, el assert de
            # abajo pasaria sin haber mirado el mecanismo ni una vez.
            "politica-de-privacidad.md": doc(
                "privacidad", "Política de Privacidad", "kPrivacySections",
                fecha=FECHA_AUTO),
        })
        self.sembrar_registro(tmp)

        destino = tmp / "docs" / "legal" / BLANCO
        destino.write_text(
            destino.read_text(encoding="utf-8").replace(
                "Texto publicable.", "Texto publicable, recien cambiado."),
            encoding="utf-8")

        r = self.correr(tmp)
        self.assertEqual(r.returncode, 0,
                         f"stdout:{r.stdout}\nstderr:{r.stderr}")
        dart = self.dart_generado(tmp)
        self.assertIn(
            f"kTermsLastUpdated = '{hoy_es()}'", dart,
            "el texto cambio y la fecha quedo en la registrada: una fecha "
            "vieja sobre un texto nuevo.")
        self.assertIn(
            f"kPrivacyLastUpdated = '{REGISTRADA}'", dart,
            "se re-fecho un documento que nadie toco")

    def test_control_negativo_editar_sin_regenerar_sale_rojo(self):
        """CONTROL NEGATIVO: un .md editado y no regenerado tiene que dar ROJO.

        Es la pregunta que decide si el #1220 arreglo el gate o lo apago. Un
        gate que dejo de fallar no esta arreglado: esta apagado, y el verde de
        los otros tres no distingue una cosa de la otra.

        El control de este control es `test_la_fecha_registrada_sobrevive_a_
        regenerar`: el MISMO arbol, sin la edicion, sale verde. Si los dos
        salieran del mismo color, este no estaria midiendo la edicion.
        """
        tmp = self.arbol(**{
            BLANCO: doc("terminos", "Términos y Condiciones", "kTermsSections",
                        fecha=FECHA_AUTO),
        })
        self.sembrar_registro(tmp)

        destino = tmp / "docs" / "legal" / BLANCO
        antes = destino.read_text(encoding="utf-8")
        despues = antes.replace("Texto publicable.",
                                "Texto publicable, editado y sin regenerar.")
        self.assertNotEqual(antes, despues,
                            "la mutacion del control negativo no entro: el "
                            "rojo (o el verde) no significaria nada")
        destino.write_text(despues, encoding="utf-8")

        r = self.correr(tmp, "--check")
        self.assertEqual(
            r.returncode, 1,
            "el gate dejo pasar un markdown editado sin regenerar.\n"
            f"stdout:{r.stdout}\nstderr:{r.stderr}")
        self.assertIn("Desfasaje", r.stderr,
                      "fallo, pero no por desfasaje: el rojo viene de otro lado")

    def test_control_negativo_registro_ilegible_aborta(self):
        """Un registro roto aborta en vez de re-fechar los nueve documentos.

        Es el heredero del viejo "sin git no hay fecha, y no se inventa una":
        cambio de donde sale la fecha, no el criterio. Tratar un JSON ilegible
        como "registro vacio" estamparia hoy en los NUEVE de una sola vez, en
        silencio, sobre textos que nadie toco — y el usuario no tiene forma de
        distinguir una fecha registrada de una fabricada.
        """
        tmp = self.arbol(**{
            BLANCO: doc("terminos", "Términos y Condiciones", "kTermsSections",
                        fecha=FECHA_AUTO),
        })
        self.sembrar_registro(tmp)
        (tmp / REGISTRO).write_text("{ esto no es json", encoding="utf-8")

        r = self.correr(tmp)
        self.assertNotEqual(
            r.returncode, 0,
            "un registro ilegible paso como vacio y los nueve documentos "
            "quedaron fechados hoy.\n"
            f"stdout:{r.stdout}\nstderr:{r.stderr}")
        self.assertIn(
            "legal-content.json", r.stdout + r.stderr,
            "aborto, pero sin decir que archivo hay que recuperar")

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

        tmp = self.arbol()
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
        tmp = self.arbol()
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
            tmp = self.arbol(**{
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
