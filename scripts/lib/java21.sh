# shellcheck shell=bash
#
# java21.sh — encontrar un JDK 21+ cuando el del PATH no sirve.
#
# ═══════════════════════════════════════════════════════════════════════════
#  POR QUE EXISTE
# ═══════════════════════════════════════════════════════════════════════════
#
# `firebase-tools` 15+ **no arranca con Java 17**. Falla con:
#
#   Error: firebase-tools no longer supports Java version before 21.
#
# Hasta acá, los dos scripts que levantan el emulador —`emulator.sh` y
# `test_rules.sh`— DOCUMENTABAN el requisito y no hacían nada al respecto:
# `emulator.sh:17` lo pone como "Requisito" y `test_rules.sh:41` deja escrito a
# mano el `JAVA_HOME=/opt/homebrew/opt/openjdk@21` que hay que anteponer. Los
# dos te dejan chocarte contra el error igual, y la variable se pierde al
# cerrar la terminal, así que se vuelve a chocar mañana.
#
# El JDK 21 ya está instalado en las máquinas del equipo —Android Studio trae
# el suyo— pero no en el PATH. Este archivo lo busca.
#
# ── Lo que NO hace, y es deliberado ──
#
# **No instala nada y no toca el PATH del sistema.** Exporta las variables para
# el proceso actual y nada más. Un script de desarrollo que modifica el entorno
# global de una máquina es un efecto que nadie pidió y que después hay que
# adivinar de dónde salió.
#
# **No hace nada si el `java` del PATH ya sirve**, y eso es lo que lo vuelve
# seguro para CI: `test_rules.sh` ES el gate del job `rules-test`, que corre en
# ubuntu con un JDK 21 provisto por el runner. Ahí esta función retorna en la
# primera línea sin imprimir nada ni tocar una variable.

# Versión MAYOR del java que se le pase, o vacío si no se puede leer.
#
# Contempla los dos formatos que imprime `java -version`, porque el viejo sigue
# vivo en máquinas con JDK 8:
#
#   openjdk version "21.0.8" 2025-07-15   ->  21
#   java version "1.8.0_202"              ->  8   (el mayor es el SEGUNDO)
_version_mayor_de_java() {
  local binario="$1"
  local cruda
  cruda="$("${binario}" -version 2>&1 | head -1 | sed -n 's/.*version "\([^"]*\)".*/\1/p')"
  [ -z "${cruda}" ] && return 0

  case "${cruda}" in
    1.*) echo "${cruda}" | cut -d. -f2 ;;
    *)   echo "${cruda}" | cut -d. -f1 ;;
  esac
}

# Los lugares donde YA hay un JDK 21 en las máquinas del equipo.
#
# El orden importa: primero el JBR de Android Studio, que es el que todo el que
# toca Flutter tiene sí o sí, y después los instalados a mano. Si alguien suma
# una ruta acá, que sea una que EXISTA en su máquina — una lista de rutas
# aspiracionales no es una búsqueda, es ruido con forma de código.
_candidatos_de_jdk21() {
  cat <<'RUTAS'
/c/Program Files/Android/Android Studio/jbr
/Applications/Android Studio.app/Contents/jbr/Contents/Home
/opt/homebrew/opt/openjdk@21
/usr/local/opt/openjdk@21
/opt/android-studio/jbr
RUTAS
  # Linux con el paquete de la distro, que trae la versión en el nombre.
  ls -d /usr/lib/jvm/java-21-* 2>/dev/null || true
  # El de Android Studio instalado en el home del usuario.
  [ -n "${HOME:-}" ] && echo "${HOME}/android-studio/jbr"
}

# Deja `java` 21+ en el PATH del PROCESO ACTUAL, o explica por qué no pudo.
#
# Devuelve 0 si al terminar hay un java 21+ disponible, 1 si no. El que llama
# decide si eso es fatal: `emulator.sh` corta, porque sin emulador no hay nada
# que hacer.
asegurar_java21() {
  local mayor
  mayor="$(_version_mayor_de_java java)"
  if [ -n "${mayor}" ] && [ "${mayor}" -ge 21 ] 2>/dev/null; then
    return 0
  fi

  local candidato
  while IFS= read -r candidato; do
    [ -z "${candidato}" ] && continue
    [ -x "${candidato}/bin/java" ] || continue

    local suya
    suya="$(_version_mayor_de_java "${candidato}/bin/java")"
    [ -n "${suya}" ] && [ "${suya}" -ge 21 ] 2>/dev/null || continue

    export JAVA_HOME="${candidato}"
    export PATH="${candidato}/bin:${PATH}"
    echo "java: el del PATH era ${mayor:-ilegible}; usando el ${suya} de ${candidato}" >&2
    return 0
  done <<EOF
$(_candidatos_de_jdk21)
EOF

  {
    echo ""
    echo "ERROR: firebase-tools 15+ necesita Java 21+ y el del PATH es ${mayor:-ilegible}."
    echo ""
    echo "Se buscó un JDK 21 en los lugares habituales y no apareció ninguno:"
    _candidatos_de_jdk21 | sed 's/^/  /'
    echo ""
    echo "Si tenés uno en otro lado, antepónelo a mano:"
    echo "  export JAVA_HOME=/ruta/al/jdk21"
    echo "  export PATH=\"\$JAVA_HOME/bin:\$PATH\""
    echo ""
    echo "Si no lo tenés: Android Studio trae el suyo (JBR 21), y en mac"
    echo "\`brew install openjdk@21\` alcanza."
    echo ""
  } >&2
  return 1
}
