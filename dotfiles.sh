#!/bin/bash
set -e

# Set color variables
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Set stow-managed directory
DOTFILES_DIR="$HOME/.dotfiles"
APT_UPDATED=false
DRY_RUN=false
ASSUME_YES=false
MODE="full"
BACKUP_ROOT=""
BACKUP_TARGETS=()
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
is_installed_of_path() {

    # Check git-installed packages (stored in a specific directory)
    if [ -d "$1" ]; then
        return 0  # Directory exists and is a git repo → installed
    fi

    return 1  # Neither installed via apt nor git
}

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

# Clone and install via git
install_git_repo() {
    local repo="$1"
    local dir="$2"
    local parent_dir

    parent_dir="$(dirname "$dir")"

    if ! is_installed_of_path "$dir"; then
        echo -e "${YELLOW}Cloning Git repo: $repo${NC}"
        if [ ! -d "$parent_dir" ]; then
            run_quiet mkdir -p "$parent_dir"
        fi
        run_quiet git clone "$repo" "$dir"
    else
        echo -e "${GREEN}$dir already exists, skipping clone${NC}"
    fi
}

# Install oh-my-zsh core
install_oh_my_zsh_core() {
    local repo="https://github.com/ohmyzsh/ohmyzsh.git"
    local version="${OH_MY_ZSH_VERSION:-master}"

    if [ ! -d "$ZSH" ]; then
        echo -e "${YELLOW}Cloning Oh-My-Zsh: $version ...${NC}"
        if [ "$version" = "master" ]; then
            run_quiet git clone --depth 1 --branch "$version" "$repo" "$ZSH"
        else
            run_quiet git clone "$repo" "$ZSH"
            run_quiet git -C "$ZSH" checkout "$version"
        fi

        echo -e "${YELLOW}Installing Oh-My-Zsh ...${NC}"
        run_quiet env RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh "$ZSH/tools/install.sh" --unattended
    else
        echo -e "${GREEN}Oh-My-Zsh is already installed${NC}"
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
    install_git_repo "https://github.com/zsh-users/zsh-autosuggestions.git" "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    # zsh-syntax-highlighting
    install_git_repo "https://github.com/zsh-users/zsh-syntax-highlighting.git" "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
    # extract
    install_git_repo "https://github.com/xvoland/Extract.git" "$ZSH_CUSTOM/plugins/extract"
}

install_neovim_plugins() {
    echo -e "${BLUE}Installing Neovim plugin manager...${NC}"
    install_git_repo "https://github.com/folke/lazy.nvim.git" "$NVIM_LAZY_DIR"
    run_quiet git -C "$NVIM_LAZY_DIR" checkout stable

    echo -e "${BLUE}Syncing Neovim plugins...${NC}"
    run env DOTFILES_NVIM_SYNC=1 nvim --headless --clean -u "$DOTFILES_DIR/nvim/.config/nvim/init.lua" "+Lazy! sync" +qa
}

install_tmux_plugins() {
    echo -e "${BLUE}Installing tmux plugins...${NC}"
    install_git_repo "https://github.com/tmux-plugins/tpm.git" "$TMUX_PLUGIN_DIR/tpm"
    install_git_repo "https://github.com/tmux-plugins/tmux-copycat.git" "$TMUX_PLUGIN_DIR/tmux-copycat"
    install_git_repo "https://github.com/nhdaly/tmux-better-mouse-mode.git" "$TMUX_PLUGIN_DIR/tmux-better-mouse-mode"
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

collect_all_backup_targets() {
    local package

    BACKUP_TARGETS=()
    for package in "${STOW_MODULES[@]}"; do
        collect_backup_targets "$package"
    done
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
    install_git_repo "https://github.com/so-fancy/diff-so-fancy.git" "$HOME/.local/share/diff-so-fancy"
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

    echo -e "${GREEN}dotfiles $MODE started...${NC}"

    case "$MODE" in
        full)
            collect_all_backup_targets
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
            confirm_backup_targets
            backup_all_configs
            ;;
        link)
            collect_all_backup_targets
            confirm_backup_targets
            backup_all_configs
            link_module
            ;;
    esac

    echo -e "${GREEN}dotfiles $MODE completed!${NC}"
}

main "$@"
