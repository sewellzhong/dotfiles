#!/usr/bin/env python3
import subprocess
import sys
from nvim_installed import main

try:
    main()
except (ValueError, OSError, subprocess.CalledProcessError) as error:
    sys.exit(str(error))
