# Load common configuration. aliases exports functions
for file in ~/.config/common/.{aliases,exports,functions}; do
    [ -r "$file" ] && [ -f "$file" ] && source "$file"
done
unset file

# Autocorrect typos in path names when using `cd`.
shopt -s cdspell

# Case-insensitive globbing (used in pathname expansion).
shopt -s nocaseglob

# Bash attempts to save all lines of a multiple-line command in the same history entry.
# This allows easy re-editing of multi-line commands.
shopt -s cmdhist

# Check the window size after each command and, if necessary,
# update the values of lines and columns.
shopt -s checkwinsize

# Bash prompt.
if [ "$color_prompt" = yes ]; then
    PS1='\n\[\e[36m\]\w$(__git_ps1 "\[\033[00m\] on \[\e[35m\] %s")\[\033[00m\]\n$ '
else
    PS1='\n\[\e[36m\]\w$(__git_ps1 "\[\033[00m\] on \[\e[35m\] %s")\[\033[00m\]\n$ '
fi
unset color_prompt force_color_prompt

# Bash completion.
if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        source /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        source /etc/bash_completion
    fi
fi

# dircolors.
setup-dircolors

# Integrated fzf
if [ -x "$(command -v fzf)" ]; then
    [ ! -d "$HOME/.config/fzf/shell" ] && mkdir -p "$HOME/.config/fzf/shell" >/dev/null
    [ ! -f "$HOME/.config/fzf/shell/key-bindings.bash" ] && cp /usr/share/doc/fzf/examples/key-bindings.bash "$HOME/.config/fzf/shell/" >/dev/null
    [ -f "$HOME/.config/fzf/shell/key-bindings.bash" ] && source "$HOME/.config/fzf/shell/key-bindings.bash"
fi

# Base16 Shell.
[ -f ~/.local/bin/base16-oxide ] && source ~/.local/bin/base16-oxide
