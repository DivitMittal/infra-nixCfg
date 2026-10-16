# shellcheck shell=bash
# Shared fixtures for the utils/*.sh bats suites.
#
# Every test runs with PATH confined to $STUB_BIN: a handful of real tools are
# symlinked in, everything else (hostname, sudo, nix, ssh, rebuild tools, ...)
# is a stub created per test. Stubs append their argv to $STUB_LOG.

UTILS="$(cd "$BATS_TEST_DIRNAME/../../utils" && pwd)"
export UTILS

# Real tools the scripts (and stubs) are allowed to use.
REAL_TOOLS=(bash cat chmod date dirname env git grep head id install mkdir mktemp readlink rm sed touch tr wc)

setup_sandbox() {
  STUB_BIN="$BATS_TEST_TMPDIR/bin"
  STUB_LOG="$BATS_TEST_TMPDIR/stub.log"
  REPO="$BATS_TEST_TMPDIR/repo"
  export STUB_BIN STUB_LOG REPO
  mkdir -p "$STUB_BIN" "$REPO"
  : >"$STUB_LOG"

  local tool real
  for tool in "${REAL_TOOLS[@]}"; do
    real="$(command -v "$tool")" || continue
    ln -sf "$real" "$STUB_BIN/$tool"
  done
  export PATH="$STUB_BIN"

  stub hostname 'echo testhost'
}

# stub <name> [body]: create an executable that logs its argv then runs body.
stub() {
  local name="$1" body="${2:-exit 0}"
  cat >"$STUB_BIN/$name" <<EOF
#!$BASH
printf '%s %s\n' "$name" "\$*" >>"\$STUB_LOG"
$body
EOF
  chmod +x "$STUB_BIN/$name"
}

# A sudo that just runs its arguments.
stub_sudo() {
  stub sudo 'exec "$@"'
}

# init_repo [dirty]: a clean git repo with one commit and a flake.nix.
init_repo() {
  git -C "$REPO" init -q
  git -C "$REPO" config user.name test
  git -C "$REPO" config user.email test@example.com
  git -C "$REPO" config commit.gpgsign false
  git -C "$REPO" config tag.gpgsign false
  echo '{}' >"$REPO/flake.nix"
  git -C "$REPO" add flake.nix
  git -C "$REPO" commit -qm init
}

tags() {
  git -C "$REPO" tag --list
}

assert_logged() {
  if ! grep -qF -- "$1" "$STUB_LOG"; then
    echo "expected stub log to contain: $1" >&2
    echo "--- stub log ---" >&2
    cat "$STUB_LOG" >&2
    return 1
  fi
}

refute_logged() {
  if grep -qF -- "$1" "$STUB_LOG"; then
    echo "expected stub log NOT to contain: $1" >&2
    cat "$STUB_LOG" >&2
    return 1
  fi
}

# $output is set by bats' `run`.
# shellcheck disable=SC2154
assert_output_contains() {
  if [[ $output != *"$1"* ]]; then
    echo "expected output to contain: $1" >&2
    echo "--- output ---" >&2
    echo "$output" >&2
    return 1
  fi
}
