# Shared helpers for setup.sh / update.sh. Source after env.sh.

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
