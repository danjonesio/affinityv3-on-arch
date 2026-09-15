# Shared helpers for setup.sh / update.sh / the launcher. Source after env.sh.
[ -n "${_AFFINITY_LIB_LOADED:-}" ] && return 0
_AFFINITY_LIB_LOADED=1

# ---- upstream sources -------------------------------------------------------
MSIX_URL="https://downloads.affinity.studio/Affinity%20x64.msix"
EW_WINE_VERSION="11.12"
EW_WINE_URL="https://github.com/ryzendew/Affinity-Wine-Builder/releases/download/${EW_WINE_VERSION}/ElementalWarrior-wine-${EW_WINE_VERSION}.tar.xz"
APL_URL="https://github.com/noahc3/AffinityPluginLoader/releases/latest/download/affinitypluginloader-plus-winefix.tar.xz"
WINTYPES_URL="https://github.com/ElementalWarrior/wine-wintypes.dll-for-affinity/raw/refs/heads/master/wintypes_shim.dll.so"
WINMETADATA_URL="https://github.com/ryzendew/AffinityOnLinux/releases/download/10.4-Wine-Affinity/WinMetadata.tar.xz"
WINMD_URL="https://raw.githubusercontent.com/microsoft/windows-rs/master/crates/libs/default/Windows.winmd"

# ---- output -----------------------------------------------------------------
say()  { printf '\033[1;34m==\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m ✗\033[0m %s\n' "$*" >&2; exit 1; }

# fetch URL DEST  - download unless DEST exists and is non-empty
fetch() {
  local url=$1 dest=$2
  if [ -s "$dest" ]; then ok "have $(basename "$dest")"; return 0; fi
  say "downloading $(basename "$dest")"
  mkdir -p "$(dirname "$dest")"
  curl -L --fail --retry 3 --progress-bar -o "$dest.part" "$url" && mv "$dest.part" "$dest"
}

msix_version() { bsdtar -xOf "$1" AppxManifest.xml | grep -oE 'Version="[0-9.]+"' | head -1 | cut -d'"' -f2; }
newest_msix()  { ls -t "$AFFINITY_ROOT"/*.msix 2>/dev/null | head -1 || true; }

# resolve_display - turn AFFINITY_DPI=auto / DXVK_FRAME_RATE=auto into numbers
# from the Hyprland monitor Affinity will actually appear on. Wine under Omarchy
# is XWayland with force_zero_scaling, so LogPixels must be 96 * compositor scale
# or the UI is tiny on a 2x laptop panel and huge on a 1x ultrawide.
#
# The scale alone is not enough: a 2880x1800 panel at 2x is only 1440x900 logical,
# and at 192 DPI Affinity's New Document dialog (about 1450x910 Wine px at 96 DPI
# once it is scaled) is bigger than the whole screen. Hyprland then centres it over
# the bar and WPF, finding no room to anchor its combo-box popups, drops them in
# the middle of the screen. So auto DPI is also capped so that dialog fits in the
# monitor's usable area (minus reserved bar space), rounded down to a Wine step.
AFFINITY_MIN_DIALOG_W=1472   # New Document dialog + margin, in 96-DPI pixels
AFFINITY_MIN_DIALOG_H=928
resolve_display() {
  local scale hz mon usable_w usable_h
  if [ "${AFFINITY_DPI}" != "auto" ] && [ "${DXVK_FRAME_RATE}" != "auto" ] && [ "${VKD3D_FRAME_RATE}" != "auto" ]; then
    export DXVK_FRAME_RATE VKD3D_FRAME_RATE
    return 0
  fi
  if ! command -v hyprctl >/dev/null || ! command -v python3 >/dev/null; then
    [ "$AFFINITY_DPI" = "auto" ] && AFFINITY_DPI=96
    [ "$DXVK_FRAME_RATE" = "auto" ] && DXVK_FRAME_RATE=60
    [ "$VKD3D_FRAME_RATE" = "auto" ] && VKD3D_FRAME_RATE=60
    export DXVK_FRAME_RATE VKD3D_FRAME_RATE
    return 0
  fi
  read -r scale hz mon usable_w usable_h < <(AFFINITY_WORKSPACE="${AFFINITY_WORKSPACE:-}" python3 - <<'PY' || true
import json, os, subprocess, sys

def load(cmd):
    try:
        return json.loads(subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL))
    except Exception:
        return None

mons = load(["hyprctl", "monitors", "-j"]) or []
if not mons:
    sys.exit(1)
by_name = {m.get("name"): m for m in mons}
chosen = None
ws = os.environ.get("AFFINITY_WORKSPACE") or ""
if ws:
    for w in (load(["hyprctl", "workspaces", "-j"]) or []):
        if str(w.get("id")) == str(ws) or str(w.get("name")) == str(ws):
            chosen = by_name.get(w.get("monitor"))
            break
if chosen is None:
    chosen = next((m for m in mons if m.get("focused")), None)
if chosen is None:
    chosen = max(mons, key=lambda m: (float(m.get("scale") or 1), int(m.get("width") or 0) * int(m.get("height") or 0)))
scale = float(chosen.get("scale") or 1)
hz = float(chosen.get("refreshRate") or 60)
# reserved = [left, top, right, bottom] in logical px; usable area in physical px
res = chosen.get("reserved") or [0, 0, 0, 0]
w = int(chosen.get("width") or 0); h = int(chosen.get("height") or 0)
if int(chosen.get("transform") or 0) % 2 == 1:
    w, h = h, w
usable_w = max(0, w - int((res[0] + res[2]) * scale))
usable_h = max(0, h - int((res[1] + res[3]) * scale))
print(f"{scale:.4f} {hz:.3f} {chosen.get('name') or '?'} {usable_w} {usable_h}")
PY
  )
  if [ -z "${scale:-}" ]; then
    scale=1
    hz=60
    mon="?"
    usable_w=0
    usable_h=0
  fi
  if [ "$AFFINITY_DPI" = "auto" ]; then
    AFFINITY_DPI=$(python3 - "$scale" "${usable_w:-0}" "${usable_h:-0}" "$AFFINITY_MIN_DIALOG_W" "$AFFINITY_MIN_DIALOG_H" <<'PY'
import sys
scale, uw, uh, dw, dh = (float(a) for a in sys.argv[1:])
want = 96 * scale
if uw > 0 and uh > 0:
    want = min(want, 96 * uw / dw, 96 * uh / dh)
steps = [96, 120, 144, 168, 192, 216, 240, 264, 288]
print(max([d for d in steps if d <= want] or [96]))
PY
    )
  fi
  local hz_i
  hz_i=$(python3 -c "print(max(30, min(240, int(round(float('$hz'))))))")
  [ "$DXVK_FRAME_RATE" = "auto" ] && DXVK_FRAME_RATE=$hz_i
  [ "$VKD3D_FRAME_RATE" = "auto" ] && VKD3D_FRAME_RATE=$hz_i
  export DXVK_FRAME_RATE VKD3D_FRAME_RATE
  ok "display $mon  scale ${scale}x usable ${usable_w:-?}x${usable_h:-?} → DPI $AFFINITY_DPI @ ${DXVK_FRAME_RATE} Hz"
}

# apply_wine_dpi - write LogPixels if it changed. Wine reads this at process start.
apply_wine_dpi() {
  local dpi="${AFFINITY_DPI:-}" stamp="$WINEPREFIX/.affinity-dpi"
  [[ "$dpi" =~ ^[0-9]+$ ]] || return 0
  [ -d "$WINEPREFIX" ] || return 0
  if [ "$(cat "$stamp" 2>/dev/null)" = "$dpi" ]; then
    return 0
  fi
  if pgrep -f '[A]ffinity\.exe' >/dev/null; then
    say "DPI $dpi: stopping running Affinity so the new scale applies"
    wineserver -k || true
    wineserver -w || true
    sleep 1
  fi
  say "setting Wine DPI to $dpi"
  wine reg add "HKCU\\Control Panel\\Desktop" /v LogPixels /t REG_DWORD /d "$dpi" /f >/dev/null
  wine reg add "HKCU\\Software\\Wine\\Fonts"  /v LogPixels /t REG_DWORD /d "$dpi" /f >/dev/null
  echo "$dpi" > "$stamp"
  wineserver -w || true
  ok "Wine DPI $dpi"
}

# gpu_vendor -> nvidia | amd | intel | unknown
gpu_vendor() {
  local v; v=$(lspci -nn 2>/dev/null | grep -iE 'vga|3d|display' | head -1)
  case "$v" in
    *NVIDIA*|*10de:*) echo nvidia ;;
    *AMD*|*ATI*|*1002:*) echo amd ;;
    *Intel*|*8086:*) echo intel ;;
    *) echo unknown ;;
  esac
}

stop_affinity() {
  if pgrep -f '[A]ffinity\.exe' >/dev/null; then
    say "stopping Affinity"; wineserver -k || true; wineserver -w || true; sleep 1
    if pgrep -f '[A]ffinity\.exe' >/dev/null; then die "Affinity is still running; close it and retry"; fi
  fi
  return 0
}

# install_payload MSIX  - extract App/ into a fresh dir, apply shim + APL/WineFix, swap in, keep .prev
install_payload() {
  local msix=$1 new="$AFFINITY_DIR.new" prev="$AFFINITY_DIR.prev"
  say "extracting Affinity payload"
  rm -rf "$new"; mkdir -p "$new"
  bsdtar -xf "$msix" -C "$new" --strip-components=1 'App/*'
  [ -f "$new/Affinity.exe" ] || die "extraction failed (no Affinity.exe)"
  cp -f "$AFFINITY_ROOT/deps/wintypes.dll" "$new/wintypes.dll"
  tar -xJf "$AFFINITY_ROOT/deps/affinitypluginloader-plus-winefix.tar.xz" -C "$new"
  [ -f "$new/AffinityHook.exe" ] || die "AffinityPluginLoader extraction failed"
  if [ -d "$AFFINITY_DIR/apl/config" ]; then mkdir -p "$new/apl"; cp -a "$AFFINITY_DIR/apl/config" "$new/apl/"; fi
  mkdir -p "$AFFINITY_ROOT/icon"
  bsdtar -xf "$msix" -C "$AFFINITY_ROOT/icon" --strip-components=1 'Package/*' 2>/dev/null || true
  rm -rf "$prev"
  [ -d "$AFFINITY_DIR" ] && mv "$AFFINITY_DIR" "$prev"
  mv "$new" "$AFFINITY_DIR"
  msix_version "$msix" > "$WINEPREFIX/.affinity-version"
  ok "Affinity $(cat "$WINEPREFIX/.affinity-version") installed"
}

# install_desktop_integration - .desktop, MIME type, icons, default handler (all under ~/.local)
install_desktop_integration() {
  local apps="$HOME/.local/share/applications" mime="$HOME/.local/share/mime" icons="$HOME/.local/share/icons/hicolor"
  mkdir -p "$apps" "$mime/packages" "$icons/256x256/mimetypes" "$icons/48x48/mimetypes" "$icons/256x256/apps"
  cp -f "$AFFINITY_ROOT/icon/AppLogo.targetsize-256_altform-unplated.png" "$icons/256x256/apps/affinity.png"
  cp -f "$AFFINITY_ROOT/icon/FileTypeLogo.targetsize-256.png" "$icons/256x256/mimetypes/application-x-affinity.png"
  cp -f "$AFFINITY_ROOT/icon/FileTypeLogo.targetsize-48.png"  "$icons/48x48/mimetypes/application-x-affinity.png"
  sed "s|@ROOT@|$AFFINITY_ROOT|g" "$AFFINITY_ROOT/affinity.desktop.in" > "$apps/affinity.desktop"
  cp -f "$AFFINITY_ROOT/affinity-mime.xml" "$mime/packages/affinity.xml"
  update-mime-database "$mime" >/dev/null 2>&1 || true
  update-desktop-database "$apps" >/dev/null 2>&1 || true
  gtk-update-icon-cache -q "$icons" 2>/dev/null || true
  xdg-mime default affinity.desktop application/x-affinity 2>/dev/null || true
  ok "app-menu entry, file associations and icons installed"
}
