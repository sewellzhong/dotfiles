# Dotfiles / 个人配置

个人 dotfiles 仓库，使用 GNU Stow 管理 shell、Git、tmux、Neovim、SSH 和常用
命令行工具配置。

> 默认面向 Debian/Ubuntu 或其他 apt 系 Linux。真实安装前建议先运行
> `./dotfiles.sh --dry-run`。

每个顶层目录都是一个 Stow 模块，目录结构对应 `$HOME` 下的真实路径。
`dotfiles.sh` 会自动把脚本所在目录作为 dotfiles 根目录，所以仓库不必固定
放在 `~/.dotfiles`。

## 目录

- [中文指南](#中文指南)
  - [快速开始](#快速开始)
  - [环境要求](#环境要求)
  - [安装模式](#安装模式)
  - [软件包组](#软件包组)
  - [备份和冲突](#备份和冲突)
  - [私有配置](#私有配置)
  - [外部依赖锁](#外部依赖锁)
  - [本地验证](#本地验证)
- [English Reference](#english-reference)
- [模块列表](#模块列表)
- [维护命令](#维护命令)
- [辅助脚本](#辅助脚本)

## 命令速查

| 场景 | 命令 |
| --- | --- |
| 预览安装动作 | `./dotfiles.sh --dry-run` |
| 默认安装 | `./dotfiles.sh` |
| 只链接配置 | `./dotfiles.sh link` |
| 只链接 Git 模块 | `./dotfiles.sh link git` |
| 运行验证 | `./dotfiles.sh verify` |
| 更新依赖锁 | `./dotfiles.sh lock` |
| 桌面环境安装 | `DOTFILES_APT_GROUPS="base desktop" ./dotfiles.sh` |
| 服务器环境安装 | `DOTFILES_APT_GROUPS="base server" ./dotfiles.sh` |

---

## 中文指南

### 快速开始

这个仓库用于管理个人 shell、Git、tmux、Neovim、SSH 等配置。安装脚本会：

- 安装基础依赖和外部插件
- 备份 `$HOME` 下已有的冲突文件
- 使用 GNU Stow 创建符号链接
- 使用 `dotfiles.lock` 固定外部 Git 依赖版本

建议每次真实执行前先 dry-run：

```sh
./dotfiles.sh --dry-run
```

确认输出无误后再安装：

```sh
./dotfiles.sh
```

跳过确认提示：

```sh
./dotfiles.sh --yes
```

### 环境要求

- Debian/Ubuntu 或其他 apt 系 Linux
- `bash`
- `git`
- `sudo`

`full` 和 `install` 模式会通过 `apt-get` 安装缺失软件。`link` 模式需要系统
已有 `stow`。

### 安装模式

| 命令 | 用途 |
| --- | --- |
| `./dotfiles.sh` | 默认 `full` 模式：安装依赖、备份冲突、链接模块 |
| `./dotfiles.sh install` | 只安装 apt 依赖和外部插件 |
| `./dotfiles.sh backup` | 只备份会冲突的现有配置 |
| `./dotfiles.sh link` | 备份冲突后，只链接配置 |
| `./dotfiles.sh backup git` | 只备份 `git` 模块的冲突配置 |
| `./dotfiles.sh link git` | 备份冲突后，只链接 `git` 模块 |
| `./dotfiles.sh verify` | 运行本地验证 |
| `./dotfiles.sh lock` | 写入当前外部 Git 依赖版本锁 |

等价长参数：

```sh
./dotfiles.sh --mode install
./dotfiles.sh --mode backup
./dotfiles.sh --mode link
```

`backup` 和 `link` 可以指定一个模块，既可使用位置参数，也可使用
`--module`：

```sh
./dotfiles.sh link git
./dotfiles.sh backup --module zsh
./dotfiles.sh link --module git --dry-run
```

### 软件包组

默认只安装 `base` 软件包组，避免在服务器上意外安装桌面组件或
`openssh-server`。

| 组 | 用途 |
| --- | --- |
| `base` | Git、Stow、Zsh、Neovim、tmux、fzf、ripgrep 等基础工具 |
| `desktop` | 字体和 Alacritty 等桌面组件 |
| `server` | `openssh-server` |
| `optional` | glow、yt-dlp、traceroute 等可选工具 |

桌面机器：

```sh
DOTFILES_APT_GROUPS="base desktop" ./dotfiles.sh
```

服务器：

```sh
DOTFILES_APT_GROUPS="base server" ./dotfiles.sh
```

完整个人环境：

```sh
DOTFILES_APT_GROUPS="base desktop server optional" ./dotfiles.sh
```

### 备份和冲突

链接前，脚本会检查 `$HOME` 下已有目标：

- 如果目标已经指向本仓库中的同一文件，会跳过
- 如果目标是普通文件或其他符号链接，会移动到备份目录
- 如果文件/目录形状冲突，脚本会停止并要求手动处理

备份目录格式：

```text
~/.dotfiles_backup/YYYYMMDD-HHMMSS/
```

示例：

```text
/home/user/.bashrc -> /home/user/.dotfiles_backup/YYYYMMDD-HHMMSS/.bashrc
```

### 私有配置

机器相关或敏感配置不要提交到仓库。以下本地文件会在存在时自动加载：

```text
~/.config/common/.aliases.local
~/.config/common/.exports.local
~/.config/common/.functions.local
~/.config/zsh/.zshrc.local
~/.config/git/.gitconfig.local
~/.ssh/config.local
```

`.gitignore` 已忽略 `*.local`、`*.secret`、`*.private` 和 `.env*`。

### 外部依赖锁

默认使用仓库内的 `dotfiles.lock` 固定外部 Git 依赖版本。更新 Oh My Zsh、
lazy.nvim、tmux 插件等外部依赖后，运行：

```sh
./dotfiles.sh lock
```

使用本机私有 lock 文件：

```sh
DOTFILES_LOCK_FILE="$HOME/.cache/dotfiles/dotfiles.lock" ./dotfiles.sh lock
DOTFILES_LOCK_FILE="$HOME/.cache/dotfiles/dotfiles.lock" ./dotfiles.sh install
```

临时覆盖单个依赖版本：

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

### 本地验证

运行完整验证：

```sh
./dotfiles.sh verify
```

验证内容包括：

- Bash 语法检查
- Zsh 语法检查
- Stow dry-run
- Neovim headless 启动检查
- ShellCheck 检查，如果已安装

Neovim 验证使用隔离的 state/cache 目录，不依赖也不修改本机编辑器状态。

---

## English Reference

### Requirements

- Debian/Ubuntu or another apt-based Linux distribution
- `bash`
- `git`
- `sudo`

Install modes require `sudo`, `git`, `apt-get`, and `dpkg-query`. Link modes
require `stow`, unless `full` mode installs it first.

### Install

Preview all actions:

```sh
./dotfiles.sh --dry-run
```

Install dependencies and link configured modules:

```sh
./dotfiles.sh
```

Run a specific mode:

```sh
./dotfiles.sh install
./dotfiles.sh backup
./dotfiles.sh link
./dotfiles.sh verify
./dotfiles.sh lock
```

Limit backup or linking to one configured module:

```sh
./dotfiles.sh link git
./dotfiles.sh backup --module zsh
./dotfiles.sh link --module git --dry-run
```

Available modes:

| Mode | Description |
| --- | --- |
| `full` | Install dependencies and plugins, back up conflicts, then link modules |
| `install` | Install apt packages, Oh My Zsh, Neovim plugin manager, and tmux plugins |
| `backup` | Move conflicting target files into `~/.dotfiles_backup` |
| `link` | Back up conflicts, then link modules with Stow |
| `verify` | Run local syntax, Stow, Neovim, and optional ShellCheck checks |
| `lock` | Write installed Git dependency commits to `dotfiles.lock` |

By default only the `base` apt package group is installed. Add more groups with
`DOTFILES_APT_GROUPS`, for example:

```sh
DOTFILES_APT_GROUPS="base desktop" ./dotfiles.sh install
```

### Backup Behavior

Before linking files, the installer checks for existing target files in `$HOME`.
Matching symlinks are left alone. Other files or symlinks are moved into:

```text
~/.dotfiles_backup/YYYYMMDD-HHMMSS/
```

Path-shape conflicts are not resolved automatically. If a target directory
exists where the repository provides a file, or the reverse, the installer stops
and asks you to resolve it manually.

### Local Private Configuration

Machine-specific or private settings should stay outside the repository. The
tracked config loads optional local files when present:

```text
~/.config/common/.aliases.local
~/.config/common/.exports.local
~/.config/common/.functions.local
~/.config/zsh/.zshrc.local
~/.config/git/.gitconfig.local
~/.ssh/config.local
```

Files matching `*.local`, `*.secret`, `*.private`, and `.env*` are ignored by
default.

## 模块列表

| Module | Description |
| --- | --- |
| `bash` | Bash startup configuration |
| `zsh` | Zsh and Oh My Zsh configuration |
| `common` | Shared aliases, exports, and functions |
| `bin` | Scripts installed into `~/.local/bin` |
| `git` | Global Git configuration and ignore rules |
| `ssh` | SSH config entry point |
| `tmux` | tmux configuration |
| `nvim` | Neovim configuration |
| `vim` | Vim configuration |
| `dircolors` | Custom `LS_COLORS` |
| `bat` | bat configuration |
| `glow` | glow configuration |
| `htop` | htop configuration |
| `ripgrep` | ripgrep configuration |
| `wget` | wget configuration |
| `yt-dlp` | yt-dlp configuration |
| `alacritty` | Alacritty configuration |

## 维护命令

Relink one module through the script, including its conflict backup checks:

```sh
./dotfiles.sh link git
```

Run the underlying Stow command manually:

```sh
stow --no-folding -d "$PWD" -R -t "$HOME" zsh
```

Check what Stow would do:

```sh
stow -n --no-folding -d "$PWD" -R -t "$HOME" zsh
```

Run individual verification checks:

```sh
bash -n dotfiles.sh bin/.local/bin/update bin/.local/bin/update-beauty bin/.local/bin/cleaner bin/.local/bin/rofi-calendar bin/.local/bin/sizeof
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
against `nvim/.config/nvim/init.lua`. Normal Neovim startup does not
auto-install missing plugins; after changing plugin specs, run `:Lazy sync` or
`./dotfiles.sh install`.

tmux plugins are installed under:

```text
~/.config/tmux/plugins/
```

The tmux config only loads TPM when it already exists.

## 辅助脚本

### `cleaner`

Target cleanup by group:

```sh
cleaner --dry-run --cache
cleaner --cache
```

Irreversible groups require `--dangerous`:

```sh
cleaner --history --dangerous
cleaner --editor-state --dangerous
cleaner --system-logs --dangerous
```

### `update`

Refresh system and language package managers. Use dry-run first:

```sh
update --dry-run -a
update -a
```

### `update-beauty`

Build desktop components from source repositories under `~/.local/src`.
Builds do not write into system paths unless `--install` is passed.

```sh
update-beauty rofi
update-beauty --install i3 picom
```

Pin an explicit ref instead of discovering the latest release:

```sh
DOTFILES_UPDATE_BEAUTY_REF=v1.0 update-beauty rofi
```

`update-beauty` only shows `git clean -fdn` output by default. Pass `--clean`
when you intentionally want it to remove untracked files before building.

## Notes

This installer is intentionally tailored for personal apt-based systems. On
other platforms, prefer using `stow` manually or adapt `dotfiles.sh` before
running it.
