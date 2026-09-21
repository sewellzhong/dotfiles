# Dotfiles / 个人配置

使用 GNU Stow 管理 Bash/Zsh、Git、SSH、tmux、Vim/Neovim 和常用终端工具。
主要支持 Debian/Ubuntu；仓库可以放在任意目录，包括含空格的路径。

## 中文指南

### 快速开始

需要预先安装 `bash`、`python3`、`git` 和 `sudo`。安装模式还需要
`apt-get`、`apt-cache`、`dpkg-query` 和 `flock`；只链接配置需要 `stow`（含其 Perl 模块）。

```sh
./dotfiles.sh --dry-run
./dotfiles.sh
./dotfiles.sh verify
```

`--yes` 跳过脚本确认。预览不安装、不备份、不修改锁文件。首次安装直接克隆
Oh My Zsh，不修改登录 Shell，也不重复执行其官方安装器。

| 命令 | 行为 |
| --- | --- |
| `./dotfiles.sh` | 检查冲突、安装依赖、备份并链接配置 |
| `./dotfiles.sh install` | 安装系统依赖、按锁恢复插件 |
| `./dotfiles.sh backup [模块]` | 只备份冲突目标 |
| `./dotfiles.sh link [模块]` | 备份后链接全部或单个模块 |
| `./dotfiles.sh restore 批次` | 恢复该批次的配置操作 |
| `./dotfiles.sh verify --static` | 仓库静态检查，不代表安装验收通过 |
| `./dotfiles.sh verify` | 静态检查及已安装依赖、Neovim 插件验收 |
| `./dotfiles.sh lock` | 将完整、来源正确且无已跟踪修改的依赖提交写入锁 |

支持 `--mode`、`--module`；单模块操作仅用于 `backup` 和 `link`。
`restore` 接受备份目录下的批次名称，不接受任意路径。

### 软件包与运行时

默认安装 `base`，通过 `DOTFILES_APT_GROUPS` 添加其他组：

```sh
DOTFILES_APT_GROUPS="base desktop" ./dotfiles.sh install
DOTFILES_APT_GROUPS="base server" ./dotfiles.sh install
```

| 组 | 主要内容 |
| --- | --- |
| `base` | Git、Stow、Zsh、Neovim、tmux、fzf、ripgrep、Python 3、jq、bc、Node.js/npm、unzip 等 |
| `desktop` | Alacritty、字体 |
| `server` | openssh-server |
| `optional` | autojump、glow、yt-dlp、traceroute 等 |

所有 apt 组先完成校验，缺失软件包去重后只执行一次索引更新和一次安装。
任何 apt/Git 变更前，检查 PATH 实际选中的 Neovim >= 0.10.4，或缓存中的 apt 候选版本
能满足要求；自定义旧版 nvim 遮蔽系统程序时提前报错。安装后再次检查实际版本。
预览不会刷新 apt 索引；无法判断候选版本时会明确提示，真实安装要求先解决该问题。

Neovim 配置以 **0.10.4** 为兼容基线。插件安装前检查 `nvim`、`node`、`npm`、
`unzip`、`tar`；Python/Node provider 的自定义路径只在程序存在时启用。

语言服务器、格式化器、解析器是单独安装的外部工具，不在 Git 插件锁的覆盖范围内。
启动编辑器不会自动安装它们；需要时运行 `:MasonToolsInstall` 和 `:TSUpdate`。
Node 工具需要 Node.js/npm；Lua、Shell 工具按 Mason 要求提供相应运行时；
PHP 检查需要 `php`，Java 服务需另行配置 JDK 与 jdtls，Treesitter 编译需要 C 编译器。
这些可选语言功能不作为所有机器的安装前置条件。

桌面源码构建工具由 `update-beauty` 按组件预检，不放进默认基础安装：

| 组件 | 必需命令（另外需要 Git；自动查版本需要 curl/jq） |
| --- | --- |
| i3 / rofi / picom | meson、ninja、cc、pkg-config |
| i3blocks / i3lock | autoreconf、make、cc、pkg-config |
| dunst | make、cc、pkg-config |

项目所需系统开发库以各项目的构建检查为准；缺库或编译失败会阻止安装。

### 备份、失败恢复与冲突

配置变更前检查所有选定模块，包括文件/目录冲突和模块间重复目标。
已指向正确源文件的链接保持原样。其他文件和符号链接移动到：

```text
~/.dotfiles_backup/YYYYMMDD-HHMMSS-唯一后缀/
  journal.json
  files/原始相对路径
```

备份后先运行整体 Stow dry-run，再执行链接。任一步失败会尝试恢复本批配置。
同一 HOME 下的备份、链接和恢复串行执行。文件父目录为符号链接时要求手动处理，
避免修改 HOME 之外的内容。

```sh
./dotfiles.sh restore 20260921-120000-示例批次 --dry-run
./dotfiles.sh restore 20260921-120000-示例批次
```

恢复会先检查整批目标，拒绝覆盖安装后新增或修改的文件；通过链接修改了仓库源文件时，
也会拒绝自动覆盖。先手动保存这些修改再恢复。重复恢复已完成的批次不会再次修改文件。
进程被强制终止后可以使用保留的 journal 手动恢复；旧版本没有 journal 的备份需手工恢复。

**恢复范围仅限配置文件和符号链接，不包括 apt 软件包或第三方依赖版本。**

### 私有配置与 SSH

支持按需加载：

```text
~/.config/common/.aliases.local
~/.config/common/.exports.local
~/.config/common/.functions.local
~/.config/zsh/.zshrc.local
~/.config/git/.gitconfig.local
~/.ssh/config.local
```

Git 忽略 `*.local`、`*.secret`、`*.private`、`.env*` 等本地配置。
安装脚本的 Stow 操作额外排除带 local/secret/private/personal 后缀的私有文件；
`.local/bin` 仍正常链接。预检直接调用已安装 Stow 的 Perl 模块，遵循包内
`.stow-local-ignore`、HOME 中 `.stow-global-ignore` 和默认规则的实际优先级。
首次缺少 Stow 时只检查模块，安装 Stow 后再执行精确检查，之后才移动配置。

SSH 先读取 `config.local`，再读取仓库中的个人主机配置，同名选项采用本地值。
本仓库有意保留服务器名称、账户、端口与密钥路径；分享仓库时这些信息也会被分享。
私钥不应存放到仓库中。

### 依赖锁与更新

`dotfiles.lock` 固定 9 个外部 Git 依赖；Neovim 的 `lazy-lock.json` 固定所有声明的
编辑器插件。两份锁中的 lazy.nvim 提交必须一致。安装使用锁恢复，更新是显式操作。

安装、更新、锁生成和验收共用依赖清单及来源校验，只接受 GitHub/GitLab 的 HTTPS、
SSH URI 和 SCP 风格地址；同时检查仓库根目录、提交和已跟踪修改。未跟踪文件单独报告，
不在提交锁的保证范围内。同一仓库的安装和锁写入串行执行；发布前复核锁是否被外部修改。

`update --nvim` 使用仓库的绝对配置路径更新插件，在独立临时 Git 工作树中验证配置后，
原子发布 `lazy-lock.json`。lazy.nvim 管理器保持固定版本，两份锁必须一致。
`update-beauty oh-my-zsh` 更新 Oh My Zsh 和清单中的 3 个第三方插件，支持 detached HEAD，
全部成功后只同步对应的 `dotfiles.lock` 记录，跳过 archive 和其他自定义目录。
失败返回非零并保留旧锁；部分插件工作树可能已更新，可用 `./dotfiles.sh install` 恢复锁定版本。
`./dotfiles.sh lock` 用于手动记录其他有意更新的依赖，要求全部依赖来源正确且无已跟踪修改。

```sh
# 更新成功并验证配置后自动同步对应的锁记录
update --nvim --yes
update-beauty --yes oh-my-zsh
# 其他依赖显式更新并验证后，手动记录新的 Git 提交：
./dotfiles.sh lock

# 私有 Git 依赖锁
DOTFILES_LOCK_FILE="$HOME/.cache/dotfiles/dotfiles.lock" ./dotfiles.sh lock
DOTFILES_LOCK_FILE="$HOME/.cache/dotfiles/dotfiles.lock" ./dotfiles.sh install

# 单次覆盖须通过环境变量传给脚本
ZSH_AUTOSUGGESTIONS_VERSION=v0.7.1 ./dotfiles.sh install
# 主动关闭 Git 依赖锁（Neovim 插件仍按 lazy-lock.json 恢复）
DOTFILES_USE_LOCK=false ./dotfiles.sh install
```

可覆盖变量：`OH_MY_ZSH_VERSION`、`DIFF_SO_FANCY_VERSION`、`LAZY_NVIM_VERSION`、
`ZSH_AUTOSUGGESTIONS_VERSION`、`ZSH_SYNTAX_HIGHLIGHTING_VERSION`、`ZSH_EXTRACT_VERSION`、
`TPM_VERSION`、`TMUX_COPYCAT_VERSION`、`TMUX_BETTER_MOUSE_MODE_VERSION`。
修改 lazy.nvim 版本时也需同步编辑器锁；严格验证会报告版本不一致。

### 验证与回归

```sh
./dotfiles.sh verify --static
./dotfiles.sh verify
bash tests/run.sh
```

静态验证需要 Bash、Zsh、Stow、ShellCheck、Neovim 和 Python 3；逐文件检查语法，
校验锁、所有模块布局及 Lua 配置。安装验收还检查外部 Git 依赖与锁的一致性，以及
所有声明的 Neovim 插件存在、提交匹配、能够加载配置。

验证使用临时 XDG state/cache/data/config 和独立 Git 检出，插件目录不链接或硬链接到用户目录。
禁止自动安装、更新和格式化。
缺失依赖和初始化失败返回非零。静态通过不表示语言服务器、构建工具或实际安装已就绪。
离线回归在临时 HOME 中模拟安装与错误，不执行真实 apt 更新或系统安装。
真实编辑器集成测试另行运行；依赖缺失会失败，不会跳过：

```sh
# 准备阶段需要网络，目标目录必须不存在
bash tests/prepare-lazy.sh /tmp/dotfiles-lazy-seed
DOTFILES_LAZY_SEED=/tmp/dotfiles-lazy-seed bash tests/integration.sh
```

集成测试使用真实固定版本 lazy.nvim 和本地 Git 插件仓库，测试阶段只允许 file 传输。
GitHub Actions 固定 Ubuntu 24.04 / Neovim 0.10.4，依次执行静态、离线和集成检查。
本地验证结果及未覆盖范围见 [tests/VALIDATION.md](tests/VALIDATION.md)。

### 日常使用

- `TERM` 由终端、tmux 或 SSH 决定，共享 Shell 配置不覆盖它。
- `stow` 函数从配置链接定位仓库，也可用 `DOTFILES_DIR` 覆盖；直接调用 `command stow` 绕过函数。
- `rg` 默认遵循忽略规则，不主动搜索隐藏文件或跟随链接；`rgdeep` 显式扩大搜索范围。
- `cleaner --cache --dry-run` 预览清理；`--cache` 仅删除 `$XDG_CACHE_HOME`（默认 `~/.cache`）
  下的 nvim、zsh、fzf 缓存目录，跳过符号链接，保留未知目录。
- 历史、编辑器状态和系统日志清理仍要求 `--dangerous`。
- `update --dry-run -a` 预览包管理器更新；真实更新请显式执行 `update -a`。
- `update-beauty rofi` 默认仅构建；`--install` 才允许系统安装，`--clean` 才允许 `git clean`。
  使用 `DOTFILES_UPDATE_BEAUTY_REF` 固定构建版本；任何组件失败会在末尾返回非零。

## English reference

### Install and verify

Requirements: Bash, Python 3, Git, sudo and an apt-based system. Linking requires GNU Stow.
The repository can live anywhere, including paths containing spaces. Neovim 0.10.4 is the
compatibility baseline. Run `./dotfiles.sh --dry-run` before installing.

- `full` (default): preflight, install dependencies, back up conflicting configuration, link modules.
- `install`: install packages and restore pinned plugins; does not run the Oh My Zsh installer.
- `backup [module]` / `link [module]`: all modules or one module; `--module` is also supported.
- `restore BATCH`: restore a journaled configuration batch; supports `--dry-run` and `--yes`.
- `verify --static`: repository syntax, lock and layout checks; does not certify an installation.
- `verify`: additionally validate installed Git commits and load all declared Neovim plugins.
- `lock`: atomically record all installed, correctly sourced, clean Git dependencies.

Only the `base` package group is installed by default. Add `desktop`, `server`, or `optional`
through `DOTFILES_APT_GROUPS`. Base includes jq, bc, Python 3, Node.js/npm and unzip.
All apt groups are validated before changes; missing packages are deduplicated into one
apt update/install. Preflight checks the actual Neovim executable or cached apt candidate
against 0.10.4 and rejects an older executable shadowing the apt binary. It checks again
after installation. Dry runs do not refresh apt indexes and report unknown candidates.
Build tools and optional language runtimes are checked/documented separately.
Use `:MasonToolsInstall` and `:TSUpdate` explicitly; startup does not download tools.
Language servers and parser binaries are outside the Git dependency locks.

### Recovery and local configuration

Configuration operations are serialized per HOME. Each batch under `~/.dotfiles_backup/`
contains `journal.json` and the moved files. Failed operations attempt automatic recovery;
interrupted batches can be restored manually. Restore refuses to overwrite later changes,
including source edits made through managed links. Apt packages and dependency updates are
not rolled back. Old backups without a journal require manual recovery.

Stow preflight uses the installed Perl Stow module for package/global/default ignore rules,
plus one shared private-file pattern. `.local/bin` is included. With Stow missing, full install
performs basic checks first and exact preflight after installing Stow, before moving files.
Optional `.local` files remain supported. SSH reads local overrides first and resets Host
matching before including the tracked personal hosts. Server metadata intentionally remains
tracked. Parent-directory symlinks require manual resolution before configuration changes.

### Pins, helpers and tests

Installation restores both Git dependency pins and the tracked Neovim lock. Explicit
`update --nvim` updates editor plugins with the repository's absolute config path, verifies
independent temporary checkouts, then atomically publishes `lazy-lock.json`. The lazy.nvim
manager stays pinned. `update-beauty oh-my-zsh` updates the four registered Zsh repositories
from their remote default branches (including detached HEADs) and publishes only those lock
records. Other custom plugins are left alone. Both locks must agree on lazy.nvim.
Failed updates keep the previous locks but may change worktrees; use `./dotfiles.sh install`
to restore pins. Use `./dotfiles.sh lock` to record other intentional dependency updates. Missing dependencies, invalid
origins or tracked modifications prevent lock replacement. Environment overrides must be
exported or supplied inline, e.g. `ZSH_AUTOSUGGESTIONS_VERSION=v0.7.1 ./dotfiles.sh install`.

`stow` locates the repository through its linked shared configuration. `TERM` is inherited.
`rg` respects ignore rules; `rgdeep` opts into hidden files, symlinks and ignored files.
`cleaner --cache` uses an explicit nvim/zsh/fzf allowlist and does not follow cache symlinks.
`update-beauty` checks build tools before changing source trees, stops a failed component,
never installs after a failed build, and reports aggregate failures with a nonzero exit.

Run `bash tests/run.sh` for offline regressions. Verification requires Bash, Zsh, Stow,
ShellCheck, Neovim and Python 3; it uses independent temporary Git checkouts and runtime
directories. Origin, repository root, HEAD and tracked changes are checked; untracked files
are reported separately. Optional language servers still require their own runtime setup.

Prepare a verified manager seed with `bash tests/prepare-lazy.sh /tmp/dotfiles-lazy-seed`
(network required), then run `DOTFILES_LAZY_SEED=/tmp/dotfiles-lazy-seed bash tests/integration.sh`.
Integration uses real lazy.nvim with local remotes and disallows network transports; missing
prerequisites fail the suite. CI targets Ubuntu 24.04 and Neovim 0.10.4 with a pinned checkout
action and read-only token. See [validation results and limits](tests/VALIDATION.md).

## 模块 / Modules

`bin`, `dircolors`, `bash`, `zsh`, `common`, `ssh`, `git`, `tmux`, `bat`, `glow`,
`htop`, `nvim`, `vim`, `wget`, `yt-dlp`, `ripgrep`, `alacritty`。

安装、备份、链接与验证共享同一模块清单；缺失模块会报错。
