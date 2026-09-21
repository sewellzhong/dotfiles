#!/usr/bin/env python3
"""Reject unsafe existing plugin worktrees before lazy can repair or replace them."""
import os
import json
from pathlib import Path
import subprocess
import sys
from nvim_installed import specs, validate_lock, validate_plugin

try:
    root = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'nvim/lazy'
    config = Path(sys.argv[1])
    origins = specs(config)
    validate_lock(json.loads((config / "lazy-lock.json").read_text()), origins)
    for name, origin in origins.items():
        directory = root / name
        if os.path.lexists(directory):
            validate_plugin(directory, origin)
except (ValueError, OSError, subprocess.CalledProcessError) as error:
    sys.exit(str(error))
