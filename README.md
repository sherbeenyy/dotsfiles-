# dotfiles

Sway rice: sway · waybar · foot · fuzzel · mako · swaylock · satty · starship · oh-my-zsh,
with 11 switchable themes (`Alt+T` or `theme <name>`).

## Fresh Debian install

1. Install Debian with the netinst image. In the "Software selection" step **untick every
   desktop environment**, keep only *standard system utilities*.
2. Log in on the TTY, then:

   ```sh
   sudo apt install git
   git clone <this repo> ~/dotfiles
   cd ~/dotfiles && ./install.sh
   ```

3. Put secrets / machine-only stuff in `~/.zshrc.local` (sourced by `.zshrc`, never committed).
4. Reboot and choose **Sway (NVIDIA Optimized)** at the login screen.

Steps can be run one at a time: `./install.sh links`, `./install.sh fonts`, … (see the top of `install.sh`).

## Layout

| Path | What |
| --- | --- |
| `home/` | Mirrors `$HOME`. Every file is symlinked into place, so editing `~/.config/...` edits the repo. |
| `system/` | Files for `/etc` (NVIDIA modprobe options, greetd config). |
| `packages/` | What was installed on the old Ubuntu, for reference (apt + snaps). |

Generated per machine and ignored by git: `themes/current`, `starship.toml`, `fuzzel/fuzzel.ini`,
`mako/config` (built by `switch-theme.sh`), and sway's display `*.state` files.

## Adding a new config

```sh
mkdir -p ~/dotfiles/home/.config/foo
mv ~/.config/foo/foo.conf ~/dotfiles/home/.config/foo/
cd ~/dotfiles && ./install.sh links
```

## Not automated

Apps that were snaps on Ubuntu (Brave, VS Code, Discord, Spotify, Zoom, Todoist) — install them from
Flatpak/Flathub or their own `.deb` repos. `packages/ubuntu-apt-manual.txt` lists the rest.
