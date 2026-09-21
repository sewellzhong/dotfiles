#!/usr/bin/env python3
"""Journaled configuration changes. Never execute commands stored in a journal."""
import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
from datetime import datetime

HELPERS = Path(__file__).resolve().parent
IGNORE = (HELPERS / 'stow-private-pattern').read_text().strip()


def ignored_paths(repo, home, modules):
    paths = []
    for module in modules:
        base = repo / module
        if Path(module).name != module or module in ('.', '..') or not base.is_dir() or base.is_symlink():
            raise ValueError(f'Missing or invalid module: {module}')
        for directory, dirs, files in os.walk(base):
            for name in dirs + files:
                paths.append([module, str((Path(directory) / name).relative_to(base))])
    result = subprocess.run(['perl', str(HELPERS / 'stow-ignore.pl')],
                            input=json.dumps(dict(repo=str(repo), home=str(home), pattern=IGNORE, paths=paths)),
                            capture_output=True, text=True, check=True)
    return {tuple(item) for item in json.loads(result.stdout)}


def fingerprint(path):
    if path.is_symlink():
        return {"kind": "link", "target": os.readlink(path)}
    if path.is_file():
        return {"kind": "file", "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "mode": path.stat().st_mode & 0o777}
    if path.exists():
        return {"kind": "directory" if path.is_dir() else "special"}
    return None


def parents_safe(path, home):
    for parent in path.parents:
        if parent == home:
            return
        if parent.is_symlink() or (parent.exists() and not parent.is_dir()):
            raise ValueError(f"Unsafe parent (resolve manually): {parent}")
    raise ValueError(f"Path outside HOME: {path}")


def layout(repo, home, modules):
    ignored = ignored_paths(repo, home, modules)
    sources = {}
    directories = set()
    for module in modules:
        base = repo / module
        if not base.is_dir() or base.is_symlink():
            raise ValueError(f"Missing or invalid module: {module}")
        for directory, dirs, files in os.walk(base):
            dirs[:] = sorted(d for d in dirs if (module, str((Path(directory) / d).relative_to(base))) not in ignored)
            for name in dirs + sorted(files):
                source = Path(directory) / name
                rel = source.relative_to(base)
                if (module, str(rel)) in ignored:
                    continue
                target = home / rel
                parents_safe(target, home)
                if source.is_dir() and not source.is_symlink():
                    directories.add(str(rel))
                    if target.is_symlink() or (target.exists() and not target.is_dir()):
                        raise ValueError(f"Directory conflict: {target}")
                else:
                    if str(rel) in sources:
                        raise ValueError(f"Multiple modules provide: {rel}")
                    if target.is_dir() and not target.is_symlink():
                        raise ValueError(f"File conflict: {target}")
                    if fingerprint(target) and fingerprint(target)['kind'] == 'special':
                        raise ValueError(f"Special file conflict: {target}")
                    sources[str(rel)] = str(source)
    if directories.intersection(sources):
        raise ValueError("Modules contain conflicting file/directory paths")
    entries = []
    for rel, source in sorted(sources.items()):
        target = home / rel
        if target.is_symlink() and target.resolve() == Path(source).resolve():
            continue
        entries.append({"path": rel, "source": source, "source_state": fingerprint(Path(source)),
                        "before": fingerprint(target)})
    missing_dirs = sorted((p for p in directories if not (home / p).exists()),
                          key=lambda p: (len(Path(p).parts), p))
    return entries, missing_dirs


def save(batch, data):
    temp = batch / 'journal.tmp'
    with temp.open('w') as output:
        json.dump(data, output, indent=2)
        output.flush()
        os.fsync(output.fileno())
    temp.replace(batch / 'journal.json')


def validate_journal(data, home):
    if data.get('version') != 1 or data.get('home') != str(home):
        raise ValueError('Journal version or HOME mismatch')
    for rel in [e['path'] for e in data['entries']] + data['directories']:
        path = Path(rel)
        if path.is_absolute() or '..' in path.parts or not path.parts:
            raise ValueError('Invalid journal path')
        parents_safe(home / path, home)


def expected_link(target, entry):
    return (target.is_symlink() and target.resolve() == Path(entry['source']).resolve()
            and fingerprint(Path(entry['source'])) == entry['source_state'])


def restore(batch, home, dry=False):
    data = json.loads((batch / 'journal.json').read_text())
    validate_journal(data, home)
    if data['status'] == 'restored':
        print(f'Already restored: {batch.name}')
        return
    # Validate every target before changing any of them. This also makes interrupted
    # rollback restartable: an already-restored target matches its original snapshot.
    for entry in data['entries']:
        target = home / entry['path']
        backup = batch / 'files' / entry['path']
        current = fingerprint(target)
        if current == entry['before'] and not os.path.lexists(backup):
            continue
        if current is not None and not expected_link(target, entry):
            raise ValueError(f'Refusing to overwrite later changes: {target}')
        if entry['before'] is not None and fingerprint(backup) != entry['before']:
            raise ValueError(f'Missing or changed backup: {backup}')
    for entry in reversed(data['entries']):
        target = home / entry['path']
        backup = batch / 'files' / entry['path']
        if fingerprint(target) == entry['before'] and not os.path.lexists(backup):
            continue
        print(f'Restore: {target}')
        if dry:
            continue
        if target.is_symlink():
            target.unlink()
        if os.path.lexists(backup):
            target.parent.mkdir(parents=True, exist_ok=True)
            backup.rename(target)
    if not dry:
        for rel in reversed(data['directories']):
            with contextlib.suppress(FileNotFoundError, OSError):
                (home / rel).rmdir()  # Only remove empty directories created by this batch.
        data['status'] = 'restored'
        save(batch, data)


def confirm(args, text):
    if not args.yes and not args.dry_run:
        if input(text + ' [y/N] ').lower() not in ('y', 'yes'):
            raise ValueError('Cancelled')


def apply(args, repo, home):
    if (args.action == 'check' or args.dry_run) and not shutil.which('stow'):
        for module in args.modules:
            base = repo / module
            if Path(module).name != module or module in ('.', '..') or not base.is_dir() or base.is_symlink():
                raise ValueError(f'Missing or invalid module: {module}')
        print('Basic module check only: exact path/ignore preflight requires Stow and runs after installation.')
        return
    entries, directories = layout(repo, home, args.modules)
    for entry in entries:
        print(f"{'Back up and link' if entry['before'] else 'Link'}: {home / entry['path']}")
    if args.action == 'check' or args.dry_run:
        return
    if args.action == 'backup':
        entries = [e for e in entries if e['before'] is not None]
        directories = []
    if not entries:
        print('No configuration changes needed.')
        return
    confirm(args, 'Apply configuration changes?')
    batch = Path(tempfile.mkdtemp(prefix=datetime.now().strftime('%Y%m%d-%H%M%S-'),
                                 dir=home / '.dotfiles_backup'))
    data = {'version': 1, 'home': str(home), 'repo': str(repo), 'status': 'pending',
            'entries': entries, 'directories': directories}
    save(batch, data)
    print(f'Batch: {batch.name}', flush=True)
    try:
        for entry in entries:
            target = home / entry['path']
            if fingerprint(target) != entry['before']:
                raise ValueError(f'Target changed after preflight: {target}')
            if entry['before'] is not None:
                backup = batch / 'files' / entry['path']
                backup.parent.mkdir(parents=True, exist_ok=True)
                target.rename(backup)
        if args.action == 'link':
            command = ['stow', '--no-folding', '--ignore=' + IGNORE, '-d', str(repo),
                       '-S', '-t', str(home), *args.modules]
            subprocess.run([*command[:1], '-n', *command[1:]], env=dict(os.environ, HOME=str(home)), check=True)
            subprocess.run(command, env=dict(os.environ, HOME=str(home)), check=True)
            for entry in entries:
                if not expected_link(home / entry['path'], entry):
                    raise ValueError(f"Stow did not create the expected link: {entry['path']}")
        data['status'] = 'complete'
        save(batch, data)
    except BaseException:
        print('Configuration operation failed; restoring this batch.', file=sys.stderr)
        try:
            restore(batch, home)
        except Exception as error:
            print(f'Automatic recovery incomplete: {error}\nRun dotfiles.sh restore {batch.name}',
                  file=sys.stderr)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['check', 'backup', 'link', 'restore'])
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--home', type=Path, required=True)
    parser.add_argument('--batch')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--yes', action='store_true')
    parser.add_argument('modules', nargs='*')
    args = parser.parse_args()
    repo, home = args.repo.resolve(), args.home.resolve()
    if not home.is_dir():
        raise ValueError('HOME must exist')
    root = home / '.dotfiles_backup'
    if root.is_symlink():
        raise ValueError('Backup root must not be a symlink')
    if args.action == 'restore':
        if not args.batch or Path(args.batch).name != args.batch or args.batch in ('.', '..'):
            raise ValueError('Specify a backup batch name, not a path')
        batch = root / args.batch
        if batch.is_symlink():
            raise ValueError('Backup batch must not be a symlink')
    with contextlib.ExitStack() as stack:
        if not args.dry_run and args.action != 'check':
            root.mkdir(mode=0o700, exist_ok=True)
            fd = os.open(root / '.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
            lock = stack.enter_context(os.fdopen(fd, 'w'))
            fcntl.flock(lock, fcntl.LOCK_EX)
        if args.action == 'restore':
            confirm(args, f'Restore batch {args.batch}?')
            restore(batch, home, args.dry_run)
        else:
            apply(args, repo, home)


def interrupted(signum, frame):
    raise InterruptedError(f'Interrupted by signal {signum}')


if __name__ == '__main__':
    signal.signal(signal.SIGTERM, interrupted)
    try:
        main()
    except (Exception, KeyboardInterrupt) as error:
        print(f'Error: {error}', file=sys.stderr)
        sys.exit(1)
