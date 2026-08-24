# add vim as default editor
export EDITOR=vim
export TERMINAL=urxvt
export BROWSER=links

# Add scripts path safely
if [[ ":$PATH:" != *":$HOME/Scripts:"* ]]; then
    export PATH="$PATH:$HOME/Scripts"
fi

# Prompt/ls colors — ANSI indices only, so they render via the Nord palette
# already set in .Xresources (URxvt.color0-15) instead of duplicating hex here.
PS1='\[\e[1;35m\]\u@\h\[\e[0m\] \[\e[1;34m\]\w\[\e[0m\]\$ '
export LS_COLORS='di=1;34:ln=1;36:ex=1;32'

alias ls='ls --color=auto'

# Package sizes
alias pkg_size="pacman -Qi | awk '/^Name/{n=\$3} /^Installed Size/{print \$4\$5\"\t\"n}' | sort -hr"

# Pacman upgrades
alias update='sudo pacman -Syu'
alias updates='checkupdates'

# Works around a urxvt 9.31 regression where the prompt renders mid-window
# (blank space above it) when i3 tiles a new terminal to full height before
# urxvt's first redraw. A clear forces a proper repaint at startup.
# https://bbs.archlinux.org/viewtopic.php?id=282889
[[ "$TERM" == rxvt* ]] && clear

