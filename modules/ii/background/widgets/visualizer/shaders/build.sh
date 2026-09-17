#!/usr/bin/env bash
# Compile the visualizer shaders to .qsb. Needs qsb from qt6-shadertools.
set -euo pipefail
cd "$(dirname "$0")"
QSB="${QSB:-$(command -v qsb || echo /usr/lib/qt6/bin/qsb)}"
for style in aurora ring dots mirror; do
    "$QSB" --qt6 -o "$style.frag.qsb" "$style.frag"
done
