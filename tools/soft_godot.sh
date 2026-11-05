#!/usr/bin/env bash
# Godot with a window but no GPU: Vulkan on the CPU (lavapipe) under Xvfb. For screenshot
# tools, so they never compete with ComfyUI for VRAM.
#   tools/soft_godot.sh -s res://tools/shot.gd -- out.png
set -euo pipefail
export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/lvp_icd.x86_64.json
exec xvfb-run -a -s "-screen 0 1280x720x24" godot --rendering-driver vulkan "$@"
