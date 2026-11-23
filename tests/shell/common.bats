#!/usr/bin/env bats
# utils/common.sh

setup() {
  load helpers
  setup_sandbox
  # shellcheck source=../../utils/common.sh
  source "$UTILS/common.sh"
}

@test "red/green/yellow prefix and colour the message" {
  run red "boom"
  [ "$status" -eq 0 ]
  [ "$output" = $'\e[31m[!] boom \e[0m' ]

  run green "ok"
  [ "$output" = $'\e[32m[+] ok \e[0m' ]

  run yellow "hmm"
  [ "$output" = $'\e[33m[*] hmm \e[0m' ]
}

@test "colour helpers run an optional second argument as a command" {
  run green "label" "echo from-command"
  [ "${lines[0]}" = $'\e[32m[+] label \e[0m' ]
  [ "${lines[1]}" = $'\e[32m[+] from-command \e[0m' ]
}

@test "colour helpers print a single line without a second argument" {
  run red "only"
  [ "${#lines[@]}" -eq 1 ]
}

@test "build_switch_args targets the current hostname" {
  run build_switch_args
  [ "$output" = " --keep-going --flake .#testhost switch" ]
}

@test "build_switch_args forwards extra flags before the defaults" {
  run build_switch_args -v --show-trace
  [ "$output" = "-v --show-trace --keep-going --flake .#testhost switch" ]
}

@test "post_rebuild_success tags a clean tree with the given prefix" {
  init_repo
  cd "$REPO"
  run post_rebuild_success home
  [ "$status" -eq 0 ]
  assert_output_contains "Tagged current commit as buildable"
  [[ "$(tags)" =~ ^home-buildable-[0-9]{14}$ ]]
}

@test "post_rebuild_success defaults the prefix to 'buildable'" {
  init_repo
  cd "$REPO"
  run post_rebuild_success
  [[ "$(tags)" =~ ^buildable-buildable-[0-9]{14}$ ]]
}

@test "post_rebuild_success does not re-tag an already tagged commit" {
  init_repo
  git -C "$REPO" tag host-buildable-20000101000000 -m ''
  cd "$REPO"
  run post_rebuild_success host
  assert_output_contains "already tagged as buildable"
  [ "$(tags | wc -l | tr -d ' ')" -eq 1 ]
}

@test "post_rebuild_success refuses to tag with unstaged changes" {
  init_repo
  echo changed >"$REPO/flake.nix"
  cd "$REPO"
  run post_rebuild_success host
  assert_output_contains "pending changes"
  [ -z "$(tags)" ]
}

@test "post_rebuild_success refuses to tag with staged changes" {
  init_repo
  echo changed >"$REPO/flake.nix"
  git -C "$REPO" add flake.nix
  cd "$REPO"
  run post_rebuild_success host
  assert_output_contains "pending changes"
  [ -z "$(tags)" ]
}

@test "post_rebuild_success ignores untracked files" {
  init_repo
  echo new >"$REPO/untracked.txt"
  cd "$REPO"
  run post_rebuild_success host
  [[ "$(tags)" =~ ^host-buildable- ]]
}
