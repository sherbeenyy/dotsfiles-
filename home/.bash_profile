if [[ $- == *i* && -s ~/.bashrc ]]; then
	source ~/.bashrc
fi
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"


# Added by Antigravity CLI installer
export PATH="/home/ahmed/.local/bin:$PATH"

export WLR_DRM_NO_ATOMIC=1
export WLR_NO_HARDWARE_CURSORS=1
