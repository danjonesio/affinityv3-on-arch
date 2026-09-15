# Copy to config.sh and edit. Every value is optional. config.sh is gitignored so
# each machine keeps its own (laptop vs desktop vs ultrawide dock).

# UI scale. auto = 96 × Hyprland scale of the target monitor, capped so the New Document
# dialog fits the screen (this 2880x1800 laptop panel at 2x → 168, not 192).
# Pin 96 / 120 / 144 / 192 / 240 to override.
AFFINITY_DPI=auto

# Hyprland only: workspace the main window opens on. Leave empty to not move it.
# Auto DPI/Hz read this workspace's monitor — plug in an ultrawide, put workspace
# 5 on it, relaunch, done.
AFFINITY_WORKSPACE=5

# Wine runtime: "ew" (ElementalWarrior build, needed for OpenCL acceleration) or "system".
AFFINITY_WINE=ew

# Intel: OpenCL is off by default (NEO + D3D12 sharing hangs the splash on Lunar Lake).
# Set to 1 to try compute acceleration. NVIDIA leaves OpenCL enabled regardless.
# AFFINITY_OPENCL=1

# Frame cap for the canvas (Hz). auto = that monitor's refresh rate.
DXVK_FRAME_RATE=auto
VKD3D_FRAME_RATE=auto
