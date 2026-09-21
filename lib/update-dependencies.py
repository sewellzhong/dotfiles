#!/usr/bin/env python3
"""Explicit checked updates. Publish locks only after every selected operation succeeds."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from dependencies import (check_locks, git, normalize, operation_lock, publish,
                          registry, snapshot, validate)
from nvim_installed import check, clone_view, specs, validate_lock, validate_plugin


def update_zsh(repo, lock, before, dry):
    selected = registry()[1:5]
    for origin, directory, _ in selected:
        validate(directory, origin)
    if dry:
        for origin, directory, _ in selected:
            print(f'+ fetch default branch and check out explicit commit: {origin} -> {directory}')
        print(f'+ publish selected records in {lock}')
        return
    targets = []
    for origin, directory, _ in selected:
        remote = git(directory, 'ls-remote', '--symref', 'origin', 'HEAD')
        branch = next((line.split()[1] for line in remote.splitlines()
                       if line.startswith('ref: refs/heads/') and line.endswith('\tHEAD')), None)
        if not branch:
            raise ValueError(f'Cannot resolve remote default branch: {origin}')
        git(directory, 'fetch', '--no-tags', 'origin', branch)
        targets.append((origin, directory, git(directory, 'rev-parse', 'FETCH_HEAD^{commit}')))
    for origin, directory, commit in targets:
        git(directory, 'checkout', '--detach', commit)
        validate(directory, origin, commit)
    updates = {normalize(origin): commit for origin, _, commit in targets}
    lines = []
    for line in before[lock].decode().splitlines():
        key = line.split('\t', 1)[0]
        lines.append(key + '\t' + updates[key] if key in updates else line)
    publish(lock, ('\n'.join(lines) + '\n').encode(), before)


def update_nvim(repo, lock, before, dry):
    config = repo / 'nvim/.config/nvim'
    tracked = config / 'lazy-lock.json'
    expected = json.loads(before[tracked])
    root = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'nvim/lazy'
    origins = specs(config)
    validate_lock(expected, origins)
    for name, origin in origins.items():
        directory = root / name
        if os.path.lexists(directory) or name == 'lazy.nvim':
            validate_plugin(directory, origin, expected[name]['commit'] if name == 'lazy.nvim' else None)
    if dry:
        print(f'+ checked Neovim update using {config}/init.lua; keep lazy.nvim pinned')
        print(f'+ independently validate configuration, then publish {tracked}')
        return
    with tempfile.TemporaryDirectory(prefix='dotfiles-nvim-update-') as temporary:
        temp = Path(temporary)
        candidate = temp / 'lazy-lock.json'
        candidate.write_bytes(before[tracked])
        env = dict(os.environ, NVIM_APPNAME='nvim', DOTFILES_NVIM_SYNC='1', DOTFILES_NVIM_LOCK=str(candidate),
                   XDG_STATE_HOME=str(temp / 'state'), XDG_CACHE_HOME=str(temp / 'cache'),
                   NVIM_LOG_FILE=str(temp / 'nvim.log'))
        subprocess.run(['nvim', '--headless', '--clean', '-u', str(config / 'init.lua'),
                        '+lua local ok,e=pcall(function() require("dotfiles.install").run(true) end); '
                        'if not ok then vim.api.nvim_err_writeln(e); vim.cmd("cquit 1") end'],
                       env=env, check=True)
        updated = json.loads(candidate.read_text())
        if updated['lazy.nvim']['commit'] != expected['lazy.nvim']['commit']:
            raise ValueError('Update tried to change the pinned lazy.nvim manager')
        check(updated, root, origins)
        clone_view(updated, root, temp / 'data/nvim/lazy')
        env.update(DOTFILES_VERIFY='1', XDG_DATA_HOME=str(temp / 'data'),
                   XDG_CONFIG_HOME=str(temp / 'config'), DOTFILES_NVIM_CHECK=str(repo / 'lib/nvim-check.lua'))
        subprocess.run(['nvim', '--headless', '--clean', '-u', str(config / 'init.lua'),
                        '+lua local ok,e=pcall(dofile,vim.env.DOTFILES_NVIM_CHECK); '
                        'if not ok then vim.api.nvim_err_writeln(e); vim.cmd("cquit 1") end'],
                       env=env, check=True)
        # Configuration callbacks cannot redefine the candidate being published.
        if json.loads(candidate.read_text()) != updated:
            raise ValueError('Validation modified the candidate lock')
        publish(tracked, candidate.read_bytes(), before)


def write_lock(repo, lock, before, dry):
    entries = {normalize(origin): validate(directory, origin) for origin, directory, _ in registry()}
    manager = json.loads(before[repo / 'nvim/.config/nvim/lazy-lock.json'])['lazy.nvim']['commit']
    if entries['github.com/folke/lazy.nvim'] != manager:
        raise ValueError('lazy.nvim commits differ between dependency locks')
    content = '# repo\tcommit\n' + ''.join(f'{origin}\t{commit}\n' for origin, commit in entries.items())
    if dry:
        print(content, end='')
    else:
        lock.parent.mkdir(parents=True, exist_ok=True)
        publish(lock, content.encode(), before)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('component', choices=('zsh', 'nvim', 'lock'))
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--lock', type=Path)
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    repo = args.repo.resolve()
    lock = (args.lock or Path(os.environ.get('DOTFILES_LOCK_FILE', repo / 'dotfiles.lock'))).resolve()
    def run():
        before = snapshot(repo, lock)
        if args.component != 'lock':
            entries = check_locks(repo, lock)
            for origin, _, _ in registry():
                if normalize(origin) not in entries:
                    raise ValueError(f'Missing lock entry: {origin}')
        {'zsh': update_zsh, 'nvim': update_nvim, 'lock': write_lock}[args.component](repo, lock, before, args.dry_run)
    if args.dry_run:
        run()
    else:
        with operation_lock(repo):
            run()


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(f'Dependency operation failed: {error}\nLocks were not published. Worktrees may have changed; '
                 'restore pinned versions with ./dotfiles.sh install.')
