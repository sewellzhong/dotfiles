"""Shared dependency identities, worktree checks and serialized lock publication."""
import contextlib
import fcntl
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
from urllib.parse import urlsplit


def normalize(url):
    if not isinstance(url, str) or any(c.isspace() for c in url) or "\\" in url:
        raise ValueError(f'Invalid dependency URL: {url}')
    if re.fullmatch(r'(github|gitlab)\.com/[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+', url):
        host, path = url.split('/', 1)
    elif re.fullmatch(r'git@(github|gitlab)\.com:[A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+', url):
        host, path = url[4:].split(':', 1)
    else:
        parts = urlsplit(url)
        if (parts.scheme not in ('https', 'ssh') or parts.hostname not in ('github.com', 'gitlab.com')
                or parts.query or parts.fragment or parts.port is not None
                or parts.password or parts.username not in (None, 'git')
                or (parts.scheme == 'https' and parts.username is not None)):
            raise ValueError(f'Unsupported dependency URL: {url}')
        host, path = parts.hostname, parts.path.removeprefix('/')
    path = path.removesuffix('.git')
    segments = path.split('/')
    if (len(segments) < 2 or (host == 'github.com' and len(segments) != 2)
            or any(p in ('', '.', '..') or not re.fullmatch(r'[A-Za-z0-9_.-]+', p) for p in segments)):
        raise ValueError(f'Invalid dependency path: {url}')
    return host + '/' + path


def registry():
    home = Path(os.environ['HOME'])
    data = Path(os.environ.get('XDG_DATA_HOME', home / '.local/share'))
    rows = [
        ('so-fancy/diff-so-fancy', home / '.local/share/diff-so-fancy', 'DIFF_SO_FANCY_VERSION'),
        ('ohmyzsh/ohmyzsh', home / '.oh-my-zsh', 'OH_MY_ZSH_VERSION'),
        ('zsh-users/zsh-autosuggestions', home / '.oh-my-zsh/custom/plugins/zsh-autosuggestions', 'ZSH_AUTOSUGGESTIONS_VERSION'),
        ('zsh-users/zsh-syntax-highlighting', home / '.oh-my-zsh/custom/plugins/zsh-syntax-highlighting', 'ZSH_SYNTAX_HIGHLIGHTING_VERSION'),
        ('xvoland/Extract', home / '.oh-my-zsh/custom/plugins/extract', 'ZSH_EXTRACT_VERSION'),
        ('folke/lazy.nvim', data / 'nvim/lazy/lazy.nvim', 'LAZY_NVIM_VERSION'),
        ('tmux-plugins/tpm', home / '.config/tmux/plugins/tpm', 'TPM_VERSION'),
        ('tmux-plugins/tmux-copycat', home / '.config/tmux/plugins/tmux-copycat', 'TMUX_COPYCAT_VERSION'),
        ('nhdaly/tmux-better-mouse-mode', home / '.config/tmux/plugins/tmux-better-mouse-mode', 'TMUX_BETTER_MOUSE_MODE_VERSION'),
    ]
    return [('https://github.com/' + repo + '.git', path, variable) for repo, path, variable in rows]


def git(directory, *args):
    return subprocess.check_output(['git', '-C', str(directory), *args], text=True).strip()


def validate(directory, repo, commit=None):
    directory = Path(directory)
    if not (directory / '.git').exists():
        raise ValueError(f'Missing dependency: {directory}')
    if Path(git(directory, 'rev-parse', '--show-toplevel')).resolve() != directory.resolve():
        raise ValueError(f'Not a dependency repository root: {directory}')
    if normalize(git(directory, 'config', '--get', 'remote.origin.url')) != normalize(repo):
        raise ValueError(f'Unexpected origin: {directory}')
    head = git(directory, 'rev-parse', 'HEAD')
    if commit and head != git(directory, 'rev-parse', commit + '^{commit}'):
        raise ValueError(f'Dependency differs from lock: {directory}')
    if git(directory, 'status', '--porcelain', '--untracked-files=no'):
        raise ValueError(f'Tracked changes in dependency: {directory}')
    untracked = git(directory, 'ls-files', '--others', '--exclude-standard')
    if untracked:
        print(f'Untracked files outside the commit guarantee in {directory}:\n{untracked}', file=__import__('sys').stderr)
    return head


def read_lock(path):
    entries = {}
    for line in Path(path).read_text().splitlines():
        if not line or line.startswith('#'):
            continue
        repo, commit = line.split('\t')
        if normalize(repo) != repo or repo in entries or not re.fullmatch('[0-9a-f]{40}', commit):
            raise ValueError(f'Invalid or duplicate lock entry: {repo}')
        entries[repo] = commit
    if not entries:
        raise ValueError('Empty dependency lock')
    return entries


def check_locks(repo, lock=None):
    entries = read_lock(lock or repo / 'dotfiles.lock')
    nvim = json.loads((repo / 'nvim/.config/nvim/lazy-lock.json').read_text())
    if nvim['lazy.nvim']['commit'] != entries['github.com/folke/lazy.nvim']:
        raise ValueError('lazy.nvim commits differ between dependency locks')
    return entries


@contextlib.contextmanager
def operation_lock(repo):
    fd = os.open(repo / '.dotfiles-dependencies.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as stream:
        fcntl.flock(stream, fcntl.LOCK_EX)
        yield


def publish(path, content, snapshots):
    # Compare again immediately before publication; all our writers also hold the same flock.
    for source, previous in snapshots.items():
        if (source.read_bytes() if source.exists() else None) != previous:
            raise ValueError(f'Lock changed concurrently: {source}')
    fd, temporary = tempfile.mkstemp(prefix='.dotfiles-lock.', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, path.stat().st_mode & 0o777 if path.exists() else 0o644)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def snapshot(repo, lock):
    return {p: p.read_bytes() if p.exists() else None for p in (lock, repo / 'nvim/.config/nvim/lazy-lock.json')}


if __name__ == '__main__':
    import sys
    try:
        if sys.argv[1] == 'normalize':
            print(normalize(sys.argv[2]))
        elif sys.argv[1] == 'registry':
            for row in registry():
                print('\t'.join(map(str, row)))
        elif sys.argv[1] == 'validate':
            print(validate(*sys.argv[2:]))
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
