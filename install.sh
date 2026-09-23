#!/usr/bin/env bash
# LaraCraft Rice — Jade / Stone / Antique Gold para KDE Plasma 6
# Todo en shell. Uso: ./install.sh [--skip-panel]
# Requiere: plasma 6, git, gdbus, qdbus6. 100% shell, sin Python.
set -euo pipefail

RICE_DIR="$(cd "$(dirname "$0")" && pwd)"
SKIP_PANEL=0
for a in "$@"; do
  case "$a" in
    --skip-panel) SKIP_PANEL=1 ;;
  esac
done

need() { command -v "$1" >/dev/null 2>&1 || { echo "Falta: $1"; exit 1; }; }
say() { echo "==> $1"; }
need plasma-apply-colorscheme; need kwriteconfig6; need qdbus6; need gdbus; need git

echo "Kzito: aplica el rice directo (sin backup)."

# ---- 0. Base: flatpak + chaotic-aur (pide sudo) ----
say "Base del sistema"
[ -f /etc/os-release ] && . /etc/os-release
IS_ARCH=0; IS_FEDORA=0
case "${ID:-} ${ID_LIKE:-}" in
  *arch*) IS_ARCH=1 ;;
  *fedora*|*rhel*|*centos*|*nobara*) IS_FEDORA=1 ;;
esac
pkg() {
  if [ "$IS_ARCH" -eq 1 ]; then sudo pacman -S --needed --noconfirm "$@"
  elif [ "$IS_FEDORA" -eq 1 ]; then sudo dnf install -y "$@"
  else echo "Distro no soportada: ${ID:-?}"; exit 1; fi
}
pkg flatpak git curl
command -v kitty >/dev/null || pkg kitty
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
if [ "$IS_ARCH" -eq 1 ] && ! grep -q "^\[chaotic-aur\]" /etc/pacman.conf; then
  sudo pacman-key --recv-keys 3056513887B78AEB --keyserver keyserver.ubuntu.com
  sudo pacman-key --lsign-key 3056513887B78AEB
  sudo pacman -U --noconfirm \
    'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' \
    'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
  printf '\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n' | sudo tee -a /etc/pacman.conf
  sudo pacman -Sy
fi

# ---- 1. Color scheme ----
say "Colores LaraCraft"
mkdir -p ~/.local/share/color-schemes
cp "$RICE_DIR/themes/LaraCraft.colors" ~/.local/share/color-schemes/
plasma-apply-colorscheme LaraCraft
kwriteconfig6 --file kdeglobals --group General --key ColorScheme LaraCraft

# ---- 2. Tema Plasma (Breeze + paleta LaraCraft) ----
say "Tema Plasma LaraCraft"
mkdir -p ~/.local/share/plasma/desktoptheme
rm -rf ~/.local/share/plasma/desktoptheme/LaraCraft
cp -r /usr/share/plasma/desktoptheme/default ~/.local/share/plasma/desktoptheme/LaraCraft
cp "$RICE_DIR/themes/LaraCraft.colors" ~/.local/share/plasma/desktoptheme/LaraCraft/colors
sed -i 's/"Name": "[^"]*"/"Name": "LaraCraft"/; s/"Description": "[^"]*"/"Description": "Jade Stone Antique Gold fan theme"/' \
  ~/.local/share/plasma/desktoptheme/LaraCraft/metadata.json
# fondo redondeado tambien al maximizar (variantes opaque/solid)
for v in opaque solid; do
  cp /usr/share/plasma/desktoptheme/default/translucent/widgets/panel-background.svgz \
    ~/.local/share/plasma/desktoptheme/LaraCraft/$v/widgets/panel-background.svgz
done
# pildoras mas translucidas (0.85 -> 0.65, iconos intactos)
PB=~/.local/share/plasma/desktoptheme/LaraCraft/translucent/widgets/panel-background.svgz
zcat "$PB" | sed 's/opacity:0\.85/opacity:0.65/g' | gzip -c > "$PB.new" && mv "$PB.new" "$PB"
kwriteconfig6 --file plasmarc --group Theme --key name LaraCraft

# ---- 3. Iconos Papirus-Dark con carpetas verdes ----
say "Iconos Papirus-Dark verdes"
if [ ! -d ~/.local/share/icons/Papirus-Dark ]; then
  git clone --depth 1 https://github.com/PapirusDevelopmentTeam/papirus-icon-theme.git /tmp/papirus-icon-theme
  cp -r /tmp/papirus-icon-theme/Papirus /tmp/papirus-icon-theme/Papirus-Dark ~/.local/share/icons/
fi
verdes=0
while IFS= read -r -d '' link; do
  tgt=$(readlink "$link")
  case "$tgt" in
    *folder-blue*)
      new="${tgt//folder-blue/folder-green}"
      if [ -e "$(dirname "$link")/$new" ]; then
        ln -sfn "$new" "$link" && verdes=$((verdes + 1))
      fi ;;
  esac
done < <(find ~/.local/share/icons/Papirus ~/.local/share/icons/Papirus-Dark -type l -print0)
echo "Carpetas verdes: $verdes"
kwriteconfig6 --file kdeglobals --group Icons --key Theme Papirus-Dark
kbuildsycoca6 >/dev/null 2>&1 || true

# ---- 4. Terminales (Konsole + Alacritty + Kitty + fastfetch) ----
say "Terminales"
mkdir -p ~/.local/share/konsole ~/.config/alacritty
cp "$RICE_DIR/config/konsole/LaraCraft.colorscheme" "$RICE_DIR/config/konsole/LaraCraft.profile" ~/.local/share/konsole/
cp "$RICE_DIR/config/alacritty/alacritty.toml" ~/.config/alacritty/alacritty.toml

# Kitty como terminal principal (Super+Enter lo abre)
command -v kitty >/dev/null || pkg kitty
mkdir -p ~/.config/kitty ~/.local/share/applications
cp "$RICE_DIR/config/kitty/kitty.conf" ~/.config/kitty/kitty.conf
cp "$RICE_DIR/config/applications/org.kde.konsole.desktop" ~/.local/share/applications/
kbuildsycoca6 >/dev/null 2>&1 || true

# Fastfetch con logo propio
command -v fastfetch >/dev/null || pkg fastfetch
mkdir -p ~/.config/fastfetch
cp "$RICE_DIR/config/fastfetch/config.jsonc" "$RICE_DIR/config/fastfetch/logo.txt" ~/.config/fastfetch/

# ---- 4d. Starship (binario local + prompt LaraCraft) ----
say "Starship"
mkdir -p ~/.local/bin
[ -x ~/.local/bin/starship ] || curl -fSL --max-time 90 -o /tmp/starship.tar.gz \
  "https://github.com/starship/starship/releases/latest/download/starship-x86_64-unknown-linux-musl.tar.gz" \
  && tar -xzf /tmp/starship.tar.gz -C ~/.local/bin/ starship
cp "$RICE_DIR/config/starship/starship.toml" ~/.config/starship.toml 2>/dev/null || { mkdir -p ~/.config; cp "$RICE_DIR/config/starship/starship.toml" ~/.config/starship.toml; }
grep -q "starship init" ~/.config/fish/config.fish 2>/dev/null || {
  mkdir -p ~/.config/fish
  printf 'export PATH="$HOME/.local/bin:$PATH"\nstarship init fish | source\n' >> ~/.config/fish/config.fish
}

# ---- 4e. GTK Colloid verde (compila con sassc) ----
say "GTK verde"
command -v sassc >/dev/null || pkg sassc
if [ ! -d ~/.themes/Colloid-Green-Dark ]; then
  git clone --depth 1 https://github.com/vinceliuice/Colloid-gtk-theme.git /tmp/colloid-gtk
  bash /tmp/colloid-gtk/install.sh -t green -c dark -d ~/.themes -l
fi
for g in ~/.config/gtk-3.0/settings.ini ~/.config/gtk-4.0/settings.ini; do
  mkdir -p "$(dirname "$g")"; touch "$g"
  sed -i '/^gtk-theme-name=/d' "$g"
  echo "gtk-theme-name=Colloid-Green-Dark" >> "$g"
done
grep -q '^gtk-theme-name=' ~/.gtkrc-2.0 2>/dev/null \
  && sed -i 's/^gtk-theme-name=.*/gtk-theme-name="Colloid-Green-Dark"/' ~/.gtkrc-2.0 \
  || echo 'gtk-theme-name="Colloid-Green-Dark"' >> ~/.gtkrc-2.0

# ---- 5. KWin: blur + dim + 5 escritorios ----
say "KWin"
kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled true
kwriteconfig6 --file kwinrc --group Plugins --key diminactiveEnabled true
kwriteconfig6 --file kwinrc --group Effect-Blur --key Strength 8
kwriteconfig6 --file kwinrc --group Effect-DimInactive --key Strength 10
kwriteconfig6 --file kwinrc --group org.kde.kdecoration2 --key library org.kde.breeze --key theme Breeze
kwriteconfig6 --file kwinrc --group Desktops --key Number 5
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true

# ---- 6. Wallpaper (no pisa el tuyo si ya existe) ----
say "Wallpaper"
mkdir -p ~/Pictures/Wallpapers
cp -n "$RICE_DIR/wallpapers/lara-tomb-jungle.png" ~/Pictures/Wallpapers/ 2>/dev/null || true
plasma-apply-wallpaperimage ~/Pictures/Wallpapers/lara-tomb-jungle.png >/dev/null 2>&1 || true
# fondo disponible para la pantalla de inicio (elegilo en Ajustes > Pantalla de inicio de sesion)
sudo cp -n "$RICE_DIR/wallpapers/lara-tomb-jungle.png" /usr/share/wallpapers/ 2>/dev/null || true

# ---- 7. Barras pildora (reinicia plasmashell) ----
say "Barras pildora"
if [ "$SKIP_PANEL" -eq 0 ]; then
  bash "$RICE_DIR/tools/pill-bar.sh"
fi

# ---- 8. Atajos del config.kksrc (en vivo) ----
say "Atajos"
bash "$RICE_DIR/config/shortcuts/apply-kksrc.sh" "$RICE_DIR/config/shortcuts/config.kksrc"

# ---- 9. Betterfox (descargado del repo, requiere Firefox/Zen cerrados) ----
say "Betterfox"
step_firefox() {
  local prof n=0
  for prof in ~/.config/mozilla/firefox/*.default-release ~/.mozilla/firefox/*.default-release ~/.zen/*.default; do
    [[ -d "$prof" ]] || continue
    cp "$prof/prefs.js" "$prof/prefs.js.bak" 2>/dev/null || true
    curl -fSL --max-time 60 -o "$prof/user.js" "https://raw.githubusercontent.com/yokoffing/Betterfox/main/user.js" || continue
    n=$((n + 1))
  done
  echo "Perfiles con Betterfox: $n"
}
if pgrep -x firefox >/dev/null || pgrep -x zen >/dev/null; then
  echo "Firefox/Zen abierto: cerralo y corre de nuevo el script."
else
  step_firefox
fi

echo "Rice aplicado."
