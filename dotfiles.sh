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
    wget
    yt-dlp
    ripgrep
    alacritty
)
APT_BASE_PACKAGES=(
    git
    shellcheck
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
    verify           Run local syntax and dry-run checks only
    lock             Write current Git dependency commits to the lock file
EOF
}

set_mode() {
    case "$1" in
        full|install|backup|link|verify|lock)
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
            full|install|backup|link|verify|lock)
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
    local url="$1"
    url="${url%.git}"
    if [[ "$url" =~ github\.com[:/](.*)$ ]]; then
        url="github.com/${BASH_REMATCH[1]}"
    elif [[ "$url" =~ gitlab\.com[:/](.*)$ ]]; then
        url="gitlab.com/${BASH_REMATCH[1]}"
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

    backup_target="$BACKUP_ROOT${target#"$HOME"}"

    while [ -e "$backup_target" ] || [ -L "$backup_target" ]; do
        counter=$((counter + 1))
        backup_target="$BACKUP_ROOT${target#"$HOME"}.$counter"
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

install_apt_package_group() {
    local group="$1"
    local package
    local packages=()

    case "$group" in
        base)
            packages=("${APT_BASE_PACKAGES[@]}")
            ;;
        desktop)
            packages=("${APT_DESKTOP_PACKAGES[@]}")
            ;;
        server)
            packages=("${APT_SERVER_PACKAGES[@]}")
            ;;
        optional)
            packages=("${APT_OPTIONAL_PACKAGES[@]}")
            ;;
        *)
            die "Unknown apt package group: $group"
            ;;
    esac

    echo -e "${BLUE}Installing apt package group: $group${NC}"
    for package in "${packages[@]}"; do
        install_apt_package "$package"
    done
}

install_apt_package_groups() {
    local group

    for group in $DOTFILES_APT_GROUPS; do
        install_apt_package_group "$group"
    done
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

install_git_dependency() {
    local repo="$1"
    local dir="$2"
    local env_name="$3"
    local ref

    ref="$(git_dependency_ref "$repo" "$env_name")"
    install_git_repo "$repo" "$dir" "$ref"
}

# Install oh-my-zsh core
install_oh_my_zsh_core() {
    local repo="https://github.com/ohmyzsh/ohmyzsh.git"

    if [ ! -d "$ZSH" ]; then
        echo -e "${YELLOW}Cloning Oh-My-Zsh...${NC}"
        install_git_dependency "$repo" "$ZSH" OH_MY_ZSH_VERSION

        echo -e "${YELLOW}Installing Oh-My-Zsh ...${NC}"
        run_quiet env RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh "$ZSH/tools/install.sh" --unattended
    else
        install_git_dependency "$repo" "$ZSH" OH_MY_ZSH_VERSION
    fi
}

# Install oh-my-zsh
install_oh_my_zsh() {
    install_oh_my_zsh_core
    # zsh-autosuggestions
    install_git_dependency "https://github.com/zsh-users/zsh-autosuggestions.git" "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ZSH_AUTOSUGGESTIONS_VERSION
    # zsh-syntax-highlighting
    install_git_dependency "https://github.com/zsh-users/zsh-syntax-highlighting.git" "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ZSH_SYNTAX_HIGHLIGHTING_VERSION
    # extract
    install_git_dependency "https://github.com/xvoland/Extract.git" "$ZSH_CUSTOM/plugins/extract" ZSH_EXTRACT_VERSION
}

install_neovim_plugins() {
    echo -e "${BLUE}Installing Neovim plugin manager...${NC}"
    install_git_dependency "https://github.com/folke/lazy.nvim.git" "$NVIM_LAZY_DIR" LAZY_NVIM_VERSION

    echo -e "${BLUE}Syncing Neovim plugins...${NC}"
    run env DOTFILES_NVIM_SYNC=1 nvim --headless --clean -u "$DOTFILES_DIR/nvim/.config/nvim/init.lua" "+Lazy! sync" +qa
}

install_tmux_plugins() {
    echo -e "${BLUE}Installing tmux plugins...${NC}"
    install_git_dependency "https://github.com/tmux-plugins/tpm.git" "$TMUX_PLUGIN_DIR/tpm" TPM_VERSION
    install_git_dependency "https://github.com/tmux-plugins/tmux-copycat.git" "$TMUX_PLUGIN_DIR/tmux-copycat" TMUX_COPYCAT_VERSION
    install_git_dependency "https://github.com/nhdaly/tmux-better-mouse-mode.git" "$TMUX_PLUGIN_DIR/tmux-better-mouse-mode" TMUX_BETTER_MOUSE_MODE_VERSION
}

git_dependencies() {
    printf '%s\t%s\n' "https://github.com/so-fancy/diff-so-fancy.git" "$HOME/.local/share/diff-so-fancy"
    printf '%s\t%s\n' "https://github.com/ohmyzsh/ohmyzsh.git" "$ZSH"
    printf '%s\t%s\n' "https://github.com/zsh-users/zsh-autosuggestions.git" "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    printf '%s\t%s\n' "https://github.com/zsh-users/zsh-syntax-highlighting.git" "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
    printf '%s\t%s\n' "https://github.com/xvoland/Extract.git" "$ZSH_CUSTOM/plugins/extract"
    printf '%s\t%s\n' "https://github.com/folke/lazy.nvim.git" "$NVIM_LAZY_DIR"
    printf '%s\t%s\n' "https://github.com/tmux-plugins/tpm.git" "$TMUX_PLUGIN_DIR/tpm"
    printf '%s\t%s\n' "https://github.com/tmux-plugins/tmux-copycat.git" "$TMUX_PLUGIN_DIR/tmux-copycat"
    printf '%s\t%s\n' "https://github.com/nhdaly/tmux-better-mouse-mode.git" "$TMUX_PLUGIN_DIR/tmux-better-mouse-mode"
}

write_git_lock() {
    local repo
    local dir
    local commit
    local parent_dir

    parent_dir="$(dirname "$LOCK_FILE")"
    run_quiet mkdir -p "$parent_dir"

    if [ "$DRY_RUN" = true ]; then
        echo "+ write Git dependency lock to $LOCK_FILE"
        return 0
    fi

    {
        printf '# repo\tcommit\n'
        while IFS=$'\t' read -r repo dir; do
            if [ -d "$dir/.git" ]; then
                commit="$(git -C "$dir" rev-parse HEAD)"
                printf '%s\t%s\n' "$(normalize_git_url "$repo")" "$commit"
            else
                warn "Skipping unlocked dependency: $dir is not installed"
            fi
        done < <(git_dependencies)
    } > "$LOCK_FILE"

    echo -e "${GREEN}Wrote $LOCK_FILE${NC}"
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

    install_apt_package_groups

    # diff-so-fancy download + symlink
    install_git_dependency "https://github.com/so-fancy/diff-so-fancy.git" "$HOME/.local/share/diff-so-fancy" DIFF_SO_FANCY_VERSION
    if [ ! -d "$HOME/.local/bin" ]; then
        run_quiet mkdir -p "$HOME/.local/bin"
    fi
    run_quiet ln -sf "$HOME/.local/share/diff-so-fancy/diff-so-fancy" "$HOME/.local/bin/diff-so-fancy"

    # oh-my-zsh
    install_oh_my_zsh

    # neovim
    install_neovim_plugins

    # tmux
    install_tmux_plugins
}

# Link modules (customize as needed)
link_module(){
    echo -e "${BLUE}Linking modules...${NC}"

    local package

    for package in "${STOW_MODULES[@]}"; do
        stow_link "$package"
    done
}

verify_command() {
    local label="$1"
    shift

    echo -e "${BLUE}Verifying $label...${NC}"
    "$@"
}

verify_optional_command() {
    local command_name="$1"
    local label="$2"
    shift 2

    if command -v "$command_name" >/dev/null 2>&1; then
        verify_command "$label" "$@"
    else
        warn "Skipping $label: $command_name is not installed"
    fi
}

verify_repo() {
    local nvim_verify_home

    verify_command "Bash syntax" bash -n "${SCRIPT_CHECKS[@]}"
    verify_optional_command zsh "Zsh syntax" zsh -n zsh/.zshrc zsh/.config/zsh/setopt.zsh
    verify_optional_command stow "Stow dry-run" stow -n --no-folding -d "$DOTFILES_DIR" -R -t "$HOME" bash zsh common git tmux nvim
    if command -v nvim >/dev/null 2>&1; then
        nvim_verify_home="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-nvim-verify.XXXXXX")"
        if verify_command "Neovim headless startup" env \
            DOTFILES_VERIFY=1 \
            XDG_STATE_HOME="$nvim_verify_home/state" \
            XDG_CACHE_HOME="$nvim_verify_home/cache" \
            NVIM_LOG_FILE="$nvim_verify_home/nvim.log" \
            nvim --headless --clean -u "$DOTFILES_DIR/nvim/.config/nvim/init.lua" +qa; then
            rm -rf "$nvim_verify_home"
        else
            rm -rf "$nvim_verify_home"
            return 1
        fi
    else
        warn "Skipping Neovim headless startup: nvim is not installed"
    fi
    verify_optional_command shellcheck "ShellCheck" shellcheck "${SCRIPT_CHECKS[@]}"
    echo -e "${GREEN}Verification completed.${NC}"
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
        verify)
            verify_repo
            ;;
        lock)
            write_git_lock
            ;;
    esac

    echo -e "${GREEN}dotfiles $MODE completed!${NC}"
}

main "$@"
