# Dotfiles

Personal dotfiles managed with GNU Stow.

The repository is organized by module. Each top-level directory mirrors paths
under `$HOME`, so `stow` can link files into place without copying them.

## Requirements

- Debian/Ubuntu or another apt-based Linux distribution
- `bash`
- `git`
- `sudo`

The installer can install missing packages with `apt-get`, including `stow`,
`zsh`, `tmux`, `neovim`, `bat`, `fzf`, `ripgrep`, `alacritty`, and related
tools.

## Install

Preview all actions first:

```sh
./dotfiles.sh --dry-run
```

Install dependencies and link all configured modules:

```sh
./dotfiles.sh
```

Skip confirmation prompts:

```sh
./dotfiles.sh --yes
```

Run a specific mode:

```sh
./dotfiles.sh install
./dotfiles.sh backup
./dotfiles.sh link
```

The equivalent long-form syntax is also supported:

```sh
./dotfiles.sh --mode install
./dotfiles.sh --mode backup
./dotfiles.sh --mode link
```

Available modes:

- `full` - install dependencies and plugins, back up conflicts, then link modules. This is the default.
- `install` - install apt packages, Oh My Zsh, Neovim plugin manager, tmux plugins, and related plugins only.
- `backup` - move conflicting target files into `~/.dotfiles_backup` only.
- `link` - back up conflicts, then link modules with Stow only.

## Backup Behavior

Before linking files, the installer checks for existing target files in
`$HOME`.

If a target already points to the matching file in this repository, it is left
alone. Other existing files or symlinks are moved into a timestamped backup
directory:

```text
~/.dotfiles_backup/YYYYMMDD-HHMMSS/
```

The installer prints each move before continuing:

```text
/home/user/.bashrc -> /home/user/.dotfiles_backup/YYYYMMDD-HHMMSS/.bashrc
```

If a backup path already exists, the script appends a numeric suffix rather
than overwriting it.

## Modules

- `bash` - Bash startup configuration
- `zsh` - Zsh and Oh My Zsh configuration
- `common` - shared aliases, exports, and functions
- `bin` - scripts installed into `~/.local/bin`
- `git` - global Git configuration and ignore rules
- `ssh` - SSH config entry point
- `tmux` - tmux configuration
- `nvim` - Neovim configuration
- `vim` - Vim configuration
- `dircolors` - custom `LS_COLORS`
- `bat`, `glow`, `htop`, `ripgrep`, `wget`, `yt-dlp`, `alacritty` - app-specific configuration

## Local Private Configuration

Machine-specific or private settings should stay outside the repository. The
tracked config loads these optional local files when present:

- `~/.config/common/.aliases.local`
- `~/.config/common/.exports.local`
- `~/.config/common/.functions.local`
- `~/.config/zsh/.zshrc.local`
- `~/.config/git/.gitconfig.local`
- `~/.ssh/config.local`

Files matching `*.local`, `*.secret`, `*.private`, and `.env*` are ignored by
default.

## Maintenance

Relink a single module manually:

```sh
stow --no-folding -d "$HOME/.dotfiles" -R -t "$HOME" zsh
```

Check what Stow would do without modifying files:

```sh
stow -n --no-folding -d "$HOME/.dotfiles" -R -t "$HOME" zsh
```

Run a shell syntax check for repository scripts:

```sh
bash -n dotfiles.sh bin/.local/bin/update bin/.local/bin/update-beauty bin/.local/bin/cleaner bin/.local/bin/rofi-calendar bin/.local/bin/sizeof
```

Install or refresh external plugin managers:

```sh
./dotfiles.sh install
```

Neovim uses `lazy.nvim`, installed at:

```text
~/.local/share/nvim/lazy/lazy.nvim
```

`./dotfiles.sh install` installs `lazy.nvim` and runs a headless `Lazy! sync`
against the repository's `nvim/.config/nvim/init.lua`. Normal Neovim startup
does not auto-install missing plugins; that behavior is enabled only during the
installer sync. After changing Neovim plugin specs later, run `:Lazy sync`
inside Neovim or run `./dotfiles.sh install` again.

tmux plugins are installed under:

```text
~/.config/tmux/plugins/
```

The tmux config only loads TPM when it already exists; it does not clone
plugins during tmux startup.

## Notes

The installer is intentionally tailored for personal apt-based systems. On
other platforms, prefer using `stow` manually or adapt `dotfiles.sh` before
running it.
