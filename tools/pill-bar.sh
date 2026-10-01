#!/usr/bin/env bash
# Reconstruye las barras estilo Gzito:
# arriba izq (pager escritorios) / centro (reloj+fecha) / der (CPU+RAM+RED+bandeja),
# abajo centro dock con tareas. Preserva la bandeja actual. Solo shell.
# Depuracion: APPLETSRC=/tmp/fake SRC; PP_TEST=1 bash pill-bar.sh (no toca plasmashell)
set -euo pipefail

APPLETSRC="${APPLETSRC:-$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc}"
[ -f "$APPLETSRC" ] || { echo "Sin appletsrc."; exit 1; }

LAUNCHERS="applications:firefox.desktop,applications:discord.desktop,preferred://filemanager"

if [ "${PP_TEST:-0}" != "1" ]; then
  kquitapp6 plasmashell >/dev/null 2>&1 || true
  # esperar a que muera (kquitapp es gradual); si no, matar
  for _ in $(seq 1 12); do pgrep -x plasmashell >/dev/null || break; sleep 1; done
  pgrep -x plasmashell >/dev/null && pkill -x plasmashell || true
  for _ in $(seq 1 5); do pgrep -x plasmashell >/dev/null || break; sleep 1; done
fi

# 1. subarbol bandeja del primer panel que la tenga
TRAYRAW=$(awk '
function want() { return (buf != "" && plug == "org.kde.plasma.systemtray") }
function dump() { printf "%s", buf; printed = 1; exit }
/^\[Containments\]\[[0-9]+\]$/ { if (want()) dump(); buf = ""; plug = ""; next }
/^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]$/ { if (want()) dump(); buf = $0 "\n"; plug = ""; next }
{ if (buf != "") { buf = buf $0 "\n"; if ($0 ~ /^plugin=/ && plug == "") { plug = $0; sub(/^plugin=/, "", plug) } } }
END { if (want() && !printed) printf "%s", buf }
' "$APPLETSRC")
[ -n "$TRAYRAW" ] || { echo "Sin bandeja para preservar."; exit 1; }
M=$(echo "$TRAYRAW" | head -n 1 | grep -o '\[Applets\]\[[0-9]*\]$' | grep -o '[0-9]*')
# renombrar containment->52 y applet padre tray->166
TRAY=$(echo "$TRAYRAW" | sed "s/\[Containments\]\[[0-9]*\]/[Containments][52]/g; s/\[Applets\]\[$M\]/[Applets][166]/g")
# renumerar hijos de la bandeja (IDs 56..72 genericos chocaban con el dock, p.ej. 70)
N=180
for CID in $(echo "$TRAY" | grep -o '\[Applets\]\[166\]\[Applets\]\[[0-9]*\]' | sed 's/.*\[\([0-9]*\)\]$/\1/' | sort -un); do
  TRAY=$(echo "$TRAY" | sed "s/\[Applets\]\[$CID\]/[Applets][$N]/g")
  N=$((N + 1))
done

# 2. borrar todos los containments panel (scope: lineas bajo [Containments][CID])
cids=$(awk '/^\[Containments\]\[[0-9]+\]$/ { cid = $0; gsub(/[^0-9]/, "", cid); in_c = 1; next }
  in_c && /^\[Containments\]/ { in_c = 0 }
  in_c && /^plugin=org\.kde\.panel$/ { print cid }' "$APPLETSRC")
awk -v cids=" $cids " '
/^\[Containments\]\[[0-9]+\]$/ {
  cur = $0; gsub(/[^0-9]/, "", cur)
  in_bad = (index(cids, " " cur " ") > 0)
  cur_top = cur
  if (!in_bad) print
  next
}
/^\[/ {
  # nueva seccion fuera del subarbol del containment: permitir verla
  if ($0 !~ ("^\\[Containments\\]\\[" cur_top "\\]\\[")) in_bad = 0
  if (!in_bad) print
  next
}
{ if (!in_bad) print }
' "$APPLETSRC" > "$APPLETSRC.new" && mv "$APPLETSRC.new" "$APPLETSRC"

# 3. anexar 3 pildoras antes de [ScreenMapping] (o al final)
{
echo "[Containments][50]"
echo "activityId="
echo "formfactor=2"
echo "immutability=1"
echo "lastScreen=0"
echo "location=3"
echo "plugin=org.kde.panel"
echo "wallpaperplugin=org.kde.image"
echo ""
echo "[Containments][50][Applets][160]"
echo "immutability=1"
echo "plugin=org.kde.plasma.pager"
echo ""
echo "[Containments][50][General]"
echo "AppletOrder=160"
echo ""
echo "[Containments][51]"
echo "activityId="
echo "formfactor=2"
echo "immutability=1"
echo "lastScreen=0"
echo "location=3"
echo "plugin=org.kde.panel"
echo "wallpaperplugin=org.kde.image"
echo ""
echo "[Containments][51][Applets][162]"
echo "immutability=1"
echo "plugin=org.kde.plasma.digitalclock"
echo ""
echo "[Containments][51][Applets][162][Configuration][General]"
echo "showDate=true"
echo ""
echo "[Containments][51][General]"
echo "AppletOrder=162"
echo ""
echo "[Containments][52]"
echo "activityId="
echo "formfactor=2"
echo "immutability=1"
echo "lastScreen=0"
echo "location=3"
echo "plugin=org.kde.panel"
echo "wallpaperplugin=org.kde.image"
echo ""
echo "[Containments][52][Applets][163]"
echo "immutability=1"
echo "plugin=org.kde.plasma.systemmonitor.cpu"
echo ""
echo "[Containments][52][Applets][164]"
echo "immutability=1"
echo "plugin=org.kde.plasma.systemmonitor.memory"
echo ""
printf '%s\n' "$TRAY"
echo ""
echo "[Containments][52][General]"
echo "AppletOrder=163;164;166"
echo ""
echo "[Containments][53]"
echo "activityId="
echo "formfactor=2"
echo "immutability=1"
echo "lastScreen=0"
echo "location=4"
echo "plugin=org.kde.panel"
echo "wallpaperplugin=org.kde.image"
echo ""
echo "[Containments][53][Applets][170]"
echo "immutability=1"
echo "plugin=org.kde.plasma.icontasks"
echo ""
echo "[Containments][53][Applets][170][Configuration][General]"
echo "launchers=$LAUNCHERS"
echo ""
echo "[Containments][53][General]"
echo "AppletOrder=170"
echo ""
} > /tmp/pills.txt
if grep -q "^\[ScreenMapping\]$" "$APPLETSRC"; then
  awk '/^\[ScreenMapping\]$/ && !done { while ((getline line < "/tmp/pills.txt") > 0) print line; done = 1 } { print }' "$APPLETSRC" > "$APPLETSRC.new" && mv "$APPLETSRC.new" "$APPLETSRC"
else
  cat /tmp/pills.txt >> "$APPLETSRC"
fi

if ! grep -q "^hiddenItems=" "$APPLETSRC"; then
  if grep -q "^\[Containments\]\[52\]\[Applets\]\[166\]\[General\]$" "$APPLETSRC"; then
    sed -i '/^\[Containments\]\[52\]\[Applets\]\[166\]\[General\]$/a hiddenItems=org.kde.plasma.clipboard' "$APPLETSRC"
  else
    sed -i '/^\[Containments\]\[52\]\[Applets\]\[166\]$/a hiddenItems=org.kde.plasma.clipboard' "$APPLETSRC"
  fi
fi

if [ "${PP_TEST:-0}" = "1" ]; then
  echo "PP_TEST=1: config escrita en $APPLETSRC (no se toca plasmashell)."
  exit 0
fi

nohup plasmashell --no-respawn >/tmp/plasmashell-pill.log 2>&1 &
sleep 5
ok=0
for _ in 1 2 3; do
  qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
    'var ps = panels(); var al = ["left", "center", "right", "center"]; for (var i = 0; i < ps.length && i < 4; i++) { var p = ps[i]; p.floating = true; p.lengthMode = "fit"; p.opacity = "adaptive"; p.alignment = al[i]; if (i == 3) { p.location = "bottom"; p.height = 46; p.hiding = "autohide"; } else { p.location = "top"; p.height = 30; p.hiding = "none"; } } "done"' >/dev/null 2>&1 && { ok=1; break; }
  sleep 3
done
[ "$ok" = "1" ] || echo "Aviso: evaluateScript no respondio; ajusta las barras a mano."
echo "Pildoras listas."
