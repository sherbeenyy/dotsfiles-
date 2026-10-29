
# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Theme
# ZSH_THEME="powerlevel10k/powerlevel10k"

# Which plugins to load
plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
  zsh-history-substring-search
  fzf
)

source $ZSH/oh-my-zsh.sh

#aliases
alias chipcode='/opt/microchip/mplabx/v6.30/mplab_platform/bin/mplab_ide'
alias clion='/home/ahmed/Downloads/clion-2026.1.1/bin/clion'
alias ai="ollama run qwen3-64k"
alias ai-c="ollama run qwen3-c"
alias ai-linux="ollama run qwen3-linux"
alias mariam="cat /home/ahmed/somthingcoolformariam/asciify/img/output2_full_ultra.txt"
# md: render markdown files in the terminal (Tab-completes .md files and folders)
unalias md 2>/dev/null
md() { python3 -m rich.markdown "$@"; }
compdef '_files -g "*.(md|markdown)(-.)"' md

# Beaver notes alias (as a function to support arguments)
beaver() {
  nohup "/opt/Beaver Notes/beaver-notes" --no-sandbox "$@" >/dev/null 2>&1 &
}

# ─── Autosuggestions ────────────────────────────────────────────────────────
# Accept the ghost suggestion with → arrow key
bindkey '→' autosuggest-accept
# Make suggestion color visible (gray)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#888888"

# ─── History substring search ───────────────────────────────────────────────
# Type part of a command, then press ↑ / ↓ to search through matching history
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

# ─── fzf ────────────────────────────────────────────────────────────────────
# Ctrl+R → fuzzy search history
# Ctrl+T → fuzzy search files in current directory
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# ─── History settings ────────────────────────────────────────────────────────
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_DUPS       # don't save duplicate commands
setopt HIST_IGNORE_SPACE      # don't save commands that start with a space
setopt SHARE_HISTORY          # share history between all open terminals

# User configuration
# export MANPATH="/usr/local/man:$MANPATH"
# export LANG=en_US.UTF-8



# Created by `pipx` on 2026-05-09 21:02:07
export PATH="$PATH:/home/ahmed/.local/bin"

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/home/ahmed/miniconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/home/ahmed/miniconda3/etc/profile.d/conda.sh" ]; then
        . "/home/ahmed/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="/home/ahmed/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<



# Added by Antigravity CLI installer
export PATH="/home/ahmed/.local/bin:$PATH"

# Pi
export PATH="/home/ahmed/.local/share/pi-node/node-v22.23.1-linux-x64/bin:$PATH"
export PATH="$HOME/system/Odin:$PATH"




#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

# Starship Prompt

# Yazi shell wrapper (cds to folder upon exit)
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	yazi "$@" --cwd-file="$tmp"
	if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
		builtin cd -- "$cwd"
	fi
	rm -f -- "$tmp"
}
eval "$(starship init zsh)"
# Terminal cat: greeting + mood face in the prompt (see ~/.config/zsh/pet.zsh)
source ~/.config/zsh/pet.zsh
export PATH="$HOME/.cargo/bin:/usr/local/bin:$PATH"
alias theme='~/.config/themes/switch-theme.sh'

# Machine-specific settings and secrets (not in the dotfiles repo)
[ -f ~/.zshrc.local ] && source ~/.zshrc.local
