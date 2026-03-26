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
#   s                Show repository status screen
#
# Options:
#   -q                    Quiet mode. Suppress the output of Git commands executed.
#   -C, --no-copyright    Suppress the copyright notice in the UI
#   -U, --unsafe-confirm  Confirm dangerous actions with Enter instead of 'y'
#   -A, --select-all      Start with all files pre-selected
#   --dry-run             Show what would be staged/committed without doing it
#   --version, -v         Show version and copyright
#   --help, -h            Show usage and controls
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

# ── Status screen ────────────────────────────────────────────────────────────
show_status() {
  local branch last_commit last_meta
  branch=$(git branch --show-current 2>/dev/null || echo 'detached HEAD')
  last_commit=$(git log -1 --pretty=format:'%s' 2>/dev/null || echo 'no commits yet')
  last_meta=$(git log -1 --pretty=format:'%an, %ad, %h' --date=format:'%a %b %d %H:%M:%S' 2>/dev/null || echo '')

  local out=""
  out+="$(bold 'git-stage') — $(green "$branch")"$'\n'
  if [[ -n "$last_meta" ]]; then
    out+="$(dim " previous commit: $last_commit [$last_meta]")"$'\n'
  else
    out+="$(dim " previous commit: $last_commit")"$'\n'
  fi

  # Collect files by category
  local staged=() unstaged=() untracked=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    local xy="${line:0:2}" path="${line:3}"
    local x="${xy:0:1}" y="${xy:1:1}"
    if [[ "$xy" == "??" ]]; then
      untracked+=("$path")
    elif [[ "$x" != " " && "$y" != " " && "$y" != "?" ]]; then
      staged+=("$xy $path")
      unstaged+=("$xy $path")
    elif [[ "$x" != " " ]]; then
      staged+=("$xy $path")
    else
      unstaged+=("$xy $path")
    fi
  done < <(git status --porcelain -u 2>/dev/null)

  local has_sections=0

  # Staged
  local sections_out=""

  if [[ ${#staged[@]} -gt 0 ]]; then
    has_sections=1
    sections_out+="$(bold ' Staged')"$'\n'
    for entry in "${staged[@]}"; do
      local xy="${entry:0:2}" path="${entry:3}"
      local raw added removed stat=""
      raw=$(git diff --cached --numstat -- "$path" 2>/dev/null)
      added=$(awk '{print $1}' <<< "$raw")
      removed=$(awk '{print $2}' <<< "$raw")
      [[ -n "$added"   && "$added"   != "-" ]] && stat+="$(printf '\033[32m+%s\033[0m' "$added")"
      [[ -n "$removed" && "$removed" != "-" ]] && stat+=" $(printf '\033[31m-%s\033[0m' "$removed")"
      sections_out+="$(green "   $xy $path")  $stat"$'\n'
    done
    sections_out+=$'\n'
  fi

  # Unstaged
  if [[ ${#unstaged[@]} -gt 0 ]]; then
    has_sections=1
    sections_out+="$(bold ' Unstaged')"$'\n'
    for entry in "${unstaged[@]}"; do
      local xy="${entry:0:2}" path="${entry:3}"
      local raw added removed stat=""
      raw=$(git diff --numstat -- "$path" 2>/dev/null)
      added=$(awk '{print $1}' <<< "$raw")
      removed=$(awk '{print $2}' <<< "$raw")
      [[ -n "$added"   && "$added"   != "-" ]] && stat+="$(printf '\033[32m+%s\033[0m' "$added")"
      [[ -n "$removed" && "$removed" != "-" ]] && stat+=" $(printf '\033[31m-%s\033[0m' "$removed")"
      sections_out+="$(yellow "   $xy $path")  $stat"$'\n'
    done
    sections_out+=$'\n'
  fi

  # Untracked
  if [[ ${#untracked[@]} -gt 0 ]]; then
    has_sections=1
    sections_out+="$(bold ' Untracked')"$'\n'
    for path in "${untracked[@]}"; do
      local lines
      lines=$(wc -l < "$path" 2>/dev/null | tr -d ' ') || lines=0
      sections_out+="$(cyan "   ?? $path")  $(printf '\033[32m+%s\033[0m' "$lines")"$'\n'
    done
    sections_out+=$'\n'
  fi

  # Stashes
  local stash_log
  stash_log=$(git stash list 2>/dev/null)
  if [[ -n "$stash_log" ]]; then
    has_sections=1
    sections_out+="$(bold ' Stashes')"$'\n'
    while IFS= read -r line; do
      sections_out+="$(dim "   $line")"$'\n'
    done <<< "$stash_log"
    sections_out+=$'\n'
  fi

  # Unpushed commits
  local upstream
  upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
  if [[ -n "$upstream" ]]; then
    local unpushed_log
    unpushed_log=$(git log '@{u}..HEAD' --pretty=format:'%h %s' 2>/dev/null)
    if [[ -n "$unpushed_log" ]]; then
      has_sections=1
      sections_out+="$(bold ' Unpushed')"$'\n'
      while IFS= read -r line; do
        sections_out+="$(dim "   $line")"$'\n'
      done <<< "$unpushed_log"
      sections_out+=$'\n'
    fi
  fi

  if [[ $has_sections -eq 1 ]]; then
    out+="$(dim ' ────────────────────────────────────────────────────────────')"$'\n'
    out+="$sections_out"
    out+="$(dim ' ────────────────────────────────────────────────────────────')"$'\n'
  fi
  printf '%s' "$out"
}

# ── CLI flags ────────────────────────────────────────────────────────────────
QUIET=0
DRY_RUN=0
SHOW_COPYRIGHT=1
UNSAFE_CONFIRM=0
SELECT_ALL=0

# Honour environment variable
[[ -n "${GIT_STAGE_NO_COPYRIGHT:-}" ]] && SHOW_COPYRIGHT=0
[[ -n "${GIT_STAGE_UNSAFE_CONFIRM:-}" ]] && UNSAFE_CONFIRM=1
[[ -n "${GIT_STAGE_SELECT_ALL:-}" ]] && SELECT_ALL=1

case "${1:-}" in
  --version|-V|-v)
    echo "git-stage 1.0.0"
    echo "Copyright (c) 2026 Scott Bellware. All rights reserved."
    exit 0 ;;
  --help|-h)
    echo "Usage: git-stage [options]"
    echo ""
    echo "Interactively select changed files to stage and commit."
    echo ""
    echo "Controls:"
    echo "  ↑ / ↓ / k / j   Navigate"
    echo "  Space            Toggle selection"
    echo "  d                Show diff of file under cursor"
    echo "  x                Remove untracked file under cursor (with confirmation)"
    echo "  u                Revert unstaged changes to file under cursor (with confirmation)"
    echo "  s                Show repository status screen"
    echo "  m                Amend the last commit (stages selected files, edits message)"
    echo "  a                Select / deselect all"
    echo "  Enter            Confirm — stage selected, unstage deselected, then commit"
    echo "  q / Ctrl-C       Quit (index left exactly as-is)"
    echo ""
    echo "Options:"
    echo "  -q               Quiet mode. Suppress the output of Git commands executed."
    echo "  -C, --no-copyright  Suppress the copyright notice in the UI"
    echo "  -U, --unsafe-confirm  Confirm dangerous actions with Enter instead of 'y'"
    echo "  -A, --select-all  Start with all files pre-selected"
    echo "  --status, -s     Show repository status screen and exit"
    echo ""
    echo "Non-interactive (for scripting and testing):"
    echo "  --stage <file>   Stage a specific file"
    echo "  --unstage <file> Unstage a specific file"
    echo "  --commit <msg>   Commit what is currently staged"
    echo "  --amend <msg>    Amend the last commit with a new message"
    echo "  --revert <file>  Revert unstaged changes to a file"
    echo "  --delete <file>  Delete an untracked file"
    echo "  --push           Push current branch to origin"
    echo ""
    echo "Copyright (c) 2026 Scott Bellware. All rights reserved."
    exit 0 ;;
  --status|-s)
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
      echo "Error: not inside a git repository." >&2; exit 1
    fi
    show_status
    exit 0 ;;

  --dry-run)            DRY_RUN=1 ;;
  -q)                   QUIET=1 ;;
  -C|--no-copyright)    SHOW_COPYRIGHT=0 ;;
  -U|--unsafe-confirm)  UNSAFE_CONFIRM=1 ;;
  -A|--select-all)      SELECT_ALL=1 ;;

  # ── Non-interactive switches ────────────────────────────────────────────────
  --stage)
    [[ -z "${2:-}" ]] && { echo "Usage: git-stage --stage <file>" >&2; exit 1; }
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
      echo "Error: not inside a git repository." >&2; exit 1
    fi
    if [[ ! -e "$2" ]]; then
      echo "Error: file not found: $2" >&2; exit 1
    fi
    git add -- "$2"
    echo "Staged: $2"
    exit $? ;;

  --unstage)
    [[ -z "${2:-}" ]] && { echo "Usage: git-stage --unstage <file>" >&2; exit 1; }
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
      echo "Error: not inside a git repository." >&2; exit 1
    fi
    xy=$(git status --porcelain -- "$2" 2>/dev/null | head -1 | cut -c1)
    if [[ "$xy" == "A" ]]; then
      git rm --cached -q -- "$2"
    else
      git restore --staged -- "$2"
    fi
    echo "Unstaged: $2"
    exit $? ;;

  --commit)
    [[ -z "${2:-}" ]] && { echo "Usage: git-stage --commit <message>" >&2; exit 1; }
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
      echo "Error: not inside a git repository." >&2; exit 1
    fi
    git commit -m "$2"
    exit $? ;;

  --amend)
    [[ -z "${2:-}" ]] && { echo "Usage: git-stage --amend <message>" >&2; exit 1; }
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
      echo "Error: not inside a git repository." >&2; exit 1
    fi
    git commit --amend -m "$2"
    exit $? ;;

  --revert)
    [[ -z "${2:-}" ]] && { echo "Usage: git-stage --revert <file>" >&2; exit 1; }
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
      echo "Error: not inside a git repository." >&2; exit 1
    fi
    xy=$(git status --porcelain -- "$2" 2>/dev/null | head -1)
    y="${xy:1:1}"
    if [[ "$y" != "M" && "$y" != "D" ]]; then
      echo "Error: no unstaged changes to revert: $2" >&2; exit 1
    fi
    git restore -- "$2"
    echo "Reverted: $2"
    exit $? ;;

  --delete)
    [[ -z "${2:-}" ]] && { echo "Usage: git-stage --delete <file>" >&2; exit 1; }
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
      echo "Error: not inside a git repository." >&2; exit 1
    fi
    if [[ ! -e "$2" ]]; then
      echo "Error: file not found: $2" >&2; exit 1
    fi
    rm -rf -- "$2"
    echo "Deleted: $2"
    exit 0 ;;

  --push)
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
      echo "Error: not inside a git repository." >&2; exit 1
    fi
    branch=$(git branch --show-current 2>/dev/null || echo 'detached HEAD')
    git push --set-upstream origin "$branch"
    exit $? ;;

  '') ;;
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

# ── Terminal setup ──────────────────────────────────────────────────────────
hide_cursor()  { tput civis 2>/dev/null || true; }
show_cursor()  { tput cnorm 2>/dev/null || true; }
clear_drawn()  {
  tput cup 0 0 2>/dev/null || true
  tput ed  2>/dev/null || true
}

OLD_STTY=$(stty -g </dev/tty)

restore() {
  show_cursor
  stty "$OLD_STTY" </dev/tty 2>/dev/null || true
}
trap 'restore; echo' EXIT
trap 'restore; echo; echo "$(dim Interrupted.)"; exit 130' INT

# ── Check for pending push on clean working tree ─────────────────────────────
if [[ ${#STATUS_LINES[@]} -eq 0 ]]; then
  echo "$(green '✓') Nothing to stage — working tree is clean."
  prev_msg=$(git log -1 --pretty=format:'%s' 2>/dev/null || true)
  prev_meta=$(git log -1 --pretty=format:'%an, %ad, %h' --date=format:'%a %b %d %H:%M:%S' 2>/dev/null || true)
  [[ -n "$prev_msg" ]] && echo "$(dim "previous commit: $prev_msg [$prev_meta]")"

  # Check for unpushed commits
  upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
  if [[ -n "$upstream" ]]; then
    unpushed=$(git log '@{u}..HEAD' --oneline 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$unpushed" -gt 0 ]]; then
      branch=$(git branch --show-current 2>/dev/null || echo 'detached HEAD')
      cur_commit=$(git log -1 --pretty=format:'%s' 2>/dev/null || true)
      cur_meta=$(git log -1 --pretty=format:'%an, %ad, %h' --date=format:'%a %b %d %H:%M:%S' 2>/dev/null || true)

      stty -echo -icanon min 1 time 0 </dev/tty
      hide_cursor
      tput clear

      printf '%s\n' \
        "$(bold 'git-stage') — $(green "$branch") · $(dim "$unpushed unpushed commit(s)")" \
        "$(dim " current commit: $cur_commit [$cur_meta]")" \
        "$(dim ' p push   q quit')" \
        "$(dim ' ────────────────────────────────────────────────────────────')"

      while true; do
        key=""
        IFS= read -r -s -n1 key </dev/tty || true
        if [[ "$key" == $'\x1b' ]]; then
          seq=""
          IFS= read -r -s -n2 -t 0.1 seq </dev/tty || true
          key="${key}${seq}"
        fi
        case "$key" in
          p|P)
            stty "$OLD_STTY" </dev/tty
            show_cursor
            tput clear
            echo "$(bold "Pushing to origin:$branch...")"
            if git push --set-upstream origin "$branch"; then
              echo "$(green '✓') Pushed successfully."
              if [[ "$QUIET" == "0" ]]; then
                echo
                echo "$(dim "Commands run:")"
                echo "$(dim "  git push --set-upstream origin $branch")"
              fi
            else
              echo "$(red 'Push failed.')"
            fi
            break ;;
          q|Q|$'\x03'|$'\x1b')
            stty "$OLD_STTY" </dev/tty
            show_cursor
            tput clear
            break ;;
        esac
      done
      exit 0
    fi
  fi
  exit 0
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

# Pre-select all files if --select-all was given
if [[ "$SELECT_ALL" == "1" ]]; then
  for (( i=0; i<N; i++ )); do SEL[$i]=1; done
fi

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

  local branch last_commit last_meta
  branch=$(git branch --show-current 2>/dev/null || echo 'detached HEAD')
  last_commit=$(git log -1 --pretty=format:'%s' 2>/dev/null || echo 'no commits yet')
  last_meta=$(git log -1 --pretty=format:'%an, %ad, %h' --date=format:'%a %b %d %H:%M:%S' 2>/dev/null || echo '')

  out+="$(bold 'git-stage') — $(green "$branch") · $(dim "$N file(s) changed, $sel_count selected")"
  [[ "$DRY_RUN" == "1" ]] && out+="  $(yellow '[dry run]')"
  out+=$'\n'
  if [[ -n "$last_meta" ]]; then
    out+="$(dim " previous commit: $last_commit [$last_meta]")"$'\n'
  else
    out+="$(dim " previous commit: $last_commit")"$'\n'
  fi
  out+="$(dim " branch: $branch")"$'\n'
  [[ "$SHOW_COPYRIGHT" == "1" ]] && out+="$(dim ' Copyright (c) 2026 Scott Bellware. All rights reserved.')"$'\n'
  out+="$(dim ' ↑↓ navigate   Space toggle   d diff   s status   x remove   u revert   m amend   a all   Enter confirm   q quit')"$'\n'
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
stty -echo -icanon min 1 time 0 </dev/tty
hide_cursor
while true; do
  draw

  # Read directly in the main shell (no subshell) so stty raw mode is inherited
  key=""
  IFS= read -r -s -n1 key </dev/tty || true
  if [[ "$key" == $'\x1b' ]]; then
    seq=""
    IFS= read -r -s -n2 -t 0.1 seq </dev/tty || true
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
    s|S)
      stty "$OLD_STTY" </dev/tty
      show_cursor
      tput clear
      show_status
      printf "$(dim 'q / Esc — return')"
      while true; do
        key=""
        IFS= read -r -s -n1 key </dev/tty || true
        if [[ "$key" == $'\x1b' ]]; then
          seq=""
          IFS= read -r -s -n2 -t 0.1 seq </dev/tty || true
          key="${key}${seq}"
        fi
        [[ "$key" == q || "$key" == Q || "$key" == $'\x1b' || "$key" == $'\x03' ]] && break
      done
      tput clear
      stty -echo -icanon min 1 time 0 </dev/tty
      hide_cursor
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
      stty "$OLD_STTY" </dev/tty
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
      stty -echo -icanon min 1 time 0 </dev/tty
      hide_cursor
      ;;
    x|X)
      if [[ "${XY[$cursor]}" == "??" ]]; then
        path="${PATHS[$cursor]}"
        # Temporarily restore terminal for the confirmation prompt
        stty "$OLD_STTY" </dev/tty
        show_cursor
        clear_drawn
        if [[ "$UNSAFE_CONFIRM" == "1" ]]; then
          printf "Remove $(red "$path")? [Enter/Esc] "
          IFS= read -r -s -n1 confirm </dev/tty
          echo
          [[ "$confirm" == "" || "$confirm" == $'\r' || "$confirm" == $'\n' ]] && confirm="y" || confirm="n"
        else
          printf "Remove $(red "$path")? [y/N] "
          IFS= read -r confirm </dev/tty
        fi
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
        stty -echo -icanon min 1 time 0 </dev/tty
        hide_cursor
      fi
      ;;
    u|U)
      xy="${XY[$cursor]}"
      # Only revert if the file has unstaged changes (index column is space, worktree column is M or D)
      if [[ "${xy:0:1}" == " " && "${xy:1:1}" =~ ^[MD]$ ]]; then
        path="${PATHS[$cursor]}"
        stty "$OLD_STTY" </dev/tty
        show_cursor
        clear_drawn
        if [[ "$UNSAFE_CONFIRM" == "1" ]]; then
          printf "Revert $(yellow "$path")? This cannot be undone. [Enter/Esc] "
          IFS= read -r -s -n1 confirm </dev/tty
          echo
          [[ "$confirm" == "" || "$confirm" == $'\r' || "$confirm" == $'\n' ]] && confirm="y" || confirm="n"
        else
          printf "Revert $(yellow "$path")? This cannot be undone. [y/N] "
          IFS= read -r confirm </dev/tty
        fi
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
        stty -echo -icanon min 1 time 0 </dev/tty
        hide_cursor
      fi
      ;;
    m|M)
      # Amend the last commit — stage selected files then amend with editable message
      clear_drawn
      stty "$OLD_STTY" </dev/tty
      show_cursor

      # Apply any staging changes first
      declare -a _TO_STAGE=() _UNSTAGE_NEW=() _UNSTAGE_TRACKED=()
      for (( i=0; i<N; i++ )); do
        if [[ "${SEL[$i]}" == "1" && "${WAS_STAGED[$i]}" == "0" ]]; then
          _TO_STAGE+=("${PATHS[$i]}")
        elif [[ "${SEL[$i]}" == "0" && "${WAS_STAGED[$i]}" == "1" ]]; then
          if [[ "${XY[$i]:0:1}" == "A" ]]; then _UNSTAGE_NEW+=("${PATHS[$i]}")
          else _UNSTAGE_TRACKED+=("${PATHS[$i]}"); fi
        fi
      done
      [[ ${#_UNSTAGE_NEW[@]}     -gt 0 ]] && git rm --cached -q -- "${_UNSTAGE_NEW[@]}"
      [[ ${#_UNSTAGE_TRACKED[@]} -gt 0 ]] && git restore --staged -- "${_UNSTAGE_TRACKED[@]}"
      [[ ${#_TO_STAGE[@]}        -gt 0 ]] && git add -- "${_TO_STAGE[@]}"

      # Show what's going into the amended commit
      local _all_staged=()
      for (( i=0; i<N; i++ )); do
        [[ "${SEL[$i]}" == "1" ]] && _all_staged+=("${PATHS[$i]}")
      done
      if [[ ${#_all_staged[@]} -gt 0 ]]; then
        echo "$(bold 'Files in amended commit:')"
        for f in "${_all_staged[@]}"; do echo "  $(green '+') $f"; done
        echo
      fi
      prev_msg=$(git log -1 --pretty=format:'%B' 2>/dev/null || echo '')
      printf "$(bold 'Amend commit message') $(dim '(blank to abort):')\n  › "
      # Print the previous message so the user can see it, then read a new one
      printf '%s' "$prev_msg"
      echo
      printf "  › "
      IFS= read -r commit_msg </dev/tty
      [[ -z "$commit_msg" ]] && commit_msg="$prev_msg"

      if [[ -z "$commit_msg" ]]; then
        echo "$(yellow 'No message — amend aborted.')"
        exit 0
      fi

      echo
      if git commit --amend -m "$commit_msg"; then
        echo
        echo "$(green '✓') Amended successfully."
      else
        echo
        echo "$(red 'Amend failed.')"
        exit 1
      fi
      exit 0
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

# Restore terminal immediately after event loop
stty "$OLD_STTY" </dev/tty
show_cursor

# ── Apply staging changes ─────────────────────────────────────────────────────
clear_drawn

declare -a TO_STAGE=() UNSTAGE_NEW=() UNSTAGE_TRACKED=()
declare -a CMDS=()   # log of git commands run
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
  for f in "${UNSTAGE_NEW[@]}" "${UNSTAGE_TRACKED[@]}"; do echo "  $(red '−') $f"; done
  if [[ "$DRY_RUN" == "0" ]]; then
    if [[ ${#UNSTAGE_NEW[@]} -gt 0 ]]; then
      git rm --cached -q -- "${UNSTAGE_NEW[@]}"
      CMDS+=("git rm --cached -- ${UNSTAGE_NEW[*]}")
    fi
    if [[ ${#UNSTAGE_TRACKED[@]} -gt 0 ]]; then
      git restore --staged -- "${UNSTAGE_TRACKED[@]}"
      CMDS+=("git restore --staged -- ${UNSTAGE_TRACKED[*]}")
    fi
  fi
  echo
fi

if [[ ${#TO_STAGE[@]} -gt 0 ]]; then
  echo "$(bold 'Staging:')"
  for f in "${TO_STAGE[@]}"; do echo "  $(green '+') $f"; done
  if [[ "$DRY_RUN" == "0" ]]; then
    git add -- "${TO_STAGE[@]}"
    CMDS+=("git add -- ${TO_STAGE[*]}")
  fi
  echo
fi

# Determine what's staged now
declare -a NOW_STAGED=()
for (( i=0; i<N; i++ )); do
  [[ "${SEL[$i]}" == "1" ]] && NOW_STAGED+=("${PATHS[$i]}")
done

if [[ ${#NOW_STAGED[@]} -eq 0 ]]; then
  prev_msg=$(git log -1 --pretty=format:'%s' 2>/dev/null || true)
  prev_meta=$(git log -1 --pretty=format:'%an, %ad, %h' --date=format:'%a %b %d %H:%M:%S' 2>/dev/null || true)
  [[ -n "$prev_msg" ]] && echo "$(dim "previous commit: $prev_msg [$prev_meta]")"
  echo "$(yellow 'Nothing staged — aborting commit.')"
  exit 0
fi

if [[ ${#TO_STAGE[@]} -eq 0 && $(( ${#UNSTAGE_NEW[@]} + ${#UNSTAGE_TRACKED[@]} )) -eq 0 ]]; then
  echo "$(dim 'Staging unchanged.')"
  prev_msg=$(git log -1 --pretty=format:'%s' 2>/dev/null || true)
  prev_meta=$(git log -1 --pretty=format:'%an, %ad, %h' --date=format:'%a %b %d %H:%M:%S' 2>/dev/null || true)
  [[ -n "$prev_msg" ]] && echo "$(dim "previous commit: $prev_msg [$prev_meta]")"
  echo
fi

# ── Commit message ────────────────────────────────────────────────────────────
printf "$(bold 'Commit message') $(dim '(blank to abort):')\n  › "
IFS= read -r commit_msg </dev/tty

if [[ -z "$commit_msg" ]]; then
  echo "$(yellow 'No message given — files are staged but not committed.')"
  exit 0
fi

# ── Commit ────────────────────────────────────────────────────────────────────
echo
if [[ "$DRY_RUN" == "1" ]]; then
  echo "$(yellow '[dry run] would commit:') $commit_msg"
elif git commit -m "$commit_msg"; then
  CMDS+=("git commit -m \"$commit_msg\"")

  # ── Post-commit UI ───────────────────────────────────────────────────────────
  stty -echo -icanon min 1 time 0 </dev/tty
  hide_cursor

  cur_commit=$(git log -1 --pretty=format:'%s' 2>/dev/null || true)
  cur_meta=$(git log -1 --pretty=format:'%an, %ad, %h' --date=format:'%a %b %d %H:%M:%S' 2>/dev/null || true)
  branch=$(git branch --show-current 2>/dev/null || echo 'detached HEAD')

  tput clear
  printf '%s\n' \
    "$(bold 'git-stage') — $(green "$branch") · $(dim 'committed')" \
    "$(dim " current commit: $cur_commit [$cur_meta]")" \
    "$(dim ' p push   q quit')" \
    "$(dim ' ────────────────────────────────────────────────────────────')"

  while true; do
    key=""
    IFS= read -r -s -n1 key </dev/tty || true
    if [[ "$key" == $'\x1b' ]]; then
      seq=""
      IFS= read -r -s -n2 -t 0.1 seq </dev/tty || true
      key="${key}${seq}"
    fi
    case "$key" in
      p|P)
        stty "$OLD_STTY" </dev/tty
        show_cursor
        tput clear
        echo "$(bold "Pushing to origin:$branch...")"
        if git push --set-upstream origin "$branch"; then
          CMDS+=("git push --set-upstream origin $branch")
          echo "$(green '✓') Pushed successfully."
        else
          echo "$(red 'Push failed.')"
        fi
        break ;;
      q|Q|$'\x03'|$'\x1b')
        stty "$OLD_STTY" </dev/tty
        show_cursor
        tput clear
        break ;;
    esac
  done
else
  echo
  echo "$(red 'Commit failed — files remain staged.')"
  exit 1
fi

# ── Commands run ──────────────────────────────────────────────────────────────
if [[ ${#CMDS[@]} -gt 0 && "$QUIET" == "0" ]]; then
  echo
  echo "$(dim 'Commands run:')"
  for cmd in "${CMDS[@]}"; do echo "$(dim "  $cmd")"; done
fi
