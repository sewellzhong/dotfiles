#!/bin/bash
set -euo pipefail

# Set color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Set stow-managed directory
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES_DIR="$(cd -- "${DOTFILES_DIR:-$SCRIPT_DIR}" && pwd -P)"
APT_UPDATED=false
DRY_RUN=false
ASSUME_YES=false
MODE="full"
STATIC_ONLY=false
RESTORE_BATCH=""
SELECTED_MODULE=""
LOCK_FILE="${DOTFILES_LOCK_FILE:-$DOTFILES_DIR/dotfiles.lock}"
DOTFILES_USE_LOCK="${DOTFILES_USE_LOCK:-true}"
DOTFILES_APT_GROUPS="${DOTFILES_APT_GROUPS:-base}"
STOW_MODULES=(
    bin
    dircolors
    bash
    zsh
    common
    ssh
    git
    tmux
    bat
    glow
    htop
    nvim
    vim
    wget
    yt-dlp
    ripgrep
    alacritty
)
TARGET_STOW_MODULES=("${STOW_MODULES[@]}")
APT_BASE_PACKAGES=(
    git
    shellcheck
    python3
    jq
    bc
    nodejs
    npm
    unzip
    stow
    zsh
    neovim
    bat
    openssh-client
    wget
    curl
    tmux
    fzf
    ripgrep
    nnn
    lrzsz
    htop
    xclip
)
APT_DESKTOP_PACKAGES=(
    fonts-jetbrains-mono
    fonts-noto-cjk
    fonts-noto-color-emoji
    alacritty
)
APT_SERVER_PACKAGES=(
    openssh-server
)
APT_OPTIONAL_PACKAGES=(
    autojump
    glow
    net-tools
    traceroute
    yt-dlp
)
SCRIPT_CHECKS=(
    dotfiles.sh
    bin/.local/bin/update
    bin/.local/bin/update-beauty
    bin/.local/bin/cleaner
    bin/.local/bin/rofi-calendar
    bin/.local/bin/sizeof
)

# Plugin directories
NVIM_LAZY_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy/lazy.nvim"

# Optional version pins. By default plugin repos follow their current branch.
OH_MY_ZSH_VERSION="${OH_MY_ZSH_VERSION:-}"
DIFF_SO_FANCY_VERSION="${DIFF_SO_FANCY_VERSION:-}"
LAZY_NVIM_VERSION="${LAZY_NVIM_VERSION:-}"
ZSH_AUTOSUGGESTIONS_VERSION="${ZSH_AUTOSUGGESTIONS_VERSION:-}"
ZSH_SYNTAX_HIGHLIGHTING_VERSION="${ZSH_SYNTAX_HIGHLIGHTING_VERSION:-}"
ZSH_EXTRACT_VERSION="${ZSH_EXTRACT_VERSION:-}"
TPM_VERSION="${TPM_VERSION:-}"
TMUX_COPYCAT_VERSION="${TMUX_COPYCAT_VERSION:-}"
TMUX_BETTER_MOUSE_MODE_VERSION="${TMUX_BETTER_MOUSE_MODE_VERSION:-}"

usage() {
    cat <<EOF
Usage: ${0##*/} [mode] [module] [options]

Options:
    -h, --help           Print this message
    -n, --dry-run        Print actions without running them
    -y, --yes            Skip confirmation prompts
    -m, --mode MODE      Run one mode: full, install, backup, link, restore, verify, lock
    --static            Only repository checks (verify mode)
    -M, --module MODULE  Limit backup or link to one configured module

Modes:
    full             Install dependencies, back up conflicts, then link modules
    install          Install dependencies and plugins only
    backup           Back up conflicting target files only
    link             Back up conflicts, then link modules only
    restore BATCH    Restore a configuration backup batch
    verify           Check repository and installed dependencies
    lock             Write current Git dependency commits to the lock file

Examples:
    ${0##*/} link git
    ${0##*/} backup --module zsh
EOF
}

set_mode() {
    case "$1" in
        full|install|backup|link|restore|verify|lock)
            MODE="$1"
            ;;
        *)
            echo -e "${RED}Unknown mode: $1${NC}"
            usage
            exit 1
            ;;
    esac
}

set_module() {
    if [ -z "$1" ]; then
        die "Missing module name."
    fi
    if [ -n "$SELECTED_MODULE" ]; then
        die "Only one module can be selected per run."
    fi
    SELECTED_MODULE="$1"
}

configure_target_modules() {
    local package

    if [ -z "$SELECTED_MODULE" ]; then
        TARGET_STOW_MODULES=("${STOW_MODULES[@]}")
        return 0
    fi

    case "$MODE" in
        backup|link)
            ;;
        *)
            die "A single module can only be selected in backup or link mode."
            ;;
    esac

    for package in "${STOW_MODULES[@]}"; do
        if [ "$package" = "$SELECTED_MODULE" ]; then
            TARGET_STOW_MODULES=("$package")
            return 0
        fi
    done

    die "Unknown stow module: $SELECTED_MODULE"
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            --static)
                STATIC_ONLY=true
                ;;
            -n|--dry-run)
                DRY_RUN=true
                ;;
            -y|--yes)
                ASSUME_YES=true
                ;;
            -m|--mode)
                if [ "$#" -lt 2 ]; then
                    echo -e "${RED}Missing value for $1${NC}"
                    usage
                    exit 1
                fi
                set_mode "$2"
                shift
                ;;
            --mode=*)
                set_mode "${1#*=}"
                ;;
            -M|--module)
                if [ "$#" -lt 2 ]; then
                    echo -e "${RED}Missing value for $1${NC}"
                    usage
                    exit 1
                fi
                set_module "$2"
                shift
                ;;
            --module=*)
                set_module "${1#*=}"
                ;;
            full|install|backup|link|restore|verify|lock)
                set_mode "$1"
                ;;
            *)
                if [ "$MODE" = restore ] && [ -z "$RESTORE_BATCH" ] && [[ "$1" != -* ]]; then
                    RESTORE_BATCH="$1"
                elif { [ "$MODE" = "backup" ] || [ "$MODE" = "link" ]; } &&
                    [ -z "$SELECTED_MODULE" ] && [[ "$1" != -* ]]; then
                    set_module "$1"
                else
                    echo -e "${RED}Unknown option: $1${NC}"
                    usage
                    exit 1
                fi
                ;;
        esac
        shift
    done

    if "$STATIC_ONLY" && [ "$MODE" != verify ]; then die "--static requires verify"; fi
    if [ "$MODE" = restore ] && [ -z "$RESTORE_BATCH" ]; then die "restore requires a batch name"; fi
    configure_target_modules
}

run() {
    if [ "$DRY_RUN" = true ]; then
        printf '+'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

run_quiet() {
    if [ "$DRY_RUN" = true ]; then
        printf '+'
        printf ' %q' "$@"
        printf ' > /dev/null\n'
    else
        "$@" > /dev/null
    fi
}

warn() {
    echo -e "${YELLOW}$*${NC}" >&2
}

die() {
    echo -e "${RED}$*${NC}" >&2
    exit 1
}

confirm_action() {
    local message="$1"
    local response

    if [ "$DRY_RUN" = true ] || [ "$ASSUME_YES" = true ]; then
        return 0
    fi

    read -r -p "$message [y/N] " response
    case "$response" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

require_command() {
    local command_name="$1"
    command -v "$command_name" >/dev/null 2>&1 || die "Missing required command: $command_name"
}

normalize_git_url() {
    python3 "$SCRIPT_DIR/lib/dependencies.py" normalize "$1"
}

preflight_common() {
    [ -d "$DOTFILES_DIR" ] || die "DOTFILES_DIR does not exist: $DOTFILES_DIR"
    [ -d "$HOME" ] || die "HOME does not exist: $HOME"
}

preflight_install() {
    require_command sudo
    require_command git
    require_command apt-get
    require_command dpkg-query
    require_command apt-cache
    require_command flock
}

preflight_link() {
    if ! command -v stow >/dev/null 2>&1; then
        if [ "$MODE" = "full" ] || [ "$MODE" = "install" ]; then
            return 0
        fi
        die "Missing required command: stow. Run ./dotfiles.sh install first."
    fi
}

preflight() {
    preflight_common
    require_command python3
    case "$MODE" in
        full|install)
            preflight_install
            ;;
        verify|lock)
            require_command git
            ;;
    esac
    case "$MODE" in
        full|link)
            preflight_link
            ;;
    esac
}

# Check if a software package is installed
is_installed_of_apt() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

# Update apt package index once per run
update_apt_once() {
    if [ "$APT_UPDATED" = false ]; then
        echo -e "${YELLOW}Updating apt package index...${NC}"
        run_quiet sudo apt-get update
        APT_UPDATED=true
    fi
}

install_apt_package_groups() {
    local group package nvim_package
    local packages=() missing=() version_args=()
    local -A seen=()
    # Resolve every group before issuing any command which changes the system.
    for group in $DOTFILES_APT_GROUPS; do
        case "$group" in
            base) packages+=("${APT_BASE_PACKAGES[@]}") ;;
            desktop) packages+=("${APT_DESKTOP_PACKAGES[@]}") ;;
            server) packages+=("${APT_SERVER_PACKAGES[@]}") ;;
            optional) packages+=("${APT_OPTIONAL_PACKAGES[@]}") ;;
            *) die "Unknown apt package group: $group" ;;
        esac
    done
    "$DRY_RUN" && version_args+=(--dry-run)
    nvim_package=$(python3 "$SCRIPT_DIR/lib/apt-preflight.py" "${version_args[@]}") || return 1
    for package in "${packages[@]}" $nvim_package; do
        [ -z "${seen[$package]:-}" ] || continue
        seen[$package]=1
        if [ "$package" = "$nvim_package" ] || ! is_installed_of_apt "$package"; then
            missing+=("$package")
        fi
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        update_apt_once
        run sudo apt-get install -y "${missing[@]}"
    fi
    if ! "$DRY_RUN"; then python3 "$SCRIPT_DIR/lib/apt-preflight.py" --installed; fi
}

git_dependency_ref() {
    local repo="$1"
    local env_name="$2"
    local explicit_ref="${!env_name:-}"
    local locked_ref=""

    if [ -n "$explicit_ref" ]; then
        printf '%s\n' "$explicit_ref"
        return 0
    fi

    if [ "$DOTFILES_USE_LOCK" = true ] && [ -r "$LOCK_FILE" ]; then
        locked_ref="$(awk -F '\t' -v repo="$(normalize_git_url "$repo")" '
            $1 == repo { print $2; exit }
        ' "$LOCK_FILE")"
    fi

    if [ "$DOTFILES_USE_LOCK" = true ] && [[ ! "$locked_ref" =~ ^[0-9a-f]{40}$ ]]; then
        die "Missing or invalid lock for $repo in $LOCK_FILE"
    fi
    printf '%s\n' "$locked_ref"
}

# Clone, update, or repair a Git-managed dependency.
install_git_repo() {
    local repo="$1"
    local dir="$2"
    local ref="${3:-}"
    local parent_dir
    local remote_url=""
    local backup_dir
    local current_branch

    parent_dir="$(dirname "$dir")"

    if [ ! -e "$dir" ]; then
        echo -e "${YELLOW}Cloning Git repo: $repo${NC}"
        if [ ! -d "$parent_dir" ]; then
            run_quiet mkdir -p "$parent_dir"
        fi
        run_quiet git clone "$repo" "$dir"
    elif [ ! -e "$dir/.git" ]; then
        backup_dir="${dir}.repair-backup.$(date +%Y%m%d-%H%M%S)"
        warn "$dir exists but is not a Git repository."
        confirm_action "Move it to $backup_dir and clone $repo?" || die "Cancelled."
        run_quiet mv "$dir" "$backup_dir"
        run_quiet git clone "$repo" "$dir"
    else
        remote_url="$(git -C "$dir" config --get remote.origin.url 2>/dev/null || true)"
        if [ "$(normalize_git_url "$remote_url")" != "$(normalize_git_url "$repo")" ]; then
            backup_dir="${dir}.repair-backup.$(date +%Y%m%d-%H%M%S)"
            warn "$dir has unexpected origin: ${remote_url:-<none>}"
            confirm_action "Move it to $backup_dir and clone $repo?" || die "Cancelled."
            run_quiet mv "$dir" "$backup_dir"
            run_quiet git clone "$repo" "$dir"
        else
            python3 "$SCRIPT_DIR/lib/dependencies.py" validate "$dir" "$repo" >/dev/null || return 1
            echo -e "${GREEN}$dir already exists, updating${NC}"
            run_quiet git -C "$dir" fetch --tags --prune origin
            if [ -n "$ref" ]; then
                run_quiet git -C "$dir" checkout "$ref"
            else
                current_branch="$(git -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
                if [ -n "$current_branch" ]; then
                    run_quiet git -C "$dir" pull --ff-only
                else
                    warn "$dir is detached; set a *_VERSION environment variable to pin it explicitly."
                fi
            fi
            return 0
        fi
    fi

    if [ -n "$ref" ]; then
        run_quiet git -C "$dir" checkout "$ref"
    fi
}

install_git_dependency() {
    local repo="$1"
    local dir="$2"
    local env_name="$3"
    local ref

    ref="$(git_dependency_ref "$repo" "$env_name")"
    install_git_repo "$repo" "$dir" "$ref"
}

# The plugin manager is installed by the shared dependency registry.
install_neovim_plugins() (
    local tool temp
    if "$DRY_RUN"; then
        echo '+ restore Neovim plugins from the tracked lazy-lock.json'
        return 0
    fi
    for tool in nvim node npm unzip tar; do require_command "$tool"; done
    python3 "$SCRIPT_DIR/lib/nvim-preflight.py" "$DOTFILES_DIR/nvim/.config/nvim"
    temp=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-nvim-install.XXXXXX")
    trap 'rm -rf -- "$temp"' EXIT
    cp "$DOTFILES_DIR/nvim/.config/nvim/lazy-lock.json" "$temp/lazy-lock.json"
    env NVIM_APPNAME=nvim DOTFILES_NVIM_SYNC=1 DOTFILES_NVIM_LOCK="$temp/lazy-lock.json" \
        nvim --headless --clean -u "$DOTFILES_DIR/nvim/.config/nvim/init.lua" \
        '+lua local ok, err = pcall(function() require("dotfiles.install").run() end); if not ok then vim.api.nvim_err_writeln(err); vim.cmd("cquit 1") end'
)

git_dependencies() {
    python3 "$SCRIPT_DIR/lib/dependencies.py" registry
}

validate_git_lock() {
    local repo dir env_name
    if [ "$DOTFILES_USE_LOCK" = true ]; then
        require_command python3
        python3 "$SCRIPT_DIR/lib/check-lock.py" "$LOCK_FILE" "$DOTFILES_DIR/nvim/.config/nvim/lazy-lock.json" || return 1
    fi
    while IFS=$'\t' read -r repo dir env_name; do
        git_dependency_ref "$repo" "$env_name" >/dev/null || return 1
    done < <(git_dependencies)
}

write_git_lock() {
    local args=(lock --repo "$DOTFILES_DIR" --lock "$LOCK_FILE")
    "$DRY_RUN" && args+=(--dry-run)
    python3 "$SCRIPT_DIR/lib/update-dependencies.py" "${args[@]}"
}

transaction() {
    local action="$1"
    local args=("$action" --repo "$DOTFILES_DIR" --home "$HOME")
    "$DRY_RUN" && args+=(--dry-run)
    "$ASSUME_YES" && args+=(--yes)
    if [ "$action" = restore ]; then args+=(--batch "$RESTORE_BATCH"); fi
    python3 "$SCRIPT_DIR/lib/transaction.py" "${args[@]}" "${TARGET_STOW_MODULES[@]}"
}

# Install dependencies or plugins (customize as needed)
install_dependencies_or_plugins() (
    local repo dir env_name dependency_lock_fd
    if ! "$DRY_RUN"; then
        [ ! -L "$DOTFILES_DIR/.dotfiles-dependencies.lock" ] || die "Dependency operation lock cannot be a symlink"
        exec {dependency_lock_fd}>"$DOTFILES_DIR/.dotfiles-dependencies.lock"
        flock -x "$dependency_lock_fd"
    fi
    validate_git_lock
    install_apt_package_groups
    while IFS=$'\t' read -r repo dir env_name; do
        install_git_dependency "$repo" "$dir" "$env_name"
    done < <(git_dependencies)
    local fancy="$HOME/.local/bin/diff-so-fancy"
    if [ -e "$fancy" ] || [ -L "$fancy" ]; then
        if [ ! -L "$fancy" ] || [ "$(readlink -f "$fancy")" != "$HOME/.local/share/diff-so-fancy/diff-so-fancy" ]; then
            die "Resolve conflicting executable manually: $fancy"
        fi
    else
        run mkdir -p "$HOME/.local/bin"
        run ln -s "$HOME/.local/share/diff-so-fancy/diff-so-fancy" "$fancy"
    fi
    install_neovim_plugins
)

# shellcheck source=lib/verify.sh
source "$SCRIPT_DIR/lib/verify.sh"

# Main entry point
main() {
    parse_args "$@"
    preflight

    if [ -n "$SELECTED_MODULE" ]; then
        echo -e "${GREEN}dotfiles $MODE started for module $SELECTED_MODULE...${NC}"
    else
        echo -e "${GREEN}dotfiles $MODE started...${NC}"
    fi

    case "$MODE" in
        full)
            transaction check
            install_dependencies_or_plugins
            transaction link
            ;;
        install) install_dependencies_or_plugins ;;
        backup|link|restore) transaction "$MODE" ;;
        verify) verify_repo ;;
        lock) write_git_lock ;;
    esac

    if [ -n "$SELECTED_MODULE" ]; then
        echo -e "${GREEN}dotfiles $MODE completed for module $SELECTED_MODULE!${NC}"
    else
        echo -e "${GREEN}dotfiles $MODE completed!${NC}"
    fi
}

if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then main "$@"; fi
