# Themes.
ZSH_THEME="af-magic"

# Case-sensitive completion.
CASE_SENSITIVE="true"

# Initialize completion system
autoload -Uz compinit
compinit

# Enable case-insensitive completion
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# Enable interactive completion menu
zstyle ':completion:*' menu select

# Enable colored completion list
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}

# Enable completion cache
zstyle ':completion:*' use-cache yes
zstyle ':completion:*' cache-path ~/.cache/zsh

# Disable bi-weekly auto-update checks.
zstyle ':omz:update' mode disabled

# Disable auto-setting terminal title.
DISABLE_AUTO_TITLE="true"

# Disable URL backslash escaping
DISABLE_MAGIC_FUNCTIONS="true"

# Disable marking untracked files under VCS as dirty.
DISABLE_UNTRACKED_FILES_DIRTY="true"

# History.
HIST_STAMPS="yyyy-mm-dd"

# Plugins.
plugins=(
	z
	archive
	extract
	git
	autojump
	zsh-autosuggestions
	zsh-syntax-highlighting
	)

# exports
[ -f ~/.config/common/.exports ] && source ~/.config/common/.exports

# Oh My Zsh.
if [ -n "${ZSH:-}" ] && [ -r "$ZSH/oh-my-zsh.sh" ]; then
    source "$ZSH/oh-my-zsh.sh"
else
    print -u2 "Oh My Zsh not found. Run ./dotfiles.sh install to install it."
fi

# setopt.zsh aliases functions
[ -f ~/.config/zsh/setopt.zsh ] && source ~/.config/zsh/setopt.zsh
[ -f ~/.config/common/.aliases ] && source ~/.config/common/.aliases
[ -f ~/.config/common/.functions ] && source ~/.config/common/.functions

# zshrc.local
[ -f ~/.config/zsh/.zshrc.local ] && source ~/.config/zsh/.zshrc.local

# dircolors.
if (( $+functions[setup-dircolors] )); then
    setup-dircolors
fi

# Integrated fzf
if [ -x "$(command -v fzf)" ]; then
    [ ! -d "$HOME/.config/fzf/shell" ] && mkdir -p "$HOME/.config/fzf/shell" >/dev/null
    [ ! -f "$HOME/.config/fzf/shell/key-bindings.zsh" ] && [ -r /usr/share/doc/fzf/examples/key-bindings.zsh ] && cp /usr/share/doc/fzf/examples/key-bindings.zsh "$HOME/.config/fzf/shell/" >/dev/null
    [ -f "$HOME/.config/fzf/shell/key-bindings.zsh" ] && source "$HOME/.config/fzf/shell/key-bindings.zsh"
fi

# Base16 Shell.
[ -f ~/.local/bin/base16-oxide ] && source ~/.local/bin/base16-oxide
