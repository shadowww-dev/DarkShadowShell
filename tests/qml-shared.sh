#!/usr/bin/env bash
# Components that live in more than one app folder are copies: they must stay byte-identical, so a fix in one
# copy is not missing from the others (the same event falling back to the click sound, an older image loader).
# rice-desktop is the source; rice-lockscreen is filled from it at every lock (bin/rice-lock sync_shared).
set -Euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QS="$root/quickshell"
SHARED="Sfx SfxBank SfxTap Fonts Icons Blob"
# these differ on purpose: T depends on Settings' M3/Prefs, RoundImage too; MoonLogo and StarField are per app
n=0
ok() { n=$((n + 1)); printf 'ok %d - %s\n' "$n" "$1"; }
bad() { printf 'not ok %d - %s\n' "$n" "$1"; exit 1; }

for f in $SHARED; do
  src="$QS/rice-desktop/$f.qml"
  [ -f "$src" ] || bad "rice-desktop/$f.qml is missing"
  for app in "$QS"/rice-*/; do
    name="$(basename "$app")"
    [ "$name" = rice-desktop ] && continue
    dst="$app$f.qml"
    [ -f "$dst" ] || continue                 # not every app needs every component
    cmp -s "$src" "$dst" || bad "$name/$f.qml differs from rice-desktop/$f.qml (copies must match)"
  done
  ok "$f.qml is identical in every app that has it"
done
echo "# $n checks passed"
