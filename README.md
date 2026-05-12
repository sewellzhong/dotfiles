# Dotfiles

Personal dotfiles managed with GNU Stow.

The repository is organized by module. Each top-level directory mirrors paths
under `$HOME`, so `stow` can link files into place without copying them.

`dotfiles.sh` uses the directory that contains the script as the dotfiles root,
so the repository no longer has to live at `~/.dotfiles`. You can still set
`DOTFILES_DIR` explicitly when needed.

## Requirements

- Debian/Ubuntu or another apt-based Linux distribution
- `bash`
- `git`
- `sudo`

The installer can install missing packages with `apt-get`, including `stow`,
`zsh`, `tmux`, `neovim`, `bat`, `fzf`, `ripgrep`, `alacritty`, and related
tools.

The installer performs a small preflight before it does any work:

- install modes require `sudo`, `git`, `apt-get`, and `dpkg-query`
- link modes require `stow`, unless `full` mode will install it first
- all modes require a valid `$HOME` and dotfiles directory

Some interactive shortcuts depend on optional tools:

- `diff-so-fancy` improves `git diff` and `git show` paging. Without it, use
  Git with `--no-pager` or install dependencies with `./dotfiles.sh install`.
- `fzf` enables shell key bindings and interactive helpers. Startup skips the
  bindings when packaged example files are unavailable.
- `xclip` enables clipboard integration for tmux and shell helpers. Clipboard
  commands will fail until `xclip` is installed.

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

`--dry-run` prints commands instead of running them. It also shows any Git
dependency repairs that would be made, such as replacing a non-Git directory or
a repository with the wrong remote.

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

The installer also checks path-shape conflicts before linking. For example, if
the repository provides `~/.config/foo` as a directory but the target already
exists as a file, the installer stops and asks you to resolve it manually.

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
stow --no-folding -d "$PWD" -R -t "$HOME" zsh
```

Check what Stow would do without modifying files:

```sh
stow -n --no-folding -d "$PWD" -R -t "$HOME" zsh
```

Run a shell syntax check for repository scripts:

```sh
bash -n dotfiles.sh bin/.local/bin/update bin/.local/bin/update-beauty bin/.local/bin/cleaner bin/.local/bin/rofi-calendar bin/.local/bin/sizeof
```

Run a broader local validation pass:

```sh
./dotfiles.sh --dry-run
stow -n --no-folding -d "$PWD" -R -t "$HOME" bash zsh common git tmux nvim
nvim --headless --clean -u "$PWD/nvim/.config/nvim/init.lua" +qa
```

If `shellcheck` is installed, also run:

```sh
shellcheck dotfiles.sh bin/.local/bin/update bin/.local/bin/update-beauty bin/.local/bin/cleaner bin/.local/bin/rofi-calendar bin/.local/bin/sizeof
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

The installer follows the latest available plugin revisions by default. To pin
external Git dependencies for a reproducible install, set any of these
environment variables before running the installer:

```sh
OH_MY_ZSH_VERSION=master
LAZY_NVIM_VERSION=stable
DIFF_SO_FANCY_VERSION=v1.4.4
ZSH_AUTOSUGGESTIONS_VERSION=v0.7.1
ZSH_SYNTAX_HIGHLIGHTING_VERSION=0.8.0
ZSH_EXTRACT_VERSION=master
TPM_VERSION=master
TMUX_COPYCAT_VERSION=master
TMUX_BETTER_MOUSE_MODE_VERSION=master
./dotfiles.sh install
```

Existing Git dependencies are validated before reuse. If a dependency directory
exists but is not a Git repository, or its `origin` does not match the expected
project, the installer asks before moving it aside to a `.repair-backup.*`
directory and cloning a clean copy. GitHub proxy URLs are normalized before
comparison, so mirrors that still point at the same `github.com/owner/repo`
identity are accepted.

tmux plugins are installed under:

```text
~/.config/tmux/plugins/
```

The tmux config only loads TPM when it already exists; it does not clone
plugins during tmux startup.

## Destructive Helpers

`cleaner -s` removes user caches, shell history, editor state, trash entries,
and other local files. It prompts before running unless `--dry-run` or `--yes`
is used.

`update-beauty` updates and builds desktop components from repositories under
`~/.local/src`. It only shows `git clean -fdn` output by default; pass `--clean`
when you intentionally want it to remove untracked files before building.

`update` refreshes package managers and runs Neovim plugin updates with
`lazy.nvim` via:

```sh
nvim --headless "+Lazy! sync" +qa
```

## Notes

The installer is intentionally tailored for personal apt-based systems. On
other platforms, prefer using `stow` manually or adapt `dotfiles.sh` before
running it.
