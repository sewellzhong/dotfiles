#!/usr/bin/env bash
# Loaded by dotfiles.sh; checks run in a subshell to contain cleanup and state.
verify_repo() (
    local temp file repo dir env_name ref failed=0
    local scripts=() configs=()
    for file in bash zsh stow shellcheck nvim python3; do require_command "$file"; done
    temp=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-verify.XXXXXX")
    trap 'rm -rf -- "$temp"' EXIT
    for file in "${SCRIPT_CHECKS[@]}"; do scripts+=("$DOTFILES_DIR/$file"); done
    while IFS= read -r -d '' file; do scripts+=("$file"); done < <(find "$SCRIPT_DIR/lib" "$SCRIPT_DIR/tests" -name '*.sh' -print0)
    configs=("$DOTFILES_DIR/bash/.bashrc" "$DOTFILES_DIR/bash/.bash_profile"
        "$DOTFILES_DIR/common/.config/common/.aliases" "$DOTFILES_DIR/common/.config/common/.exports"
        "$DOTFILES_DIR/common/.config/common/.functions" "$DOTFILES_DIR/bin/.local/bin/base16-oxide")
    for file in "${scripts[@]}" "${configs[@]}"; do
        echo "Bash syntax: $file"
        bash -n "$file" || failed=1
    done
    while IFS= read -r -d '' file; do
        echo "Zsh syntax: $file"
        zsh -n "$file" || failed=1
    done < <(find "$DOTFILES_DIR/zsh" -type f \( -name '*.zsh' -o -name '.zshrc' -o -name '*.zsh-theme' \) -print0)
    for file in "$DOTFILES_DIR/common/.config/common/".{aliases,exports,functions}; do
        zsh -n "$file" || failed=1
    done
    shellcheck -P "$SCRIPT_DIR" -x "${scripts[@]}" || failed=1
    python3 - "$SCRIPT_DIR" <<'PY' || failed=1
import ast
from pathlib import Path
import sys
for directory in ('lib', 'tests'):
    for path in (Path(sys.argv[1]) / directory).glob('*.py'):
        ast.parse(path.read_text(), filename=str(path))
PY
    validate_git_lock || failed=1
    python3 "$SCRIPT_DIR/lib/check-lock.py" "$LOCK_FILE" "$DOTFILES_DIR/nvim/.config/nvim/lazy-lock.json" || failed=1
    mkdir -p "$temp/home"
    python3 "$SCRIPT_DIR/lib/transaction.py" check --repo "$DOTFILES_DIR" --home "$temp/home" -- "${STOW_MODULES[@]}" >/dev/null || failed=1
    HOME="$temp/home" stow -n --no-folding "--ignore=$(cat "$SCRIPT_DIR/lib/stow-private-pattern")" \
        -d "$DOTFILES_DIR" -S -t "$temp/home" "${STOW_MODULES[@]}" || failed=1
    # Report actual conflicts separately; repository validation doesn't move user files.
    echo 'Current HOME configuration preview:'
    transaction check || failed=1
    env NVIM_APPNAME=nvim DOTFILES_NVIM_CONFIG="$DOTFILES_DIR/nvim/.config/nvim" \
        DOTFILES_NVIM_CHECK="$SCRIPT_DIR/lib/nvim-check.lua" \
        XDG_CONFIG_HOME="$temp/config" XDG_DATA_HOME="$temp/data" \
        XDG_STATE_HOME="$temp/state" XDG_CACHE_HOME="$temp/cache" NVIM_LOG_FILE="$temp/nvim.log" \
        nvim --headless --clean -u NONE '+lua local ok, err = pcall(dofile, vim.env.DOTFILES_NVIM_CHECK); if not ok then vim.api.nvim_err_writeln(err); vim.cmd("cquit 1") end' || failed=1
    if "$STATIC_ONLY"; then
        echo 'Static checks only: installed dependencies and plugin startup NOT checked.'
    else
        while IFS=$'\t' read -r repo dir env_name; do
            ref=$(git_dependency_ref "$repo" "$env_name") || { failed=1; continue; }
            python3 "$SCRIPT_DIR/lib/dependencies.py" validate "$dir" "$repo" "$ref" >/dev/null || failed=1
        done < <(git_dependencies)
        if python3 "$SCRIPT_DIR/lib/nvim-installed.py" "$DOTFILES_DIR/nvim/.config/nvim/lazy-lock.json" "$(dirname "$NVIM_LAZY_DIR")" "$temp/data/nvim/lazy"; then
            cp "$DOTFILES_DIR/nvim/.config/nvim/lazy-lock.json" "$temp/lazy-lock.json"
            env NVIM_APPNAME=nvim DOTFILES_VERIFY=1 DOTFILES_NVIM_LOCK="$temp/lazy-lock.json" \
                DOTFILES_NVIM_CHECK="$SCRIPT_DIR/lib/nvim-check.lua" \
                XDG_CONFIG_HOME="$temp/config" XDG_DATA_HOME="$temp/data" \
                XDG_STATE_HOME="$temp/state" XDG_CACHE_HOME="$temp/cache" NVIM_LOG_FILE="$temp/nvim.log" \
                nvim --headless --clean -u "$DOTFILES_DIR/nvim/.config/nvim/init.lua" \
                '+lua local ok, err = pcall(dofile, vim.env.DOTFILES_NVIM_CHECK); if not ok then vim.api.nvim_err_writeln(err); vim.cmd("cquit 1") end' || failed=1
        else
            failed=1
        fi
    fi
    if [ "$failed" -ne 0 ]; then echo 'Verification FAILED.' >&2; return 1; fi
    echo 'Verification passed.'
)
