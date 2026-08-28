#!/usr/bin/env bash
# Exporta el cliente Web EN EL SERVIDOR y lo publica en /var/www/astrion.
#   ssh root@servidor 'bash -s' < tools/deploy-web.sh
#
# Se exporta alli y no aqui por la misma razon que en el prototipo: el paquete
# pesa cientos de megas y subirlo desde un PC domestico se atasca; en el servidor
# (12 nucleos) el export tarda un minuto y no hay subida.
#
# Godot 4.7.1 y sus plantillas ya estan instalados en /opt/godot para el
# prototipo — misma version que en desarrollo, asi que no hay nada que bajar.
set -euo pipefail
export HOME=/root

GODOT=/opt/godot/godot
SRC=/home/astrion/mex-orbit-v1/mex-orbit-client
DEST=/var/www/astrion

[ -x "$GODOT" ] || { echo "no hay godot en $GODOT"; exit 1; }
cd "$SRC"
git fetch -q origin main && git reset -q --hard origin/main
echo "cliente: $(git log --oneline -1)"

# Los .import NO estan en git: sin importar primero, cada PNG sale como
# marcador de posicion y el juego se exporta lleno de cuadros rosas.
"$GODOT" --headless --path . --import > /tmp/astrion-import.log 2>&1 || true
mkdir -p build/web
"$GODOT" --headless --path . --export-release Web build/web/index.html > /tmp/astrion-export.log 2>&1 || true
if [ ! -s build/web/index.pck ] || [ ! -s build/web/index.wasm ]; then
  echo "EXPORT FALLO — ver /tmp/astrion-export.log"; tail -25 /tmp/astrion-export.log; exit 1
fi

# Comprobacion que no se puede saltar: dev_login.cfg lleva credenciales reales y
# el preset lo excluye, pero un preset se edita y este paquete se REPARTE.
#
# Se usa `grep -a` y no `strings` a proposito. La primera version llamaba a
# `strings`, que no esta instalado en este servidor, y al ir dentro de un `if` el
# fallo del comando se leyo como "no encontrado, todo bien": el guardian se salto
# solo y el paquete se publico sin que nadie lo comprobara. Un `set -e` no salva
# de esto — dentro de una condicion, fallar ES el resultado.
#
# `grep -a` viene en coreutils y esta en cualquier sitio, pero aun asi se
# comprueba que existe: un guardian que puede desaparecer en silencio es peor que
# no tener guardian, porque da confianza.
command -v grep >/dev/null || { echo "ABORTADO: no hay grep para revisar el paquete"; exit 1; }
for aguja in dev_login odrack; do
  if grep -aqi "$aguja" build/web/index.pck; then
    echo "ABORTADO: '$aguja' viajo dentro del paquete"; exit 1
  fi
done
echo "paquete limpio: sin credenciales dentro"

mkdir -p "$DEST"
# El .pck se copia aparte y se renombra: `mv` en el mismo sistema de ficheros es
# atomico, asi que nadie descarga un archivo a medias mientras se publica.
cp -f build/web/index.pck "$DEST/index.pck.new" && mv -f "$DEST/index.pck.new" "$DEST/index.pck"
for f in index.html index.js index.wasm index.png index.icon.png \
         index.apple-touch-icon.png index.audio.worklet.js index.audio.position.worklet.js; do
  [ -f "build/web/$f" ] && cp -f "build/web/$f" "$DEST/"
done
# PRECOMPRIMIR lo que comprime, y solo eso. Medido en este mismo paquete:
#   index.wasm  37,7 MB -> 9,7  (25%)   <- 28 MB menos por tester
#   index.js     0,3 MB -> 0,1  (24%)
#   index.pck   93,9 MB -> 93,6 (99%)   <- ya son texturas: no se toca
# nginx los sirve con `gzip_static on`. Al vuelo seria comprimir 38 MB en cada
# peticion, y este servidor tiene otros dos proyectos encima.
for f in index.wasm index.js; do
  [ -f "$DEST/$f" ] && gzip -9 -c "$DEST/$f" > "$DEST/$f.gz.new" && mv -f "$DEST/$f.gz.new" "$DEST/$f.gz"
done
chmod 644 "$DEST"/*
ls -la --time-style=long-iso "$DEST"
for f in index.html index.wasm index.pck; do
  curl -s -o /dev/null -I -w "$f -> %{http_code} %{size_download}\n" "https://astrion.turname.mx/$f" || true
done
echo "DEPLOY_WEB_OK"
