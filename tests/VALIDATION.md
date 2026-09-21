# Validation record

Validated on 2026-09-21, Debian 13, Neovim 0.10.4, using temporary HOME/XDG directories.
The user's existing untracked `.nvimlog` was left untouched.

## Automated checks

- `bash tests/run.sh`: 50 offline scenarios passed. The tests use real Stow for
  filesystem scenarios and command substitutes for package installation/builds.
- `./dotfiles.sh verify --static`: passed, including individual Bash/Zsh parsing,
  ShellCheck, Python parsing, all 17 Stow modules, Lua syntax and lock coverage.
- `git diff --check`: passed.
- `DOTFILES_LAZY_SEED=/tmp/dotfiles-lazy-seed-round2-verified bash tests/integration.sh`:
  13 real editor integration scenarios passed. The seed was fetched at the tracked
  manager SHA and passed `git fsck --full`. Tests permit only Git file transport.
- A delivery copy includes tracked and new source files, excluding local metadata,
  caches and the pre-existing `.nvimlog`; static checks and both suites passed from
  `/tmp/dotfiles-delivery-round2-cg65hice` (50 offline + 13 editor cases).
- Real isolated worktrees of all 19 pinned Neovim plugins loaded successfully with
  the strict checker. Telescope, file tree, LSP setup, formatting and lint module
  initialization passed; the Java extension also loaded on Neovim 0.10.4. Source
  worktrees retained identical Git status before/after; validation uses independent
  shallow transport clones, not symlinks, hardlinks or shared Git object stores.
- Startup assertions confirm Telescope, LSP, formatting and lint plugins are not
  loaded before their configured commands/events.

Regression coverage includes first install/reinstall, paths with spaces, execution
outside the repository, broken symlinks, cross-module and directory conflicts,
partial backup/link failures, interrupted operations, HOME-level serialization,
manual restore, later edits, missing/duplicate locks, failed final lock replacement,
missing build tools, build/checkout failure propagation, cache boundaries, search
scope, SSH override precedence and missing editor dependencies.

The second-round tests cover preserved restore snapshots, missing/eager plugins,
reinstall, upgrades/downgrades, dirty/origin checks, equivalent SSH origins without
recloning, detached Zsh updates, unmanaged directories, partial checkout failures,
configuration/build/fetch/clone failures, error output without exceptions, silent
command failures, failed atomic
publication, concurrent lock edits and serialized operations. Apt tests cover
batched/deduplicated packages, invalid groups, candidates, PATH shadowing and dry runs.
Stow tests cover default/global/package ignore precedence and multiline patterns,
plus `.local/bin` inclusion. Tests exposed and fixed lazy's headless process error
reporting, deferred error notifications and completion filters affecting helptags.

## CI configuration

`.github/workflows/validate.yml` targets Ubuntu 24.04 / Neovim 0.10.4, uses a
SHA-pinned checkout action with `contents: read` and no persisted credentials,
verifies the editor archive checksum, prepares the pinned manager, and runs static,
offline and real editor suites. The archive name and SHA256 come from the official
[Neovim v0.10.4 release](https://github.com/neovim/neovim/releases/tag/v0.10.4).
The workflow was added and inspected locally; no hosted GitHub Actions run is claimed.

## Startup measurements (first repair round)

Wall-clock medians of seven warm runs, after one warm-up run, on the same host with
identical pinned dependencies and temporary runtime directories:

| Configuration | Before | After |
| --- | ---: | ---: |
| Neovim headless startup and exit | 51.21 ms | 21.05 ms |
| Zsh interactive startup and exit | 558.82 ms | 69.15 ms |

The Neovim comparison used `DOTFILES_VERIFY=1` to suppress external tooling side
effects. The Zsh comparison disabled Oh My Zsh update checks and used a private
completion cache. These are local measurements, not cross-machine guarantees.

## Installation status and limits

Strict verification of the existing workstation intentionally returns nonzero:
its three Zsh plugin origins use proxy URLs outside the accepted GitHub/GitLab
identities, its lazy.nvim commit differs from the repository lock, and tmux-copycat
and tmux-better-mouse-mode are missing. The editor dependency check stops at the
manager mismatch; nvim-jdtls was also absent in the first-round workstation audit.
Missing dependencies
are reported rather than treated as successful verification. Their source pins
and real editor compatibility were validated separately in temporary directories.

No real apt update, system component installation, user-cache cleanup or live
configuration relinking was used for testing. Language server processes, optional
Mason tool downloads, parser compilation and desktop application builds depend on
external runtimes/development libraries and are not certified by these checks.
Configuration rollback does not undo package-manager or dependency updates.
