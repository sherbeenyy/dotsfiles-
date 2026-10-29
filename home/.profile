# ~/.profile: executed by the command interpreter for login shells.
# This file is not read by bash(1), if ~/.bash_profile or ~/.bash_login
# exists.
# see /usr/share/doc/bash/examples/startup-files for examples.
# the files are located in the bash-doc package.

# the default umask is set in /etc/profile; for setting the umask
# for ssh logins, install and configure the libpam-umask package.
#umask 022

# if running bash
if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
	. "$HOME/.bashrc"
    fi
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/bin" ] ; then
    PATH="$HOME/bin:$PATH"
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/.local/bin" ] ; then
    PATH="$HOME/.local/bin:$PATH"
fi
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"


# Added by Antigravity CLI installer
export PATH="/home/ahmed/.local/bin:$PATH"
export NIXOS_OZONE_WL=1
export ELECTRON_OZONE_PLATFORM_HINT=auto

# export WLR_DRM_NO_ATOMIC=1  # disabled: breaks multi-GPU output on sway
export WLR_NO_HARDWARE_CURSORS=1
