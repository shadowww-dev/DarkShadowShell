# shellcheck shell=bash
# The file helpers of install.sh: put / bk_one / copy_tree and the rule that your own QML edits survive an
# update untouched (the new version lands as FILE.rice-update). Sourced by install.sh.
# ---- your own edits survive updates (V4.32) ----
# The installer remembers what it wrote (~/.config/rice/installed.sums). A Quickshell file (.qml, .js) you changed
# since then is kept as it is on an update: the new version lands next to it as FILE.rice-update and the summary
# lists it. Before there was a list, the version the repo had before this update (git) tells if it was changed.
SUMS="$HOME/.config/rice/installed.sums"
# one line per file: appending on every update made this grow without end (and every check below slower)
[ -f "$SUMS" ] && awk 'NF >= 2 { h = $1; sub(/^[^ ]+  */, ""); s[$0] = h } END { for (k in s) print s[k] "  " k }' "$SUMS" >"$SUMS.tmp" && mv "$SUMS.tmp" "$SUMS"
KEPTF="$HOME/.cache/rice/kept-edits"
PREV_REV=""
sum_of() { sha256sum 2>/dev/null | cut -c1-64; }
rec_sum() { # rec_sum DST: what is in DST now is ours
  [ "$DRY_RUN" = 1 ] && return 0
  case "$1" in "$HOME"/.config/quickshell/*.qml|"$HOME"/.config/quickshell/*.js) ;; *) return 0 ;; esac
  mkdir -p "$(dirname "$SUMS")"
  printf '%s  %s\n' "$(sum_of <"$1")" "${1#"$HOME"/}" >>"$SUMS"
}
user_edited() { # user_edited SRC DST: true when you changed DST after the installer wrote it
  local src="$1" dst="$2" rel cur rec old
  [ "${RICE_OVERWRITE:-0}" = 1 ] && return 1
  case "$dst" in "$HOME"/.config/quickshell/*.qml|"$HOME"/.config/quickshell/*.js) ;; *) return 1 ;; esac
  rel="${dst#"$HOME"/}"
  cur="$(sum_of <"$dst")"
  rec="$(grep -F "  $rel" "$SUMS" 2>/dev/null | awk -v r="$rel" '$2 == r { s = $1 } END { print s }')"
  if [ -n "$rec" ]; then [ "$cur" != "$rec" ]; return; fi
  [ -n "$PREV_REV" ] || return 1
  git -C "$ROOT" cat-file -e "$PREV_REV:${src#"$ROOT"/}" 2>/dev/null || return 1      # not in that version
  old="$(git -C "$ROOT" show "$PREV_REV:${src#"$ROOT"/}" 2>/dev/null | sed -e "s|@HOME@|$HOME|g" -e "s|@USER@|$USER|g" | sum_of)"
  [ -n "$old" ] && [ "$cur" != "$old" ]
}
keep_edit() { # keep_edit SRC DST: your file stays, the new one goes next to it
  put "$1" "$2.rice-update"
  mkdir -p "$(dirname "$KEPTF")"; printf '%s\n' "${2#"$HOME"/}" >>"$KEPTF"
}

# put SRC DST: copy one file, fill in @HOME@/@USER@, back up what it replaces
put() {
  local src="$1" dst="$2" rel
  [ "$DRY_RUN" = 1 ] && return 0
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    rel="${dst#"$HOME"/}"
    mkdir -p "$BK/$(dirname "$rel")"
    cp -aL "$dst" "$BK/$rel" 2>/dev/null || warn "could not back up ~/$rel (it is replaced anyway)"
    [ -L "$dst" ] && rm -f "$dst"
  fi
  mkdir -p "$(dirname "$dst")"
  if grep -qI . "$src" 2>/dev/null; then
    sed -e "s|@HOME@|$HOME|g" -e "s|@USER@|$USER|g" "$src" >"$dst"
  else
    cp -f "$src" "$dst"
  fi
  [ -x "$src" ] && chmod +x "$dst"
  return 0
}
# V6.80: a file the installer changes in place (not replaced with a new one: the GTK settings, btop's config, lines
# added to hyprland.lua, the fixes of fixup.py) gets a copy in this run's backup first, like every replaced file.
# Before, only replaced files were saved, so "every file it changes is backed up" was not true for these
bk_one() { # bk_one FILE
  local f="$1" rel
  [ "$DRY_RUN" = 1 ] && return 0
  [ -f "$f" ] || return 0
  case "$f" in "$HOME"/*) ;; *) return 0 ;; esac
  rel="${f#"$HOME"/}"
  [ -e "$BK/$rel" ] && return 0
  mkdir -p "$BK/$(dirname "$rel")"
  cp -aL "$f" "$BK/$rel" 2>/dev/null || warn "could not back up ~/$rel"
}
copy_tree() { # copy_tree SRC_DIR DST_DIR
  local src="$1" dst="$2" f rel
  local -a new_files=() kept_files=()
  [ -d "$src" ] || return 0
  # files that are new on this computer go first (a changed file may need them, and Quickshell reloads as soon as
  # something changes), then the changed ones, and shell.qml goes last
  while IFS= read -r -d '' f; do
    rel="${f#"$src"/}"
    if [ -e "$dst/$rel" ] || [ -L "$dst/$rel" ]; then kept_files+=("$f"); else new_files+=("$f"); fi
  done < <(find -L "$src" -type f ! -name '*.bak*' ! -name '.gitkeep' ! -name shell.qml -print0)
  for f in "${new_files[@]}"; do put "$f" "$dst/${f#"$src"/}"; rec_sum "$dst/${f#"$src"/}"; done
  # the changed ones are written next to their old selves first and then swapped in all at once, so a running
  # Quickshell never reloads with half of the new files (a new Bar.qml with an old DynIsland.qml); files that
  # did not change are not touched at all
  local d rel2
  local -a staged=()
  for f in "${kept_files[@]}"; do
    d="$dst/${f#"$src"/}"
    if [ "$DRY_RUN" = 1 ]; then continue; fi
    put "$f" "$d.rice-new"
    if cmp -s "$d.rice-new" "$d"; then rm -f "$d.rice-new" "$d.rice-update"; rec_sum "$d"; continue; fi
    if user_edited "$f" "$d"; then rm -f "$d.rice-new"; keep_edit "$f" "$d"; continue; fi
    rel2="${d#"$HOME"/}"
    mkdir -p "$BK/$(dirname "$rel2")"
    cp -aL "$d" "$BK/$rel2" 2>/dev/null || warn "could not back up ~/$rel2 (it is replaced anyway)"
    [ -L "$d" ] && rm -f "$d"
    staged+=("$d")
  done
  for d in "${staged[@]}"; do mv -f "$d.rice-new" "$d"; rm -f "$d.rice-update"; rec_sum "$d"; done
  # shell.qml last, swapped in whole as well (Quickshell must never read it half written)
  if [ -f "$src/shell.qml" ] && [ "$DRY_RUN" != 1 ]; then
    d="$dst/shell.qml"
    if [ -e "$d" ]; then
      put "$src/shell.qml" "$d.rice-new"
      if cmp -s "$d.rice-new" "$d"; then rm -f "$d.rice-new"; rec_sum "$d"
      elif user_edited "$src/shell.qml" "$d"; then rm -f "$d.rice-new"; keep_edit "$src/shell.qml" "$d"
      else
        rel2="${d#"$HOME"/}"; mkdir -p "$BK/$(dirname "$rel2")"; cp -aL "$d" "$BK/$rel2" 2>/dev/null || warn "could not back up ~/$rel2 (it is replaced anyway)"
        [ -L "$d" ] && rm -f "$d"
        mv -f "$d.rice-new" "$d"; rec_sum "$d"
      fi
    else
      put "$src/shell.qml" "$d"; rec_sum "$d"
    fi
  fi
  return 0
}
