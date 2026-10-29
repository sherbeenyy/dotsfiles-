#!/bin/bash
# Set up the sway rice on a fresh Debian install.
#
#   ./install.sh            everything below, in order
#   ./install.sh packages   apt packages + tools not in Debian (starship, satty, helix, yazi)
#   ./install.sh fonts      Iosevka / JetBrainsMono / Symbols Nerd Fonts
#   ./install.sh shell      oh-my-zsh + plugins, zsh as login shell
#   ./install.sh links      symlink home/ into $HOME (existing files are backed up)
#   ./install.sh theme      apply the theme and GTK settings
#   ./install.sh session    "Sway (NVIDIA Optimized)" login session
#   ./install.sh nvidia     NVIDIA driver (enables contrib/non-free)
#   ./install.sh greeter    greetd + tuigreet login screen
#
# Every step is safe to re-run.

set -uo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEME="${THEME:-rose-pine}"
BIN="$HOME/.local/bin"

say()  { printf '\n\033[1;35m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m  ! %s\033[0m\n' "$*"; }
ask()  { read -rp "$1 [y/N] " r; [[ $r == [yY]* ]]; }

APT_PACKAGES=(
    # sway desktop
    sway swaybg swaylock swayidle waybar foot fuzzel mako-notifier libnotify-bin
    wl-clipboard cliphist grim slurp wl-mirror brightnessctl jq psmisc
    xdg-desktop-portal-wlr xdg-desktop-portal-gtk gnome-keyring
    dconf-gsettings-backend libglib2.0-bin
    # audio / network
    pipewire pipewire-pulse pipewire-audio wireplumber
    network-manager network-manager-gnome
    # look
    yaru-theme-gtk yaru-theme-icon adwaita-icon-theme
    fonts-noto-core fonts-noto-color-emoji fontconfig
    # shell & terminal tools
    zsh tmux fzf ripgrep zoxide btop kitty gh git curl wget unzip xz-utils
    python3 python3-rich pipx
    # tools that may or may not be packaged; fall back to GitHub releases below
    satty hx
)

# Download the newest GitHub release asset whose name matches a regex, print the file path
gh_release() {
    local repo=$1 pattern=$2 url out
    url=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
        | jq -r --arg p "$pattern" '.assets[] | select(.name | test($p)) | .browser_download_url' | head -n1)
    [ -z "$url" ] && { warn "no release asset in $repo matching $pattern"; return 1; }
    out="$(mktemp -d)/$(basename "$url")"
    curl -fsSL -o "$out" "$url" && echo "$out"
}

step_packages() {
    say "apt packages"
    sudo apt-get update
    local available=() missing=()
    for p in "${APT_PACKAGES[@]}"; do
        if apt-cache show "$p" >/dev/null 2>&1; then available+=("$p"); else missing+=("$p"); fi
    done
    sudo apt-get install -y "${available[@]}"
    [ ${#missing[@]} -gt 0 ] && warn "not in apt, handled below if possible: ${missing[*]}"

    mkdir -p "$BIN"

    if ! command -v starship >/dev/null; then
        say "starship"
        curl -fsSL https://starship.rs/install.sh | sh -s -- -y
    fi

    if ! command -v satty >/dev/null; then
        say "satty (screenshot editor)"
        local f; f=$(gh_release gabm/Satty 'x86_64.*linux.*\.tar\.gz$') && {
            local d; d=$(dirname "$f"); tar -xzf "$f" -C "$d"
            install -m755 "$(find "$d" -type f -name satty | head -n1)" "$BIN/satty"
        }
        sudo apt-get install -y libgtk-4-1 libadwaita-1-0 >/dev/null 2>&1
    fi

    if ! command -v hx >/dev/null; then
        say "helix"
        local f; f=$(gh_release helix-editor/helix 'x86_64-linux\.tar\.xz$') && {
            rm -rf "$HOME/.local/share/helix-bin" && mkdir -p "$HOME/.local/share/helix-bin"
            tar -xJf "$f" -C "$HOME/.local/share/helix-bin" --strip-components=1
            ln -sf "$HOME/.local/share/helix-bin/hx" "$BIN/hx"
        }
    fi

    if ! command -v yazi >/dev/null; then
        say "yazi (file manager)"
        local f; f=$(gh_release sxyazi/yazi 'yazi-x86_64-unknown-linux-gnu\.zip$') && {
            local d; d=$(dirname "$f"); unzip -oq "$f" -d "$d"
            install -m755 "$(find "$d" -type f -name yazi | head -n1)" "$BIN/yazi"
            install -m755 "$(find "$d" -type f -name ya | head -n1)" "$BIN/ya"
        }
    fi

    # brightnessctl needs write access to the backlight
    sudo usermod -aG video "$USER"
}

step_fonts() {
    say "Nerd Fonts"
    local dir="$HOME/.local/share/fonts"
    mkdir -p "$dir"
    for font in Iosevka JetBrainsMono NerdFontsSymbolsOnly; do
        if [ -d "$dir/$font" ]; then echo "  $font already installed"; continue; fi
        echo "  downloading $font"
        mkdir -p "$dir/$font"
        curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$font.tar.xz" \
            | tar -xJ -C "$dir/$font" || warn "failed to download $font"
    done
    fc-cache -f >/dev/null
}

step_shell() {
    say "oh-my-zsh"
    [ -d "$HOME/.oh-my-zsh" ] || git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
    local plugins="$HOME/.oh-my-zsh/custom/plugins"
    for repo in zsh-users/zsh-autosuggestions zsh-users/zsh-syntax-highlighting zsh-users/zsh-history-substring-search; do
        [ -d "$plugins/${repo#*/}" ] || git clone --depth 1 "https://github.com/$repo.git" "$plugins/${repo#*/}"
    done
    if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$(command -v zsh)" ]; then
        chsh -s "$(command -v zsh)"
    fi
}

step_links() {
    say "linking dotfiles"
    local backup="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)" src rel target
    while IFS= read -r -d '' src; do
        rel="${src#"$DOTFILES/home/"}"
        target="$HOME/$rel"
        [ "$(readlink "$target")" = "$src" ] && continue
        if [ -e "$target" ] || [ -L "$target" ]; then
            mkdir -p "$backup/$(dirname "$rel")"
            mv "$target" "$backup/$rel"
        fi
        mkdir -p "$(dirname "$target")"
        ln -s "$src" "$target"
        echo "  $rel"
    done < <(find "$DOTFILES/home" \( -type f -o -type l \) -print0)
    [ -d "$backup" ] && echo "  old files moved to $backup"

    # sway includes this before display.sh has generated it
    touch "$HOME/.config/sway/display-workspaces.conf"
}

step_theme() {
    say "theme: $THEME"
    local current; current=$(basename "$(readlink "$HOME/.config/themes/current" 2>/dev/null)")
    "$HOME/.config/themes/switch-theme.sh" "${current:-$THEME}"

    local gs="gsettings"
    [ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ] && gs="dbus-run-session -- gsettings"
    $gs set org.gnome.desktop.interface gtk-theme 'Yaru-blue-dark'
    $gs set org.gnome.desktop.interface icon-theme 'Yaru-blue'
    $gs set org.gnome.desktop.interface cursor-theme 'Adwaita'
    $gs set org.gnome.desktop.interface color-scheme 'prefer-dark'
}

step_session() {
    say "sway-nvidia login session"
    sudo tee /usr/share/wayland-sessions/sway-nvidia.desktop >/dev/null <<EOF
[Desktop Entry]
Name=Sway (NVIDIA Optimized)
Comment=An i3-compatible Wayland compositor with NVIDIA fixes
Exec=$HOME/.local/bin/sway-nvidia
Type=Application
EOF
}

step_nvidia() {
    say "NVIDIA driver"
    ask "Install the proprietary NVIDIA driver (adds contrib/non-free to apt)?" || return 0
    if [ -f /etc/apt/sources.list.d/debian.sources ]; then
        sudo sed -i.bak -E '/^Components:/{/contrib/!s/main/main contrib/; /non-free( |$)/!s/$/ non-free/}' \
            /etc/apt/sources.list.d/debian.sources
    fi
    if [ -f /etc/apt/sources.list ]; then
        sudo sed -i.bak -E '/^deb/{/contrib/!s/ main/ main contrib/; / non-free( |$)/!s/$/ non-free/}' /etc/apt/sources.list
    fi
    sudo apt-get update
    sudo apt-get install -y linux-headers-amd64 nvidia-driver firmware-misc-nonfree nvidia-suspend-common
    sudo install -m644 "$DOTFILES/system/nvidia.conf" /etc/modprobe.d/nvidia-rice.conf
    sudo update-initramfs -u
    warn "reboot to load the NVIDIA driver"
}

step_greeter() {
    say "greetd login screen"
    ask "Use greetd + tuigreet as the login screen (replaces any other display manager)?" || return 0
    sudo apt-get install -y greetd tuigreet
    sudo install -m644 "$DOTFILES/system/greetd-config.toml" /etc/greetd/config.toml
    for dm in gdm3 sddm lightdm; do
        systemctl is-enabled "$dm" >/dev/null 2>&1 && sudo systemctl disable "$dm"
    done
    sudo systemctl enable greetd
}

ALL=(packages fonts shell links theme session nvidia greeter)
steps=("$@"); [ ${#steps[@]} -eq 0 ] && steps=("${ALL[@]}")
for s in "${steps[@]}"; do
    if declare -f "step_$s" >/dev/null; then "step_$s"; else warn "unknown step: $s"; exit 1; fi
done
say "done — log out and pick \"Sway (NVIDIA Optimized)\""
