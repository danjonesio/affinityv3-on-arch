#!/usr/bin/env bash
# Update (or roll back) the Affinity payload inside the Wine prefix.
#
#   ./update.sh --check              is there a newer MSIX on downloads.affinity.studio?
#   ./update.sh --download           fetch the current MSIX and install it if it's a new version
#   ./update.sh [path/to/file.msix]  install from a local MSIX (default: newest *.msix here)
#   ./update.sh --force ...          reinstall even if the version matches
#   ./update.sh --rollback           swap the previous payload back in
#
# Only "Program Files/Affinity/Affinity" is replaced; prefix, settings, Wine runtime and WineFix
# config are kept. One previous payload is retained as Affinity.prev for --rollback.
set -euo pipefail
source "$(dirname "$0")/env.sh"
source "$AFFINITY_ROOT/lib.sh"

VERSION_FILE="$WINEPREFIX/.affinity-version"
PREV_DIR="$AFFINITY_DIR.prev"
installed_version() { cat "$VERSION_FILE" 2>/dev/null || echo "unknown"; }
remote_info() { curl -sSI -L --max-time 30 "$MSIX_URL" | tr -d '\r' | awk 'tolower($1)=="content-length:"{l=$2} tolower($1)=="last-modified:"{$1="";m=substr($0,2)} END{print l"|"m}'; }

mode=install; force=0; msix=""
for a in "$@"; do
  case "$a" in
    --check) mode=check ;;
    --download) mode=download ;;
    --rollback) mode=rollback ;;
    --force) force=1 ;;
    -h|--help) sed -n 2,11p "$0"; exit 0 ;;
    *) msix="$a" ;;
  esac
done

if [ "$mode" = check ]; then
  local_msix=$(newest_msix)
  info=$(remote_info); rlen=${info%%|*}; rmod=${info#*|}
  echo "installed:     $(installed_version)"
  echo "remote MSIX:   $rlen bytes, modified $rmod"
  if [ -n "$local_msix" ]; then
    llen=$(stat -c %s "$local_msix")
    echo "local MSIX:    $llen bytes ($(basename "$local_msix"), v$(msix_version "$local_msix"))"
    [ "$llen" = "$rlen" ] && echo "=> no new build on the server" || echo "=> server has a different build; run ./update.sh --download"
  else
    echo "=> no local MSIX; run ./update.sh --download"
  fi
  exit 0
fi

if [ "$mode" = rollback ]; then
  [ -d "$PREV_DIR" ] || die "nothing to roll back to ($PREV_DIR missing)"
  stop_affinity
  tmp="$AFFINITY_DIR.new"; rm -rf "$tmp"
  mv "$AFFINITY_DIR" "$tmp"; mv "$PREV_DIR" "$AFFINITY_DIR"; mv "$tmp" "$PREV_DIR"
  ok "rolled back; the payload you replaced is now $PREV_DIR (version file may be stale)"
  exit 0
fi

if [ "$mode" = download ]; then
  msix="$AFFINITY_ROOT/Affinity x64.msix"
  info=$(remote_info); rlen=${info%%|*}
  if [ -f "$msix" ] && [ "$(stat -c %s "$msix")" = "$rlen" ] && [ $force = 0 ]; then
    ok "local MSIX already matches the server build ($rlen bytes)"
  else
    rm -f "$msix"; fetch "$MSIX_URL" "$msix"
  fi
fi

[ -n "$msix" ] || msix=$(newest_msix)
[ -f "$msix" ] || die "no MSIX given and none found in $AFFINITY_ROOT"
bsdtar -tf "$msix" AppxManifest.xml >/dev/null 2>&1 || die "$msix is not an Affinity MSIX"
newv=$(msix_version "$msix"); curv=$(installed_version)
echo "installed: $curv   package: $newv ($(basename "$msix"))"
if [ "$newv" = "$curv" ] && [ $force = 0 ]; then echo "already installed; use --force to reinstall"; exit 0; fi
[ -f "$AFFINITY_ROOT/deps/wintypes.dll" ] && [ -f "$AFFINITY_ROOT/deps/affinitypluginloader-plus-winefix.tar.xz" ] || die "deps missing - run ./setup.sh first"

stop_affinity
install_payload "$msix"
install_desktop_integration
ok "previous payload kept at $PREV_DIR (./update.sh --rollback to revert)"
