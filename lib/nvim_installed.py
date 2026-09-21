#!/usr/bin/env python3
"""Validate installed plugins and build independent checkouts for startup verification."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from dependencies import validate


def specs(config):
    with tempfile.TemporaryDirectory(prefix='dotfiles-specs-') as temp:
        output = Path(temp) / 'specs.json'
        env = dict(os.environ, NVIM_APPNAME='nvim', DOTFILES_NVIM_CONFIG=str(config), DOTFILES_NVIM_SPECS=str(output),
                   DOTFILES_SPEC_SCRIPT=str(Path(__file__).with_name('nvim-specs.lua')),
                   XDG_STATE_HOME=temp, XDG_CACHE_HOME=temp, NVIM_LOG_FILE=temp + '/nvim.log')
        subprocess.run(['nvim', '--headless', '--clean', '-u', 'NONE',
                        '+lua dofile(vim.env.DOTFILES_SPEC_SCRIPT)'], env=env, check=True)
        return json.loads(output.read_text())


def validate_lock(lock, origins):
    if not isinstance(lock, dict) or set(lock) != set(origins):
        raise ValueError('Plugin declarations and lock entries differ')
    for name, entry in lock.items():
        if (Path(name).name != name or name in ('.', '..') or not isinstance(entry, dict)
                or not isinstance(entry.get('commit'), str)
                or not re.fullmatch('[0-9a-f]{40}', entry['commit'])
                or not isinstance(entry.get('branch'), str)):
            raise ValueError(f'Invalid plugin lock entry: {name}')
        subprocess.run(['git', 'check-ref-format', '--branch', entry['branch']],
                       stdout=subprocess.DEVNULL, check=True)


def validate_plugin(directory, origin, commit=None):
    metadata = directory / '.git'
    if not metadata.is_dir() or metadata.is_symlink():
        raise ValueError(f'lazy.nvim requires an independent Git directory: {directory}')
    return validate(directory, origin, commit)


def check(lock, root, origins):
    validate_lock(lock, origins)
    for name, entry in lock.items():
        validate_plugin(root / name, origins[name], entry['commit'])


def clone_view(lock, root, view):
    view.mkdir(parents=True, exist_ok=True)
    for name, entry in lock.items():
        target = view / name
        # Transport clone: no hardlinks, shared objects, alternates or worktree symlinks.
        subprocess.run(['git', 'clone', '--quiet', '--no-local', '--no-hardlinks', '--depth=1', '--single-branch', '--no-checkout',
                        str(root / name), str(target)], check=True)
        subprocess.run(['git', '-C', str(target), 'checkout', '--quiet', '-B', entry['branch'],
                        entry['commit']], check=True)


def main():
    lockfile, root, view = map(Path, sys.argv[1:4])
    lock = json.loads(lockfile.read_text())
    check(lock, root, specs(Path(sys.argv[4]) if len(sys.argv) > 4 else lockfile.parent))
    clone_view(lock, root, view)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
