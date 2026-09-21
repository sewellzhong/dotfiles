#!/usr/bin/env bash
# Network preparation only; integration.sh itself permits file transport exclusively.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
seed=${1:?Usage: prepare-lazy.sh NEW_DIRECTORY}
[ ! -e "$seed" ] || { echo "Seed destination already exists: $seed" >&2; exit 1; }
pin=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["lazy.nvim"]["commit"])' "$ROOT/nvim/.config/nvim/lazy-lock.json")
git init -q "$seed"
git -C "$seed" remote add origin https://github.com/folke/lazy.nvim.git
git -C "$seed" fetch --depth=1 origin "$pin"
git -C "$seed" checkout -q -B main FETCH_HEAD
[ "$(git -C "$seed" rev-parse HEAD)" = "$pin" ]
git -C "$seed" fsck --full
printf 'Prepared verified lazy.nvim seed: %s\n' "$seed"
