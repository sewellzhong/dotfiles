#!/usr/bin/env python3
"""Check the executable actually selected by PATH before apt or Git mutations."""
import argparse
import re
import shutil
import subprocess
import sys

MINIMUM = (0, 10, 4)


def version(text):
    match = re.search(r'(\d+)\.(\d+)\.(\d+)', text)
    return tuple(map(int, match.groups())) if match else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--installed', action='store_true')
    args = parser.parse_args()
    executable = shutil.which('nvim')
    current = None
    if executable:
        output = subprocess.run([executable, '--version'], text=True, capture_output=True, check=True)
        current = version(output.stdout)
        if current and current >= MINIMUM:
            return
    if args.installed:
        raise ValueError('The active nvim executable must be >= 0.10.4 after package installation')
    if executable and executable not in ('/usr/bin/nvim', '/bin/nvim'):
        raise ValueError(f'{executable} shadows the apt executable and is older than 0.10.4 or unverifiable; fix PATH first')
    result = subprocess.run(['apt-cache', 'policy', 'neovim'], capture_output=True, text=True, check=True)
    match = re.search(r'^\s*Candidate:\s*(\S+)', result.stdout, re.M)
    candidate = version(match[1].split(':')[-1]) if match else None
    if candidate is None:
        if args.dry_run:
            print('Cannot confirm Neovim >= 0.10.4 from the cached apt index; refresh it before installing.', file=sys.stderr)
            return
        raise ValueError('Cannot confirm a compatible Neovim apt candidate; refresh the apt index first')
    if candidate < MINIMUM:
        raise ValueError(f'Neovim apt candidate {match[1]} is older than required 0.10.4')
    # Caller includes Neovim in the single install transaction, even if an old version is installed.
    print('neovim')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
