# ~/.bashrc — Basic Bash with bold colors

# If not running interactively, do nothing
case $- in
    *i*) ;;
    *) return;;
esac

# ---- Enable color for ls and grep ----
if [ -x /usr/bin/dircolors ]; then
    test -r ~/.dircolors && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
fi

alias ls='ls --color=auto'
alias ll='ls -alF --color=auto'
alias la='ls -A --color=auto'
alias l='ls -CF --color=auto'


alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# ---- Default bold colored Bash prompt ----
# Custom Bash prompt: username green, @ blue, hostname default, path blue
PS1="\[\e[1;32m\]\u\[\e[0m\]\[\e[1;34m\]@\[\e[0m\]\[\e[1;34m\]\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ "


# ---- Enable bash completion if available ----
if [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
fi

# ---- Useful aliases ----
alias ..='cd ..'
alias ...='cd ../..'
alias h='history'
alias chipcode='/opt/microchip/mplabx/v6.30/mplab_platform/bin/mplab_ide'

# ---- End of .bashrc ----
source /opt/ros/jazzy/setup.bash
source ~/coding/ros_workspaces/learning/install/setup.bash


export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/home/ahmed/miniconda3/bin/conda' 'shell.bash' 'hook' 2> /dev/null)"
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

[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"


# Added by Antigravity CLI installer
export PATH="/home/ahmed/.local/bin:$PATH"
export PATH="$HOME/system/Odin:$PATH"

#THIS MUST BE AT THE END OF THE FILE FOR SDKMAN TO WORK!!!
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

# Starship Prompt
eval "$(starship init bash)"

# Yazi shell wrapper
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	yazi "$@" --cwd-file="$tmp"
	if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
		builtin cd -- "$cwd"
	fi
	rm -f -- "$tmp"
}
alias theme='~/.config/themes/switch-theme.sh'
