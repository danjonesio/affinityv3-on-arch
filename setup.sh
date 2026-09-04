#!/usr/bin/env bash
# Set up Affinity 3 (by Canva) on Arch Linux under Wine. Idempotent: re-run after changing config.sh
# or after pulling a new version of these scripts; finished steps are skipped.
#
#   ./setup.sh                 full setup (packages, deps, prefix, Affinity, desktop entry)
#   ./setup.sh --hyprland      also append the window rules to ~/.config/hypr/hyprland.lua (Omarchy)
#   ./setup.sh --no-packages   skip the pacman/modprobe steps (already done, or not Arch)
#
# Requires: an Arch-based distro (pacman), a Vulkan-capable GPU, ~8 GB free disk.
set -euo pipefail
source "$(dirname "$0")/env.sh"
source "$AFFINITY_ROOT/lib.sh"

do_packages=1; do_hyprland=0
for a in "$@"; do
  case "$a" in
    --no-packages) do_packages=0 ;;
    --hyprland) do_hyprland=1 ;;
    -h|--help) sed -n 2,9p "$0"; exit 0 ;;
    *) die "unknown option $a" ;;
  esac
done

# ---- 1. packages -------------------------------------------------------------
if [ $do_packages = 1 ]; then
  command -v pacman >/dev/null || die "pacman not found - this script targets Arch; use --no-packages and install the equivalents yourself"
  pkgs=(wine winetricks wine-mono wine-gecko cabextract unzip libarchive curl jq
        vulkan-icd-loader lib32-vulkan-icd-loader lib32-gnutls lib32-libpulse lib32-alsa-lib)
  case "$(gpu_vendor)" in
    nvidia) pkgs+=(opencl-nvidia lib32-nvidia-utils) ;;
    amd)    pkgs+=(rocm-opencl-runtime lib32-vulkan-radeon) ;;
    intel)  pkgs+=(intel-compute-runtime lib32-vulkan-intel) ;;
    *)      warn "GPU vendor not detected; install your OpenCL runtime manually for hardware acceleration" ;;
  esac
  missing=(); for p in "${pkgs[@]}"; do pacman -Q "$p" >/dev/null 2>&1 || missing+=("$p"); done
  if [ ${#missing[@]} -gt 0 ]; then
    say "installing packages: ${missing[*]}"
    grep -q '^\[multilib\]' /etc/pacman.conf || die "enable the [multilib] repo in /etc/pacman.conf first"
    sudo pacman -S --needed --noconfirm "${missing[@]}"
  fi
  ok "packages present"
  # ntsync: Wine 10+ uses it automatically when /dev/ntsync exists; big responsiveness win for .NET apps.
  if [ ! -e /dev/ntsync ] && modinfo ntsync >/dev/null 2>&1; then
    say "enabling ntsync kernel module"
    sudo modprobe ntsync && echo ntsync | sudo tee /etc/modules-load.d/ntsync.conf >/dev/null
  fi
  [ -e /dev/ntsync ] && ok "ntsync available" || warn "no /dev/ntsync (kernel without ntsync?) - Wine will use its slower sync path"
fi
for t in wine winetricks cabextract bsdtar curl; do command -v $t >/dev/null || die "missing tool: $t"; done

# ---- 2. dependencies ----------------------------------------------------------
say "dependencies"
D="$AFFINITY_ROOT/deps"; mkdir -p "$D"
fetch "$EW_WINE_URL"     "$D/ElementalWarrior-wine-${EW_WINE_VERSION}.tar.xz"
fetch "$APL_URL"         "$D/affinitypluginloader-plus-winefix.tar.xz"
fetch "$WINTYPES_URL"    "$D/wintypes.dll"
fetch "$WINMETADATA_URL" "$D/WinMetadata.tar.xz"
if [ ! -x "$D/wine-ew/bin/wine" ]; then
  say "unpacking ElementalWarrior Wine"
  rm -rf "$D/wine-ew"; mkdir -p "$D/wine-ew"
  tar -xJf "$D/ElementalWarrior-wine-${EW_WINE_VERSION}.tar.xz" -C "$D/wine-ew" --strip-components=1
fi
ok "ElementalWarrior $("$D/wine-ew/bin/wine" --version 2>/dev/null | tail -1)"

msix=$(newest_msix)
if [ -z "$msix" ]; then
  msix="$AFFINITY_ROOT/Affinity x64.msix"
  fetch "$MSIX_URL" "$msix"
fi
bsdtar -tf "$msix" AppxManifest.xml >/dev/null 2>&1 || die "$msix is not an Affinity MSIX package"
ok "Affinity package $(msix_version "$msix") ($(basename "$msix"))"

# ---- 3. prefix (uses the system Wine + winetricks; the runtime choice only matters at launch) -----
say "Wine prefix at $WINEPREFIX"
stop_affinity                  # a running instance holds a wineserver of the other build
export PATH="/usr/bin:$PATH"   # winetricks with distro Wine
export WINETRICKS_DOWNLOADER=curl
if [ ! -f "$WINEPREFIX/system.reg" ]; then
  wineboot --init; wineserver -w
fi
# winetricks skips verbs already recorded in winetricks.log; dotnet48 takes several minutes the first time.
winetricks --unattended --force remove_mono >/dev/null 2>&1 || true
winetricks --unattended vcrun2022 dotnet48 corefonts tahoma win11 renderer=vulkan fontsmooth=rgb
# DXVK for D3D9/D3D11 (wined3d's Vulkan backend fails to compile Affinity's shaders -> pixelated/blank UI),
# vkd3d-proton for D3D12 (Affinity's canvas; Wine's built-in d3d12 ghosts stale GPU memory onto the page).
winetricks --unattended dxvk vkd3d
wineserver -w
# UI scale
wine reg add "HKCU\\Control Panel\\Desktop" /v LogPixels /t REG_DWORD /d "$AFFINITY_DPI" /f >/dev/null
wine reg add "HKCU\\Software\\Wine\\Fonts"  /v LogPixels /t REG_DWORD /d "$AFFINITY_DPI" /f >/dev/null
wineserver -w
ok "prefix ready (DPI $AFFINITY_DPI)"

# WinRT metadata so the .NET side can resolve Windows.* types
WM="$WINEPREFIX/drive_c/windows/system32/WinMetadata"
if [ ! -f "$WM/Windows.winmd" ]; then
  mkdir -p "$WM"; tar -xJf "$D/WinMetadata.tar.xz" -C "$WM" --strip-components=1
fi
ok "WinMetadata ($(ls "$WM" | wc -l) files)"

# ---- 4. Affinity payload ------------------------------------------------------
if [ "$(cat "$WINEPREFIX/.affinity-version" 2>/dev/null)" != "$(msix_version "$msix")" ] || [ ! -f "$AFFINITY_EXE" ]; then
  stop_affinity
  install_payload "$msix"
else
  ok "Affinity $(cat "$WINEPREFIX/.affinity-version") already installed"
fi

# ---- 5. desktop integration -------------------------------------------------
install_desktop_integration

# ---- 6. Hyprland (optional) --------------------------------------------------
HL="$HOME/.config/hypr/hyprland.lua"
if [ $do_hyprland = 1 ]; then
  [ -f "$HL" ] || die "$HL not found (this option targets Omarchy's Lua config)"
  if grep -q 'affinity\\\\.exe' "$HL"; then
    ok "Hyprland rules already present in $HL"
  else
    cp "$HL" "$HL.bak.$(date +%s)"
    { echo; sed "s/@WORKSPACE@/${AFFINITY_WORKSPACE:-5}/" "$AFFINITY_ROOT/hyprland-rules.lua" | { [ -n "$AFFINITY_WORKSPACE" ] && cat || grep -v 'workspace ='; }; } >> "$HL"
    hyprctl reload >/dev/null 2>&1 || true
    errs=$(hyprctl configerrors 2>/dev/null | tr -d '\n'); [ -z "$errs" ] && ok "Hyprland rules appended to $HL" || warn "hyprctl configerrors: $errs"
  fi
elif command -v hyprctl >/dev/null; then
  warn "Hyprland detected: run ./setup.sh --hyprland to add the window rules (opaque window, floating dialogs), or copy hyprland-rules.lua by hand"
fi

echo; ok "done - launch with ./affinity or from the app menu"
