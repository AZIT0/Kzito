#!/usr/bin/env bash
# Reconstruye las barras estilo Gzito:
# arriba izq (pager escritorios) / centro (reloj+fecha) / der (CPU+RAM+RED+bandeja),
# abajo centro dock con tareas. Preserva la bandeja actual. Solo shell.
set -euo pipefail

APPLETSRC=~/.config/plasma-org.kde.plasma.desktop-appletsrc
[ -f "$APPLETSRC" ] || { echo "Sin appletsrc."; exit 1; }

LAUNCHERS="applications:firefox.desktop,applications:discord.desktop,preferred://filemanager"

kquitapp6 plasmashell >/dev/null 2>&1 || true
sleep 3

# 1. subarbol bandeja del primer panel que la tenga
TRAYRAW=$(awk '
function want() { return (buf != "" && plug == "org.kde.plasma.systemtray") }
/^\[Containments\]\[[0-9]+\]$/ { if (want()) { printf "%s", buf; exit } buf = ""; plug = ""; next }
/^\[Containments\]\[[0-9]+\]\[Applets\]\[[0-9]+\]$/ { if (want()) { printf "%s", buf; exit } buf = $0 "\n"; plug = ""; next }
{ if (buf != "") { buf = buf $0 "\n"; if ($0 ~ /^plugin=/ && plug == "") { plug = $0; sub(/^plugin=/, "", plug) } } }
END { if (want()) printf "%s", buf }
' "$APPLETSRC")
[ -n "$TRAYRAW" ] || { echo "Sin bandeja para preservar."; exit 1; }
M=$(echo "$TRAYRAW" | head -n 1 | grep -o '\[Applets\]\[[0-9]*\]$' | grep -o '[0-9]*')
TRAY=$(echo "$TRAYRAW" | sed "s/\[Containments\]\[[0-9]*\]/[Containments][52]/g; s/\[Applets\]\[$M\]/[Applets][66]/g")

# 2. borrar todos los containments panel
cids=$(awk '/^\[Containments\]\[[0-9]+\]$/ { cid = $0; gsub(/[^0-9]/, "", cid); in_c = 1; next }
  in_c && /^\[Containments\]/ { in_c = 0 }
  in_c && /^plugin=org\.kde\.panel$/ { print cid }' "$APPLETSRC")
awk -v cids=" $cids " '
/^\[Containments\]\[[0-9]+\]$/ { cur = $0; gsub(/[^0-9]/, "", cur); skip = (index(cids, " " cur " ") > 0); if (skip) next }
{ if (!skip) print }
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
echo "[Containments][50][Applets][60]"
echo "immutability=1"
echo "plugin=org.kde.plasma.pager"
echo ""
echo "[Containments][50][General]"
echo "AppletOrder=60"
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
echo "[Containments][51][Applets][62]"
echo "immutability=1"
echo "plugin=org.kde.plasma.digitalclock"
echo ""
echo "[Containments][51][Applets][62][Configuration][General]"
echo "showDate=true"
echo ""
echo "[Containments][51][General]"
echo "AppletOrder=62"
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
echo "[Containments][52][Applets][63]"
echo "immutability=1"
echo "plugin=org.kde.plasma.systemmonitor.cpu"
echo ""
echo "[Containments][52][Applets][64]"
echo "immutability=1"
echo "plugin=org.kde.plasma.systemmonitor.memory"
echo ""
printf '%s\n' "$TRAY"
echo ""
echo "[Containments][52][General]"
echo "AppletOrder=63;64;66"
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
echo "[Containments][53][Applets][70]"
echo "immutability=1"
echo "plugin=org.kde.plasma.icontasks"
echo ""
echo "[Containments][53][Applets][70][Configuration][General]"
echo "launchers=$LAUNCHERS"
echo ""
echo "[Containments][53][General]"
echo "AppletOrder=70"
echo ""
} > /tmp/pills.txt
if grep -q "^\[ScreenMapping\]$" "$APPLETSRC"; then
  awk '/^\[ScreenMapping\]$/ && !done { while ((getline line < "/tmp/pills.txt") > 0) print line; done = 1 } { print }' "$APPLETSRC" > "$APPLETSRC.new" && mv "$APPLETSRC.new" "$APPLETSRC"
else
  cat /tmp/pills.txt >> "$APPLETSRC"
fi

grep -q "^hiddenItems=" "$APPLETSRC" || \
  sed -i '/^\[Containments\]\[52\]\[Applets\]\[66\]\[General\]$/a hiddenItems=org.kde.plasma.clipboard' "$APPLETSRC"

nohup plasmashell --no-respawn >/tmp/plasmashell-pill.log 2>&1 &
sleep 5
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
  'var ps = panels(); var al = ["left", "center", "right", "center"]; for (var i in ps) { var p = ps[i]; p.floating = true; p.lengthMode = "fit"; p.opacity = "adaptive"; p.alignment = al[i]; if (i == 3) { p.location = "bottom"; p.height = 46; p.hiding = "autohide"; } else { p.location = "top"; p.height = 30; p.hiding = "normal"; } } "done"' >/dev/null 2>&1 || true
echo "Pildoras listas."
