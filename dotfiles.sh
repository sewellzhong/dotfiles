#!/bin/bash
set -euo pipefail

# Set color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Set stow-managed directory
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
DOTFILES_DIR="${DOTFILES_DIR:-$SCRIPT_DIR}"
APT_UPDATED=false
DRY_RUN=false
ASSUME_YES=false
MODE="full"
BACKUP_ROOT=""
BACKUP_TARGETS=()
STOW_CONFLICTS=()
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
    wget
    yt-dlp
    ripgrep
    alacritty
)

# oh-my-zsh directories
ZSH="$HOME/.oh-my-zsh"
ZSH_CUSTOM="$ZSH/custom"

# Plugin directories
NVIM_LAZY_DIR="$HOME/.local/share/nvim/lazy/lazy.nvim"
TMUX_PLUGIN_DIR="$HOME/.config/tmux/plugins"

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
Usage: ${0##*/} [mode] [options]

Options:
    -h, --help       Print this message
    -n, --dry-run    Print actions without running them
    -y, --yes        Skip confirmation prompts
    -m, --mode MODE  Run one mode: full, install, backup, link

Modes:
    full             Install dependencies, back up conflicts, then link modules
    install          Install dependencies and plugins only
    backup           Back up conflicting target files only
    link             Back up conflicts, then link modules only
EOF
}

set_mode() {
    case "$1" in
        full|install|backup|link)
            MODE="$1"
            ;;
        *)
            echo -e "${RED}Unknown mode: $1${NC}"
            usage
            exit 1
            ;;
    esac
}

parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
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
            full|install|backup|link)
                set_mode "$1"
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                usage
                exit 1
                ;;
        esac
        shift
    done
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
    echo -e "${YELLOW}$*${NC}"
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
    local url="$1"
    url="${url%.git}"
    if [[ "$url" == *github.com* ]]; then
        url="$(sed 's#.*github.com[:/]#github.com/#' <<<"$url")"
    elif [[ "$url" == *gitlab.com* ]]; then
        url="$(sed 's#.*gitlab.com[:/]#gitlab.com/#' <<<"$url")"
    else
        url="${url#https://}"
        url="${url#http://}"
        url="${url#git@}"
        url="${url/:/\/}"
    fi
    printf '%s\n' "$url"
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
    case "$MODE" in
        full|install)
            preflight_install
            ;;
    esac
    case "$MODE" in
        full|link)
            preflight_link
            ;;
    esac
}

init_backup_root() {
    local stamp
    local backup_root
    local counter=0

    [ -n "$BACKUP_ROOT" ] && return 0

    stamp="$(date +%Y%m%d-%H%M%S)"
    backup_root="$HOME/.dotfiles_backup/$stamp"

    while [ -e "$backup_root" ] || [ -L "$backup_root" ]; do
        counter=$((counter + 1))
        backup_root="$HOME/.dotfiles_backup/$stamp-$counter"
    done

    BACKUP_ROOT="$backup_root"
}

backup_path_for() {
    local target="$1"
    local backup_target
    local counter=0

    backup_target="$BACKUP_ROOT${target#$HOME}"

    while [ -e "$backup_target" ] || [ -L "$backup_target" ]; do
        counter=$((counter + 1))
        backup_target="$BACKUP_ROOT${target#$HOME}.$counter"
    done

    printf '%s\n' "$backup_target"
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

# Check if a software package is installed
# Install an apt package
install_apt_package() {
    if ! is_installed_of_apt "$1"; then
        echo -e "${YELLOW}Installing missing package: $1${NC}"
        update_apt_once
        run_quiet sudo apt-get install -y "$1"
    else
        echo -e "${GREEN}$1 is already installed${NC}"
    fi
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
    elif [ ! -d "$dir/.git" ]; then
        backup_dir="${dir}.repair-backup.$(date +%Y%m%d-%H%M%S)"
        warn "$dir exists but is not a Git repository."
        confirm_action "Move it to $backup_dir and clone $repo?" || die "Cancelled."
        run_quiet mv "$dir" "$backup_dir"
        run_quiet git clone "$repo" "$dir"
    else
        remote_url="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
        if [ "$(normalize_git_url "$remote_url")" != "$(normalize_git_url "$repo")" ]; then
            backup_dir="${dir}.repair-backup.$(date +%Y%m%d-%H%M%S)"
            warn "$dir has unexpected origin: ${remote_url:-<none>}"
            confirm_action "Move it to $backup_dir and clone $repo?" || die "Cancelled."
            run_quiet mv "$dir" "$backup_dir"
            run_quiet git clone "$repo" "$dir"
        else
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

# Install oh-my-zsh core
install_oh_my_zsh_core() {
    local repo="https://github.com/ohmyzsh/ohmyzsh.git"

    if [ ! -d "$ZSH" ]; then
        echo -e "${YELLOW}Cloning Oh-My-Zsh...${NC}"
        install_git_repo "$repo" "$ZSH" "$OH_MY_ZSH_VERSION"

        echo -e "${YELLOW}Installing Oh-My-Zsh ...${NC}"
        run_quiet env RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh "$ZSH/tools/install.sh" --unattended
    else
        install_git_repo "$repo" "$ZSH" "$OH_MY_ZSH_VERSION"
    fi
}

# Install oh-my-zsh
install_oh_my_zsh() {
    # zsh
    install_apt_package "zsh"

    install_oh_my_zsh_core

    # autojump
    install_apt_package "autojump"
    # zsh-autosuggestions
    install_git_repo "https://github.com/zsh-users/zsh-autosuggestions.git" "$ZSH_CUSTOM/plugins/zsh-autosuggestions" "$ZSH_AUTOSUGGESTIONS_VERSION"
    # zsh-syntax-highlighting
    install_git_repo "https://github.com/zsh-users/zsh-syntax-highlighting.git" "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" "$ZSH_SYNTAX_HIGHLIGHTING_VERSION"
    # extract
    install_git_repo "https://github.com/xvoland/Extract.git" "$ZSH_CUSTOM/plugins/extract" "$ZSH_EXTRACT_VERSION"
}

install_neovim_plugins() {
    echo -e "${BLUE}Installing Neovim plugin manager...${NC}"
    install_git_repo "https://github.com/folke/lazy.nvim.git" "$NVIM_LAZY_DIR" "$LAZY_NVIM_VERSION"

    echo -e "${BLUE}Syncing Neovim plugins...${NC}"
    run env DOTFILES_NVIM_SYNC=1 nvim --headless --clean -u "$DOTFILES_DIR/nvim/.config/nvim/init.lua" "+Lazy! sync" +qa
}

install_tmux_plugins() {
    echo -e "${BLUE}Installing tmux plugins...${NC}"
    install_git_repo "https://github.com/tmux-plugins/tpm.git" "$TMUX_PLUGIN_DIR/tpm" "$TPM_VERSION"
    install_git_repo "https://github.com/tmux-plugins/tmux-copycat.git" "$TMUX_PLUGIN_DIR/tmux-copycat" "$TMUX_COPYCAT_VERSION"
    install_git_repo "https://github.com/nhdaly/tmux-better-mouse-mode.git" "$TMUX_PLUGIN_DIR/tmux-better-mouse-mode" "$TMUX_BETTER_MOUSE_MODE_VERSION"
}

# Backup existing config files
backup_config() {
    local source="$1"
    local target="$2"

    if [ -L "$target" ] && [ "$(readlink -f "$target")" = "$(readlink -f "$source")" ]; then
        return
    elif [ -f "$target" ] || [ -L "$target" ]; then
        local backup_target
        local backup_dir

        init_backup_root
        backup_target="$(backup_path_for "$target")"
        backup_dir="$(dirname "$backup_target")"

        if [ ! -d "$backup_dir" ]; then
            run_quiet mkdir -p "$backup_dir"
        fi

        echo -e "${YELLOW}Backing up $target to $backup_target${NC}"
        run_quiet mv "$target" "$backup_target"
    fi
}

collect_backup_targets() {
    local package="$1"
    local package_dir="$DOTFILES_DIR/$package"
    local file
    local target

    if [ ! -d "$package_dir" ]; then
        return
    fi

    while IFS= read -r file; do
        target="${file/#$package_dir/$HOME}"
        if [ -L "$target" ] && [ "$(readlink -f "$target")" = "$(readlink -f "$file")" ]; then
            continue
        elif [ -f "$target" ] || [ -L "$target" ]; then
            BACKUP_TARGETS+=("$target")
        fi
    done < <(find "$package_dir" -type f)
}

collect_stow_conflicts() {
    local package="$1"
    local package_dir="$DOTFILES_DIR/$package"
    local file
    local dir
    local target

    if [ ! -d "$package_dir" ]; then
        return
    fi

    while IFS= read -r file; do
        target="${file/#$package_dir/$HOME}"
        if [ -d "$target" ] && [ ! -L "$target" ]; then
            STOW_CONFLICTS+=("$target exists as a directory, but $package provides a file")
        fi
    done < <(find "$package_dir" -type f)

    while IFS= read -r dir; do
        [ "$dir" = "$package_dir" ] && continue
        target="${dir/#$package_dir/$HOME}"
        if { [ -f "$target" ] || [ -L "$target" ]; } && [ ! -d "$target" ]; then
            STOW_CONFLICTS+=("$target exists as a file or symlink, but $package provides a directory")
        fi
    done < <(find "$package_dir" -type d)
}

collect_all_backup_targets() {
    local package

    BACKUP_TARGETS=()
    STOW_CONFLICTS=()
    for package in "${STOW_MODULES[@]}"; do
        collect_backup_targets "$package"
        collect_stow_conflicts "$package"
    done
}

confirm_stow_conflicts() {
    local conflict

    [ "${#STOW_CONFLICTS[@]}" -eq 0 ] && return 0

    echo -e "${RED}Stow cannot safely resolve these path-shape conflicts:${NC}"
    for conflict in "${STOW_CONFLICTS[@]}"; do
        echo "  - $conflict"
    done
    die "Resolve these manually, then rerun the installer."
}

confirm_backup_targets() {
    local target
    local response

    [ "${#BACKUP_TARGETS[@]}" -eq 0 ] && return 0
    init_backup_root

    echo -e "${YELLOW}The following files will be moved to $BACKUP_ROOT:${NC}"
    for target in "${BACKUP_TARGETS[@]}"; do
        echo "  $target -> $(backup_path_for "$target")"
    done

    if [ "$DRY_RUN" = true ] || [ "$ASSUME_YES" = true ]; then
        return 0
    fi

    read -r -p "Continue? [y/N] " response
    case "$response" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            echo "Cancelled."
            exit 1
            ;;
    esac
}

backup_module() {
    local package="$1"
    local package_dir="$DOTFILES_DIR/$package"

    if [ -d "$package_dir" ]; then
        find "$package_dir" -type f | while IFS= read -r file; do
            local target="${file/#$package_dir/$HOME}"
            backup_config "$file" "$target"
        done
    else
        echo -e "${RED}Stow package $package does not exist, skipping backup${NC}"
    fi
}

backup_all_configs() {
    local package

    if [ "${#BACKUP_TARGETS[@]}" -eq 0 ]; then
        echo -e "${GREEN}No conflicting config files found${NC}"
        return 0
    fi

    echo -e "${BLUE}Backing up conflicting config files...${NC}"
    for package in "${STOW_MODULES[@]}"; do
        backup_module "$package"
    done
}

# Link files using stow
stow_link() {
    local package="$1"
    echo -e "${BLUE}Stowing package $package...${NC}"

    local package_dir="$DOTFILES_DIR/$package"

    if [ -d "$package_dir" ]; then
        run_quiet stow --no-folding -d "$DOTFILES_DIR" -R -t "$HOME" "$package"
    else
        echo -e "${RED}Stow package $package does not exist, skipping${NC}"
    fi
}

# Install dependencies or plugins (customize as needed)
install_dependencies_or_plugins() {
    echo -e "${BLUE}Installing packages...${NC}"

    # font support
    install_apt_package "fonts-jetbrains-mono"
    install_apt_package "fonts-noto-cjk"
    install_apt_package "fonts-noto-color-emoji"

    # git
    install_apt_package "git"
    # diff-so-fancy download + symlink
    install_git_repo "https://github.com/so-fancy/diff-so-fancy.git" "$HOME/.local/share/diff-so-fancy" "$DIFF_SO_FANCY_VERSION"
    if [ ! -d "$HOME/.local/bin" ]; then
        run_quiet mkdir -p "$HOME/.local/bin"
    fi
    run_quiet ln -sf "$HOME/.local/share/diff-so-fancy/diff-so-fancy" "$HOME/.local/bin/diff-so-fancy"

    # stow
    install_apt_package "stow"

    # oh-my-zsh
    install_oh_my_zsh

    # net-tools
    install_apt_package "net-tools"
    # traceroute
    install_apt_package "traceroute"

    # neovim
    install_apt_package "neovim"
    install_neovim_plugins
    # vim
#    install_apt_package "vim"
    # glow
    install_apt_package "glow"
    # bat
    install_apt_package "bat"

    # ssh
    install_apt_package "openssh-server"
    install_apt_package "openssh-client"

    # wget
    install_apt_package "wget"
    # curl
    install_apt_package "curl"

    # tmux
    install_apt_package "tmux"
    install_tmux_plugins
    # fzf
    install_apt_package "fzf"
    # ripgrep
    install_apt_package "ripgrep"
    # nnn
    install_apt_package "nnn"
    # lrzsz
    install_apt_package "lrzsz"
    # htop
    install_apt_package "htop"
    # xclip
    install_apt_package "xclip"
    # yt-dlp
    install_apt_package "yt-dlp"

    # alacritty
    install_apt_package "alacritty"
}

# Link modules (customize as needed)
link_module(){
    echo -e "${BLUE}Linking modules...${NC}"

    local package

    for package in "${STOW_MODULES[@]}"; do
        stow_link "$package"
    done
}

# Main entry point
main() {
    parse_args "$@"
    preflight

    echo -e "${GREEN}dotfiles $MODE started...${NC}"

    case "$MODE" in
        full)
            collect_all_backup_targets
            confirm_stow_conflicts
            confirm_backup_targets
            install_dependencies_or_plugins
            backup_all_configs
            link_module
            ;;
        install)
            install_dependencies_or_plugins
            ;;
        backup)
            collect_all_backup_targets
            confirm_stow_conflicts
            confirm_backup_targets
            backup_all_configs
            ;;
        link)
            collect_all_backup_targets
            confirm_stow_conflicts
            confirm_backup_targets
            backup_all_configs
            link_module
            ;;
    esac

    echo -e "${GREEN}dotfiles $MODE completed!${NC}"
}

main "$@"
