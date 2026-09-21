#!/usr/bin/env python3
"""Validate dependency lock syntax and the shared manager pin."""
import json
from pathlib import Path
import sys
from dependencies import read_lock

try:
    entries = read_lock(Path(sys.argv[1]))
    if len(sys.argv) > 2:
        nvim = json.loads(Path(sys.argv[2]).read_text())
        if nvim['lazy.nvim']['commit'] != entries['github.com/folke/lazy.nvim']:
            raise ValueError('lazy.nvim commits differ between dependency locks')
except (ValueError, OSError, KeyError) as error:
    sys.exit(f'Invalid dependency lock: {error}')
