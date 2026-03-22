#!/usr/bin/env bash
# Copyright (c) 2026 Scott Bellware. All rights reserved.
#
# git-stage — interactively select changed files to stage and commit.
#
# Controls:
#   ↑ / ↓ / k / j   Navigate
#   Space            Toggle selection
#   d                Show diff of file under cursor
#   a                Select / deselect all
#   x                Remove untracked file under cursor (with confirmation)
#   u                Revert unstaged changes to file under cursor (with confirmation)
#   q / Ctrl-C       Quit (index left exactly as-is)
#
# Options:
#   -q               Suppress copyright display
#
# Already-staged files appear pre-checked.
# Unchecking a staged file will unstage it on confirm.

# NOTE: intentionally no 'set -e' — bash arithmetic (( expr )) exits non-zero
# when the result is 0, which -e would treat as a fatal error.
set -uo pipefail

# ── Colours & formatting ────────────────────────────────────────────────────
bold()    { printf '\033[1m%s\033[0m'     "$*"; }
dim()     { printf '\033[2m%s\033[0m'     "$*"; }
green()   { printf '\033[32m%s\033[0m'    "$*"; }
yellow()  { printf '\033[33m%s\033[0m'    "$*"; }
cyan()    { printf '\033[36m%s\033[0m'    "$*"; }
red()     { printf '\033[31m%s\033[0m'    "$*"; }
reverse() { printf '\033[7m%s\033[27m'    "$*"; }
rev_grn() { printf '\033[42;30m%s\033[0m' "$*"; }

# ── CLI flags ────────────────────────────────────────────────────────────────
case "${1:-}" in
  --version|-V|-v)
    echo "git-stage 1.0.0"
    echo "Copyright (c) 2026 Scott Bellware"
    exit 0 ;;
  --help|-h)
    echo "Usage: git-stage"
    echo ""
    echo "Interactively select changed files to stage and commit."
    echo ""
    echo "Controls:"
    echo "  ↑ / ↓ / k / j   Navigate"
    echo "  Space            Toggle selection"
    echo "  d                Show diff of file under cursor"
    echo "  x                Remove untracked file under cursor (with confirmation)"
    echo "  u                Revert unstaged changes to file under cursor (with confirmation)"
    echo "  a                Select / deselect all"
    echo "  Enter            Confirm — stage selected, unstage deselected, then commit"
    echo "  q / Ctrl-C       Quit (index left exactly as-is)"
    echo ""
    echo "Options:"
    echo "  -q               Suppress copyright display"
    echo ""
    echo "Copyright (c) 2026 Scott Bellware"
    exit 0 ;;
  -q) QUIET=1 ;;
  '') QUIET=0 ;;
  *)
    echo "Unknown option: ${1}" >&2
    echo "Try 'git-stage --help' for usage." >&2
    exit 1 ;;
esac


# ── Sanity checks ───────────────────────────────────────────────────────────
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  red "Error: not inside a git repository." >&2; echo; exit 1
fi

# ── Collect changed files ───────────────────────────────────────────────────
mapfile -t STATUS_LINES < <(git status --porcelain -u)

if [[ ${#STATUS_LINES[@]} -eq 0 ]]; then
  echo "$(green '✓') Nothing to stage — working tree is clean."; exit 0
fi

# Parallel arrays
declare -a XY PATHS WAS_STAGED SEL
for line in "${STATUS_LINES[@]}"; do
  xy="${line:0:2}"
  path="${line:3}"
  x="${xy:0:1}"
  XY+=("$xy")
  PATHS+=("$path")
  # Pre-check files that are already in the index
  if [[ "$x" != " " && "$x" != "?" ]]; then
    WAS_STAGED+=(1); SEL+=(1)
  else
    WAS_STAGED+=(0); SEL+=(0)
  fi
done

N=${#PATHS[@]}
cursor=0
scroll=0

# ── Collect diff stats (once, before the event loop) ────────────────────────
declare -a STATS
for (( i=0; i<N; i++ )); do
  xy="${XY[$i]}"
  path="${PATHS[$i]}"
  x="${xy:0:1}"
  stat=""
  if [[ "$xy" == "??" ]]; then
    # Untracked: count lines in the file as additions
    lines=$(wc -l < "$path" 2>/dev/null | tr -d ' ') || lines=0
    stat="$(printf '\033[32m+%s\033[0m' "$lines")"
  elif [[ "$x" != " " ]]; then
    # Staged: diff against HEAD
    raw=$(git diff --cached --numstat -- "$path" 2>/dev/null)
    added=$(awk '{print $1}' <<< "$raw")
    removed=$(awk '{print $2}' <<< "$raw")
    [[ -n "$added"   && "$added"   != "-" ]] && stat+="$(printf '\033[32m+%s\033[0m' "$added")"
    [[ -n "$removed" && "$removed" != "-" ]] && stat+=" $(printf '\033[31m-%s\033[0m' "$removed")"
  else
    # Unstaged
    raw=$(git diff --numstat -- "$path" 2>/dev/null)
    added=$(awk '{print $1}' <<< "$raw")
    removed=$(awk '{print $2}' <<< "$raw")
    [[ -n "$added"   && "$added"   != "-" ]] && stat+="$(printf '\033[32m+%s\033[0m' "$added")"
    [[ -n "$removed" && "$removed" != "-" ]] && stat+=" $(printf '\033[31m-%s\033[0m' "$removed")"
  fi
  STATS+=("$stat")
done

# ── Terminal setup ──────────────────────────────────────────────────────────

hide_cursor()  { tput civis 2>/dev/null || true; }
show_cursor()  { tput cnorm 2>/dev/null || true; }
clear_drawn()  {
  tput cup 0 0 2>/dev/null || true
  tput ed  2>/dev/null || true
}

OLD_STTY=$(stty -g)

restore() {
  show_cursor
  stty "$OLD_STTY" 2>/dev/null || true
}
trap 'restore; echo' EXIT
trap 'restore; echo; echo "$(dim Interrupted.)"; exit 130' INT

stty -echo -icanon min 1 time 0
hide_cursor

# ── Status label ────────────────────────────────────────────────────────────
status_label() {
  local xy="$1" x="${1:0:1}" y="${1:1:1}"
  # Untracked is a whole-file state — handle before the two-column logic
  if [[ "$xy" == "??" ]]; then
    cyan 'untracked'; return
  fi
  local parts=()
  case "$x" in
    A) parts+=("$(green 'added')")      ;;
    M) parts+=("$(green 'staged')")     ;;
    D) parts+=("$(green 'staged-del')") ;;
    R) parts+=("$(green 'renamed')")    ;;
    C) parts+=("$(green 'copied')")     ;;
  esac
  case "$y" in
    M) parts+=("$(yellow 'modified')") ;;
    D) parts+=("$(red    'deleted')")  ;;
  esac
  local IFS='+'; printf '%s' "${parts[*]}"
}

staged_hint() {
  local x="${1:0:1}"
  if [[ "$x" != " " && "$x" != "?" ]]; then
    printf '%s' "$(dim ' [staged — uncheck to unstage]')"
  fi
}

# ── sel_count helper ─────────────────────────────────────────────────────────
count_selected() {
  local c=0 i
  for (( i=0; i<N; i++ )); do
    [[ "${SEL[$i]}" == "1" ]] && c=$(( c + 1 ))
  done
  printf '%d' "$c"
}

# ── Draw ─────────────────────────────────────────────────────────────────────
draw() {
  clear_drawn

  local term_rows
  term_rows=$(tput lines 2>/dev/null || echo 24)
  local visible=$(( term_rows - 6 ))
  [[ $visible -lt 1 ]] && visible=1

  # scroll tracking
  [[ $cursor -lt $scroll ]] && scroll=$cursor
  [[ $cursor -ge $(( scroll + visible )) ]] && scroll=$(( cursor - visible + 1 ))

  local sel_count
  sel_count=$(count_selected)

  local out=""

  local branch last_commit
  branch=$(git branch --show-current 2>/dev/null || echo 'detached HEAD')
  last_commit=$(git log -1 --pretty=format:'%s' 2>/dev/null || echo 'no commits yet')

  out+="$(bold ' git-stage')  $(dim "— $branch · $N file(s) changed, $sel_count selected")"$'\n'
  out+="$(dim " previous commit: $last_commit")"$'\n'
  [[ "$QUIET" == "0" ]] && out+="$(dim ' Copyright (c) 2026 Scott Bellware')"$'\n'
  out+="$(dim ' ↑↓ navigate   Space toggle   d diff   x remove   u revert   a all   Enter confirm   q quit')"$'\n'
  out+="$(dim ' ────────────────────────────────────────────────────────────')"$'\n'

  local i
  for (( i=0; i<visible; i++ )); do
    local fi=$(( i + scroll ))
    [[ $fi -ge $N ]] && break

    local path="${PATHS[$fi]}"
    local xy="${XY[$fi]}"
    local check="[ ] "
    [[ "${SEL[$fi]}" == "1" ]] && check="[✓] "

    local lbl hint stat
    lbl="$(status_label "$xy")"
    hint="$(staged_hint "$xy")"
    stat="${STATS[$fi]}"
    local row="  ${check} ${path}  ${lbl}${hint}  ${stat}"

    if   [[ "${SEL[$fi]}" == "1" && $fi -eq $cursor ]]; then
      out+="$(rev_grn "$row")"$'\n'
    elif [[ $fi -eq $cursor ]]; then
      out+="$(reverse "$row")"$'\n'
    elif [[ "${SEL[$fi]}" == "1" ]]; then
      out+="$(green "$row")"$'\n'
    else
      out+="${row}"$'\n'
    fi
  done

  local remaining=$(( N - visible - scroll ))
  if [[ $remaining -gt 0 ]]; then
    out+="$(dim "  … $remaining more below")"$'\n'
  fi

  out+="$(dim ' ────────────────────────────────────────────────────────────')"$'\n'

  printf '%s' "$out"
}

# ── Event loop ────────────────────────────────────────────────────────────────
while true; do
  draw

  # Read directly in the main shell (no subshell) so stty raw mode is inherited
  key=""
  IFS= read -r -s -n1 key || true
  if [[ "$key" == $'\x1b' ]]; then
    seq=""
    IFS= read -r -s -n2 -t 0.1 seq || true
    key="${key}${seq}"
  fi

  case "$key" in
    $'\x1b[A'|k)
      [[ $cursor -gt 0 ]] && cursor=$(( cursor - 1 ))
      ;;
    $'\x1b[B'|j)
      [[ $cursor -lt $(( N - 1 )) ]] && cursor=$(( cursor + 1 ))
      ;;
    ' ')
      if [[ "${SEL[$cursor]}" == "1" ]]; then SEL[$cursor]=0
      else SEL[$cursor]=1; fi
      ;;
    a|A)
      sel_count=$(count_selected)
      if [[ $sel_count -eq $N ]]; then
        for (( i=0; i<N; i++ )); do SEL[$i]=0; done
      else
        for (( i=0; i<N; i++ )); do SEL[$i]=1; done
      fi
      ;;
    d|D)
      # Show diff for the file under the cursor, then restore raw mode
      stty "$OLD_STTY"
      show_cursor
      path="${PATHS[$cursor]}"
      xy="${XY[$cursor]}"
      x="${xy:0:1}"
      # Staged files: diff against HEAD; unstaged/untracked: diff worktree
      if [[ "$x" != " " && "$x" != "?" ]]; then
        git diff --color=always --word-diff --unified=5 --cached -- "$path" | less -R
      elif [[ "$xy" == "??" ]]; then
        less "$path"
      else
        git diff --color=always --word-diff --unified=5 -- "$path" | less -R
      fi
      tput clear
      stty -echo -icanon min 1 time 0
      hide_cursor
      ;;
    x|X)
      if [[ "${XY[$cursor]}" == "??" ]]; then
        path="${PATHS[$cursor]}"
        # Temporarily restore terminal for the confirmation prompt
        stty "$OLD_STTY"
        show_cursor
        clear_drawn
        printf "Remove $(red "$path")? [y/N] "
        IFS= read -r confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
          rm -rf -- "$path"
          # Remove from arrays
          PATHS=("${PATHS[@]:0:$cursor}" "${PATHS[@]:$(( cursor + 1 ))}")
          XY=("${XY[@]:0:$cursor}" "${XY[@]:$(( cursor + 1 ))}")
          WAS_STAGED=("${WAS_STAGED[@]:0:$cursor}" "${WAS_STAGED[@]:$(( cursor + 1 ))}")
          SEL=("${SEL[@]:0:$cursor}" "${SEL[@]:$(( cursor + 1 ))}")
          N=$(( N - 1 ))
          [[ $cursor -ge $N && $cursor -gt 0 ]] && cursor=$(( cursor - 1 ))
          if [[ $N -eq 0 ]]; then
            echo "$(green '✓') No more changed files."
            exit 0
          fi
        fi
        stty -echo -icanon min 1 time 0
        hide_cursor
      fi
      ;;
    u|U)
      xy="${XY[$cursor]}"
      # Only revert if the file has unstaged changes (index column is space, worktree column is M or D)
      if [[ "${xy:0:1}" == " " && "${xy:1:1}" =~ ^[MD]$ ]]; then
        path="${PATHS[$cursor]}"
        stty "$OLD_STTY"
        show_cursor
        clear_drawn
        printf "Revert $(yellow "$path")? This cannot be undone. [y/N] "
        IFS= read -r confirm
        if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
          git restore -- "$path"
          # Remove from arrays
          PATHS=("${PATHS[@]:0:$cursor}" "${PATHS[@]:$(( cursor + 1 ))}")
          XY=("${XY[@]:0:$cursor}" "${XY[@]:$(( cursor + 1 ))}")
          WAS_STAGED=("${WAS_STAGED[@]:0:$cursor}" "${WAS_STAGED[@]:$(( cursor + 1 ))}")
          SEL=("${SEL[@]:0:$cursor}" "${SEL[@]:$(( cursor + 1 ))}")
          N=$(( N - 1 ))
          [[ $cursor -ge $N && $cursor -gt 0 ]] && cursor=$(( cursor - 1 ))
          if [[ $N -eq 0 ]]; then
            echo "$(green '✓') No more changed files."
            exit 0
          fi
        fi
        stty -echo -icanon min 1 time 0
        hide_cursor
      fi
      ;;
    q|Q|$'\x1b'|$'\x03')
      clear_drawn
      echo "$(dim 'Quit — index left unchanged.')"
      exit 0
      ;;
    $'\n'|$'\r'|'')
      break
      ;;
  esac
done

# ── Apply staging changes ─────────────────────────────────────────────────────
clear_drawn

declare -a TO_STAGE=() UNSTAGE_NEW=() UNSTAGE_TRACKED=()
for (( i=0; i<N; i++ )); do
  if [[ "${SEL[$i]}" == "1" && "${WAS_STAGED[$i]}" == "0" ]]; then
    TO_STAGE+=("${PATHS[$i]}")
  elif [[ "${SEL[$i]}" == "0" && "${WAS_STAGED[$i]}" == "1" ]]; then
    # 'A' = newly added, no HEAD ref yet; must use rm --cached
    # M/D/R/C = tracked file with a HEAD ref; use restore --staged
    if [[ "${XY[$i]:0:1}" == "A" ]]; then
      UNSTAGE_NEW+=("${PATHS[$i]}")
    else
      UNSTAGE_TRACKED+=("${PATHS[$i]}")
    fi
  fi
done

if [[ $(( ${#UNSTAGE_NEW[@]} + ${#UNSTAGE_TRACKED[@]} )) -gt 0 ]]; then
  echo "$(bold 'Unstaging:')"
  for f in "${UNSTAGE_NEW[@]}"     "${UNSTAGE_TRACKED[@]}"; do echo "  $(red '−') $f"; done
  [[ ${#UNSTAGE_NEW[@]}     -gt 0 ]] && git rm --cached -q -- "${UNSTAGE_NEW[@]}"
  [[ ${#UNSTAGE_TRACKED[@]} -gt 0 ]] && git restore --staged -- "${UNSTAGE_TRACKED[@]}"
  echo
fi

if [[ ${#TO_STAGE[@]} -gt 0 ]]; then
  echo "$(bold 'Staging:')"
  for f in "${TO_STAGE[@]}"; do echo "  $(green '+') $f"; done
  git add -- "${TO_STAGE[@]}"
  echo
fi

# Determine what's staged now
declare -a NOW_STAGED=()
for (( i=0; i<N; i++ )); do
  [[ "${SEL[$i]}" == "1" ]] && NOW_STAGED+=("${PATHS[$i]}")
done

if [[ ${#NOW_STAGED[@]} -eq 0 ]]; then
  echo "$(yellow 'Nothing staged — aborting commit.')"
  exit 0
fi

if [[ ${#TO_STAGE[@]} -eq 0 && $(( ${#UNSTAGE_NEW[@]} + ${#UNSTAGE_TRACKED[@]} )) -eq 0 ]]; then
  echo "$(dim 'Staging unchanged.')"
  echo
fi

# ── Restore terminal before text input ───────────────────────────────────────
stty "$OLD_STTY"

# ── Commit message ────────────────────────────────────────────────────────────
printf "$(bold 'Commit message') $(dim '(blank to abort):')\n  › "
IFS= read -r commit_msg

if [[ -z "$commit_msg" ]]; then
  echo "$(yellow 'No message given — files are staged but not committed.')"
  exit 0
fi

# ── Commit ────────────────────────────────────────────────────────────────────
echo
if git commit -m "$commit_msg"; then
  echo
  echo "$(green '✓') Committed successfully."
else
  echo
  echo "$(red 'Commit failed — files remain staged.')"
  exit 1
fi
