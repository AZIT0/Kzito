#!/usr/bin/env bash
# Borra todo lo que instala el rice y deja KDE de fabrica (oscuro Breeze).
# Solo shell. Ojo: no hay vuelta atras (no usa backup).
set -euo pipefail

say() { echo "==> $1"; }

say "Temas y colores"
rm -rf ~/.local/share/plasma/desktoptheme/LaraCraft
rm -f ~/.local/share/color-schemes/LaraCraft.colors
rm -rf ~/.local/share/icons/Papirus ~/.local/share/icons/Papirus-Dark
rm -f ~/.local/share/konsole/LaraCraft.colorscheme ~/.local/share/konsole/LaraCraft.profile
rm -f ~/.local/share/applications/org.kde.konsole.desktop
rm -f ~/.config/kitty/kitty.conf ~/.config/alacritty/alacritty.toml
rm -f ~/.config/fastfetch/config.jsonc ~/.config/fastfetch/logo.txt
rm -f ~/.config/starship.toml
sed -i '/starship init fish | source/d' ~/.config/fish/config.fish 2>/dev/null || true
rm -rf ~/.themes/Colloid-Green-Dark
for g in ~/.config/gtk-3.0/settings.ini ~/.config/gtk-4.0/settings.ini; do
  [ -f "$g" ] && sed -i 's/^gtk-theme-name=.*/gtk-theme-name=Breeze/' "$g"
done
[ -f ~/.gtkrc-2.0 ] && sed -i 's/^gtk-theme-name=.*/gtk-theme-name="Breeze"/' ~/.gtkrc-2.0
kwriteconfig6 --file konsolerc --group "Desktop Entry" --key DefaultProfile --delete 2>/dev/null || true

say "Apariencia de fabrica (Breeze oscuro)"
kwriteconfig6 --file kdeglobals --group General --key ColorScheme BreezeDark
kwriteconfig6 --file kdeglobals --group Icons --key Theme breeze-dark
kwriteconfig6 --file plasmarc --group Theme --key name breeze-dark
kbuildsycoca6 >/dev/null 2>&1 || true

say "KWin de fabrica"
kwriteconfig6 --file kwinrc --group Plugins --key blurEnabled true
kwriteconfig6 --file kwinrc --group Plugins --key diminactiveEnabled false
kwriteconfig6 --file kwinrc --group Desktops --key Number 1
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true

say "Paneles y atajos de fabrica (se regeneran solos)"
kquitapp6 plasmashell >/dev/null 2>&1 || true
sleep 2
rm -f ~/.config/plasma-org.kde.plasma.desktop-appletsrc ~/.config/plasmashellrc ~/.config/kglobalshortcutsrc
nohup plasmashell --no-respawn >/tmp/plasmashell-unrice.log 2>&1 &
sleep 3

say "Firefox (DoH y Betterfox)"
sudo rm -f /usr/lib/firefox/distribution/policies.json /usr/lib64/firefox/distribution/policies.json
for p in ~/.config/mozilla/firefox/*.default-release ~/.mozilla/firefox/*.default-release; do
  [ -d "$p" ] && rm -f "$p/user.js"
done

echo "Listo. Cerrá sesión y entrá."
echo "Nota: los prefs de Betterfox ya escritos en prefs.js no se revierten solos."
