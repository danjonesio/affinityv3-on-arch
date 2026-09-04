# Environment for the Affinity Wine prefix. Sourced by the scripts; don't run it.
AFFINITY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Per-machine overrides live in config.sh (copy config.example.sh). Defaults:
AFFINITY_DPI="${AFFINITY_DPI:-96}"          # 96 = 100 %, 120 = 125 %, 144 = 150 %
AFFINITY_WORKSPACE="${AFFINITY_WORKSPACE:-}" # Hyprland workspace for the main window ("" = don't move it)
AFFINITY_WINE="${AFFINITY_WINE:-ew}"        # ew = ElementalWarrior build (OpenCL works), system = distro Wine
[ -f "$AFFINITY_ROOT/config.sh" ] && source "$AFFINITY_ROOT/config.sh"

export WINEPREFIX="$AFFINITY_ROOT/prefix"
export WINEARCH=win64
export WINEDEBUG="${WINEDEBUG:-fixme-all}"

# Wine runtime. The ElementalWarrior build's opencl.dll exposes the real device capabilities, which
# Affinity needs before it will enable OpenCL acceleration; stock Wine hides extensions it can't proxy.
if [ "$AFFINITY_WINE" = "ew" ] && [ -x "$AFFINITY_ROOT/deps/wine-ew/bin/wine" ]; then
  export PATH="$AFFINITY_ROOT/deps/wine-ew/bin:$PATH"
fi

# WPF draws the UI chrome through D3D9; DXVK's d3d9 can't do WPF's partial presents, so the UI goes
# black after resizes (dxvk #2542). Reporting SM1 pushes WPF onto its software rasterizer for the
# chrome only - the canvas is D3D12 (vkd3d-proton) and unaffected. Same setting AffinityOnLinux uses.
# syncInterval/maxFrameLatency: the canvas swapchain otherwise runs FIFO with a 5-image queue
# (several frames of drag lag); the compositor handles tearing, the frame cap keeps it sane.
export DXVK_CONFIG="d3d9.deferSurfaceCreation = True; d3d9.shaderModel = 1; dxgi.syncInterval = 0; dxgi.maxFrameLatency = 1; d3d9.maxFrameLatency = 1"
export DXVK_ASYNC=0
export DXVK_FRAME_RATE="${DXVK_FRAME_RATE:-120}"
export DXVK_LOG_LEVEL="${DXVK_LOG_LEVEL:-info}"
export VKD3D_FRAME_RATE="${VKD3D_FRAME_RATE:-120}"
export VKD3D_SWAPCHAIN_LATENCY_FRAMES=1
export VKD3D_DISABLE_EXTENSIONS=VK_KHR_present_id   # known NVIDIA stall trigger
export VKD3D_FEATURE_LEVEL=12_1
export VKD3D_SHADER_MODEL=6_5

# Wine's native Wayland driver is not usable for this app yet (wrong geometry at non-96 DPI, and
# winewayland's clipboard code throws on newer wlr-data-control). Run through XWayland unless
# AFFINITY_WAYLAND=1 is set to retry it.
if [ "${AFFINITY_WAYLAND:-0}" = "1" ]; then
  unset DISPLAY
else
  export DISPLAY="${DISPLAY:-:0}"
  unset WAYLAND_DISPLAY
fi

AFFINITY_DIR="$WINEPREFIX/drive_c/Program Files/Affinity/Affinity"
# Launch through AffinityPluginLoader (WineFix plugin) rather than Affinity.exe directly.
AFFINITY_EXE="$AFFINITY_DIR/AffinityHook.exe"
