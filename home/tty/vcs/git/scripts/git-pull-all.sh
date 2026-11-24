# Pull every git repository found under one or more directories, then print a
# summary of what was updated, skipped, and what failed.
#
# Repos are pulled one at a time so their output doesn't interleave. Network
# auth prompts are disabled (GIT_TERMINAL_PROMPT=0) so a single repo with an
# expired credential fails fast instead of blocking the whole sweep.
#
# Usage: git-pull-all [--dry-run] [--ff-only] [--max-depth N] [DIR...]

usage() {
  cat <<'EOF'
Usage: git-pull-all [--dry-run] [--ff-only] [--max-depth N] [DIR...]

Find every git repository under DIR (default: current directory) and pull it.

  -n, --dry-run      show what would be pulled, without touching the network
  -f, --ff-only      pass --ff-only to git pull (never create merge commits)
  -d, --max-depth N  limit how deep to search for repositories
  -h, --help         show this help

Set NO_COLOR=1 to disable colors.
EOF
}

## Options

DRY_RUN=false
PULL_ARGS=()
FD_ARGS=()
DIRS=()

while [ $# -gt 0 ]; do
  case "$1" in
  -n | --dry-run)
    DRY_RUN=true
    shift
    ;;
  -f | --ff-only)
    PULL_ARGS+=(--ff-only)
    shift
    ;;
  -d | --max-depth)
    [ $# -ge 2 ] || {
      echo "error: $1 needs a value" >&2
      exit 1
    }
    # +1 because we match the .git dir, which sits one level below the repo.
    FD_ARGS+=(--max-depth "$(($2 + 1))")
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --)
    shift
    DIRS+=("$@")
    break
    ;;
  -*)
    echo "error: unknown flag: $1" >&2
    usage >&2
    exit 1
    ;;
  *)
    DIRS+=("$1")
    shift
    ;;
  esac
done

[ ${#DIRS[@]} -gt 0 ] || DIRS=(.)

for dir in "${DIRS[@]}"; do
  [ -d "$dir" ] || {
    echo "error: directory '$dir' does not exist" >&2
    exit 1
  }
done

## Styling

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  BOLD=$'\033[1m' DIM=$'\033[2m' RESET=$'\033[0m'
  RED=$'\033[31m' GREEN=$'\033[32m' YELLOW=$'\033[33m'
  BLUE=$'\033[34m' MAGENTA=$'\033[35m' CYAN=$'\033[36m'
else
  BOLD="" DIM="" RESET="" RED="" GREEN="" YELLOW="" BLUE="" MAGENTA="" CYAN=""
fi

G_UPDATED="${GREEN}✓${RESET}"
G_CURRENT="${BLUE}•${RESET}"
G_SKIPPED="${YELLOW}⊘${RESET}"
G_FAILED="${RED}✗${RESET}"
G_PLAN="${CYAN}→${RESET}"

rule() { printf '%s%s%s\n' "$DIM" "────────────────────────────────────────────────────────────" "$RESET"; }
header() { printf '\n%s%s%s\n' "$BOLD" "$1" "$RESET" && rule; }

## Discovery

# --prune stops fd from descending into each .git dir it matches. Newer fd
# prints directories with a trailing slash, so strip it before peeling /.git.
mapfile -t REPOS < <(
  fd -H -t d --prune "${FD_ARGS[@]}" '^\.git$' "${DIRS[@]}" |
    sed -e 's#/$##' -e 's#/\.git$##' -e 's#^\./##' -e 's#^$#.#' |
    sort -u
)

total=${#REPOS[@]}
if [ "$total" -eq 0 ]; then
  echo "${G_SKIPPED} No git repositories found in: ${DIRS[*]}"
  exit 0
fi

width=0
for repo in "${REPOS[@]}"; do
  [ ${#repo} -gt "$width" ] && width=${#repo}
done
[ "$width" -gt 48 ] && width=48

mode="pulling"
[ "$DRY_RUN" = true ] && mode="dry run"
noun="repositories"
[ "$total" -eq 1 ] && noun="repository"
header "git-pull-all ${DIM}·${RESET}${BOLD} ${total} ${noun} ${DIM}(${mode})${RESET}"

## Pull loop

export GIT_TERMINAL_PROMPT=0

UPDATED=() CURRENT=() SKIPPED=() FAILED=()
commits_total=0
i=0

# Print one aligned status line: glyph, [i/n], repo, then free-form detail.
line() {
  printf '%s %s[%*d/%d]%s %-*s  %s\n' \
    "$1" "$DIM" ${#total} "$i" "$total" "$RESET" "$width" "$repo" "$2"
}

for repo in "${REPOS[@]}"; do
  i=$((i + 1))

  if ! branch=$(git -C "$repo" symbolic-ref -q --short HEAD); then
    line "$G_SKIPPED" "${YELLOW}detached HEAD${RESET}"
    SKIPPED+=("$repo"$'\t'"detached HEAD")
    continue
  fi

  if ! upstream=$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null); then
    line "$G_SKIPPED" "${MAGENTA}${branch}${RESET} ${YELLOW}no upstream${RESET}"
    SKIPPED+=("$repo"$'\t'"$branch has no upstream")
    continue
  fi

  dirty=""
  [ -n "$(git -C "$repo" status --porcelain --untracked-files=no)" ] &&
    dirty=" ${YELLOW}✎ dirty${RESET}"

  if [ "$DRY_RUN" = true ]; then
    line "$G_PLAN" "${MAGENTA}${branch}${RESET} ${DIM}←${RESET} ${upstream}${dirty}"
    CURRENT+=("$repo")
    continue
  fi

  before=$(git -C "$repo" rev-parse HEAD)
  if ! out=$(git -C "$repo" pull "${PULL_ARGS[@]}" 2>&1); then
    line "$G_FAILED" "${MAGENTA}${branch}${RESET} ${RED}pull failed${RESET}${dirty}"
    # Last few non-empty lines are where git puts the actual reason.
    grep -v '^[[:space:]]*$' <<<"$out" | tail -n 3 | sed "s/^/      ${DIM}│${RESET} /"
    # For the report, the first fatal:/error: line is the most specific cause;
    # later lines tend to be generic advice ("Please commit or stash them.").
    reason=$(grep -m1 -E '^(fatal|error): ' <<<"$out" | sed -E 's/^(fatal|error): //' || true)
    [ -n "$reason" ] || reason=$(grep -m1 -v '^[[:space:]]*$' <<<"$out" || true)
    FAILED+=("$repo"$'\t'"${reason:-git pull exited non-zero}")
    continue
  fi
  after=$(git -C "$repo" rev-parse HEAD)

  ahead=$(git -C "$repo" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
  unpushed=""
  [ "$ahead" -gt 0 ] && unpushed=" ${CYAN}↑${ahead}${RESET}"

  if [ "$before" = "$after" ]; then
    line "$G_CURRENT" "${MAGENTA}${branch}${RESET} ${DIM}up to date${RESET}${unpushed}${dirty}"
    CURRENT+=("$repo")
    continue
  fi

  count=$(git -C "$repo" rev-list --count "$before..$after")
  commits_total=$((commits_total + count))
  range="${before:0:7}..${after:0:7}"
  line "$G_UPDATED" "${MAGENTA}${branch}${RESET} ${GREEN}↓${count}${RESET} ${DIM}${range}${RESET}${unpushed}${dirty}"
  UPDATED+=("$repo"$'\t'"↓${count} commits  ${range}")
done

## Report

# Print "repo  detail" rows from tab-separated entries, under a glyph heading.
section() {
  local glyph="$1" title="$2"
  shift 2
  [ $# -gt 0 ] || return 0
  printf '\n%s %s%s%s\n' "$glyph" "$BOLD" "$title" "$RESET"
  local entry
  for entry in "$@"; do
    printf '    %-*s  %s%s%s\n' "$width" "${entry%%$'\t'*}" "$DIM" "${entry#*$'\t'}" "$RESET"
  done
}

header "Report"
section "$G_UPDATED" "Updated" "${UPDATED[@]}"
section "$G_SKIPPED" "Skipped" "${SKIPPED[@]}"
section "$G_FAILED" "Failed" "${FAILED[@]}"

echo
rule
if [ "$DRY_RUN" = true ]; then
  printf '%s %s%d to pull%s  %s %d skipped  %s%ds%s\n' \
    "$G_PLAN" "$BOLD" ${#CURRENT[@]} "$RESET" \
    "$G_SKIPPED" ${#SKIPPED[@]} "$DIM" "$SECONDS" "$RESET"
else
  fail_style=""
  [ ${#FAILED[@]} -gt 0 ] && fail_style="$RED$BOLD"
  printf '%s %s%d updated%s %s(%d commits)%s  %s %d up to date  %s %d skipped  %s %s%d failed%s  %s%ds%s\n' \
    "$G_UPDATED" "$BOLD" ${#UPDATED[@]} "$RESET" "$DIM" "$commits_total" "$RESET" \
    "$G_CURRENT" ${#CURRENT[@]} \
    "$G_SKIPPED" ${#SKIPPED[@]} \
    "$G_FAILED" "$fail_style" ${#FAILED[@]} "$RESET" \
    "$DIM" "$SECONDS" "$RESET"
fi

[ ${#FAILED[@]} -eq 0 ]
