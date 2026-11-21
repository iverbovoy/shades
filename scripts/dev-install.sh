#!/bin/bash
# Development loop: compile the shader, copy the working tree into the Omarchy
# plugin folder and restart the shell. The restart is needed because a hot
# reload re-creates a service from its previously compiled code, and Qt keeps
# compiled shaders for the life of the process.
set -euo pipefail

src="$(cd "$(dirname "$0")/.." && pwd)"
dest="$HOME/.config/omarchy/plugins/verbovoy.shades"

"$src/scripts/build-shader.sh"
mkdir -p "$dest"
rsync -a --delete --exclude .git --exclude tests --exclude docs --exclude scripts "$src/" "$dest/"
omarchy-shell shell rescanPlugins >/dev/null
omarchy plugin enable verbovoy.shades >/dev/null
omarchy restart shell >/dev/null 2>&1
