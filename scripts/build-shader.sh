#!/bin/bash
# Compile the wall shader. The .qsb is committed so that installing the plugin
# with `omarchy plugin add` needs no build step; run this after editing wall.frag.
set -euo pipefail

cd "$(dirname "$0")/.."
/usr/lib/qt6/bin/qsb --qt6 -o shaders/wall.frag.qsb shaders/wall.frag
