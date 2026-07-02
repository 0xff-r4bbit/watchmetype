#!/usr/bin/env bash
#
# sign-update.sh — sign a Watch Me Type release with the Sparkle EdDSA key.
#
# The signing key was moved OUT of Google Drive (best practice: never keep a
# private signing key in cloud storage or inside the git repo). It now lives at:
#
#     ~/.config/sparkle/watch-me-type/sparkle_ed25519_private_key
#
# This script finds Sparkle's `sign_update` tool (bundled as a SwiftPM artifact
# under Xcode's DerivedData — its path contains a per-checkout hash that changes,
# so we locate the newest one rather than hardcode it), signs the file you pass,
# and prints the `sparkle:edSignature=... length=...` attributes to paste into
# docs/appcast.xml.
#
# Usage:
#     scripts/sign-update.sh <path-to-update>            # sign a .dmg / .zip / .delta / .pkg
#     scripts/sign-update.sh --verify <sig> <path>       # verify an existing signature
#
# Environment overrides:
#     SPARKLE_KEY   — path to the private key file (default: the path above)
#     SIGN_UPDATE   — path to the sign_update binary (default: auto-located)
#
set -euo pipefail

KEY="${SPARKLE_KEY:-$HOME/.config/sparkle/watch-me-type/sparkle_ed25519_private_key}"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# --- locate sign_update -------------------------------------------------------
# Sorted by mtime via `ls -t` (portable across BSD/GNU; avoids `stat` format
# flags, which differ between the two).
find_sign_update() {
  # 1. explicit override
  if [[ -n "${SIGN_UPDATE:-}" ]]; then
    [[ -x "$SIGN_UPDATE" ]] || die "SIGN_UPDATE is set but not executable: $SIGN_UPDATE"
    printf '%s\n' "$SIGN_UPDATE"; return
  fi
  # 2. on PATH (e.g. a Homebrew install)
  if command -v sign_update >/dev/null 2>&1; then command -v sign_update; return; fi
  # 3. newest Sparkle artifact in DerivedData — prefer this app's, then any app's.
  #    (exclude the legacy old_dsa_scripts variant, which is DSA not EdDSA)
  local dd="$HOME/Library/Developer/Xcode/DerivedData" pattern list found
  for pattern in '*Watch_Me_Type-*sparkle/Sparkle/bin/sign_update' '*sparkle/Sparkle/bin/sign_update'; do
    list=$(find "$dd" -type f -path "$pattern" 2>/dev/null | grep -v old_dsa_scripts || true)
    [[ -n "$list" ]] || continue
    found=$(printf '%s\n' "$list" | tr '\n' '\0' | xargs -0 ls -t 2>/dev/null | head -1)
    [[ -n "$found" ]] && { printf '%s\n' "$found"; return; }
  done
  die "could not find Sparkle's sign_update. Build the app in Xcode once (so SwiftPM
       resolves the Sparkle artifact), or set SIGN_UPDATE=/path/to/sign_update."
}

# --- args ---------------------------------------------------------------------
[[ $# -ge 1 ]] || die "usage: $(basename "$0") <path-to-update>  |  --verify <sig> <path>"

[[ -f "$KEY" ]] || die "signing key not found: $KEY
       (set SPARKLE_KEY to its location, or copy it back from your secure store)"

SIGN_UPDATE=$(find_sign_update)

# --- verify mode --------------------------------------------------------------
if [[ "$1" == "--verify" ]]; then
  [[ $# -eq 3 ]] || die "usage: $(basename "$0") --verify <signature> <path-to-update>"
  sig="$2"; file="$3"
  [[ -f "$file" ]] || die "update file not found: $file"
  echo "sign_update: $SIGN_UPDATE"
  echo "verifying:   $file"
  # sign_update --verify is SILENT on success (exit 0) and errors on failure.
  if "$SIGN_UPDATE" --verify "$file" "$sig" --ed-key-file "$KEY"; then
    echo "OK  signature is valid"
    exit 0
  else
    die "signature is INVALID for $file"
  fi
fi

# --- sign mode ----------------------------------------------------------------
file="$1"
[[ -f "$file" ]] || die "update file not found: $file"

echo "sign_update: $SIGN_UPDATE"
echo "key:         $KEY"
echo "file:        $file"
echo
echo "Paste this into the <enclosure> for this version in docs/appcast.xml:"
echo "-----------------------------------------------------------------------"
"$SIGN_UPDATE" --ed-key-file "$KEY" "$file"
echo "-----------------------------------------------------------------------"
