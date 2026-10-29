#!/bin/bash

THEME=$1
if [ -z "$THEME" ]; then
  echo "Usage: ./switch-theme.sh <theme-name>"
  echo "Available themes: tokyo-night, gruvbox, catppuccin, nord, dracula"
  echo "                  one-dark, rose-pine, everforest, monokai-pro, kanagawa, pitch-black"
  exit 1
fi

THEME_DIR="$HOME/.config/themes/$THEME"

if [ ! -d "$THEME_DIR" ]; then
  echo "Error: Theme '$THEME' does not exist."
  exit 1
fi

# 1. Update the master symlink for includes
ln -sfn "$THEME_DIR" "$HOME/.config/themes/current"

# 2. Symlink Starship directly (since it doesn't support includes)
ln -sf "$THEME_DIR/starship.toml" "$HOME/.config/starship.toml"

# 3. Compile configs for apps that do not support "include" properly on this version
cat "$HOME/.config/fuzzel/fuzzel.ini.base" "$THEME_DIR/fuzzel-colors.ini" > "$HOME/.config/fuzzel/fuzzel.ini"
cat "$HOME/.config/mako/config.base" "$THEME_DIR/mako-colors" "$HOME/.config/mako/config.categories" > "$HOME/.config/mako/config"
# OSD progress fill: the theme's accent, translucent so the text stays readable
ACCENT=$(grep -oP '@define-color accent \K#[0-9a-fA-F]{6}' "$THEME_DIR/waybar-colors.css")
printf '\n[category=osd]\nprogress-color=over %s55\n' "$ACCENT" >> "$HOME/.config/mako/config"

# 4. Reload daemons to apply changes live (skipped outside sway, e.g. during install)
[ -z "$SWAYSOCK" ] && exit 0
pkill -x waybar  # sway restarts it on reload, picking up the new colors
swaymsg reload
makoctl reload
touch ~/.config/foot/foot.ini # Force foot to reload colors live

notify-send -u normal -a "Theme Engine" "Theme Switched" "Active theme is now: $THEME"