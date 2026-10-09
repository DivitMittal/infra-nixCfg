#!/usr/bin/env bash
# Remote first activation for non-NixOS Linux hosts managed by system-manager.
#
# Unlike bootstrap_nixos.sh, this never partitions disks or calls nixos-anywhere.
# --check and --switch require the target to already have Nix installed with
# flakes enabled or usable via --extra-experimental-features. For a target with
# no Nix at all and no interest in a system-wide install, --install-nix-portable
# provisions https://github.com/DavHau/nix-portable first (rootless, no config).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

usage() {
  cat <<'EOF'
Usage:
  bootstrap-system-manager <host> --target <ssh-target> --install-nix-portable [options]
  bootstrap-system-manager <host> --target <ssh-target> --check [options]
  bootstrap-system-manager <host> --target <ssh-target> --switch [options]

Arguments:
  <host>                  Host attr under .#systemConfigs.<host>.

Options:
  --target <ssh-target>       SSH target for an existing Linux host, e.g. root@203.0.113.10.
  --install-nix-portable      Install davhau/nix-portable on the target, then exit.
  --check                     Run local/remote preflight checks only; do not switch.
  --switch                    Build and activate the system-manager profile remotely.
  --port <port>                SSH port.
  --ssh-identity <path>        SSH identity for reaching the target system.
  --ssh-option <option>        Extra SSH option for ssh and system-manager.
  -h, --help                   Show this help.

Notes:
  --check and --switch require Nix already reachable on the target's non-interactive
  SSH PATH. This helper does not manage disks and is suitable for LXC VPS targets
  where nixos-anywhere/disko/bootloader flows are not available.

  --install-nix-portable is for targets with no Nix at all: it fetches the
  https://github.com/DavHau/nix-portable release for the target's architecture
  and installs it as root's "nix" (rootless, no daemon, no system changes beyond
  the binary itself). Run it once before the first --check/--switch on a fresh
  host, as root, then re-run with --check.
EOF
}

host=""
target=""
check_only=false
switch_profile=false
install_nix_portable=false
port=""
ssh_identity=""
ssh_options=()

require_value() {
  local option="$1"
  local value="${2:-}"

  if [[ -z $value ]]; then
    red "Missing value for $option."
    usage
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --target)
    require_value "$1" "${2:-}"
    target="$2"
    shift
    ;;
  --check)
    check_only=true
    ;;
  --switch)
    switch_profile=true
    ;;
  --install-nix-portable)
    install_nix_portable=true
    ;;
  --port)
    require_value "$1" "${2:-}"
    port="$2"
    shift
    ;;
  --ssh-identity)
    require_value "$1" "${2:-}"
    ssh_identity="$2"
    shift
    ;;
  --ssh-option)
    require_value "$1" "${2:-}"
    ssh_options+=("$2")
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  --*)
    red "Unknown option: $1"
    usage
    exit 1
    ;;
  *)
    if [[ -n $host ]]; then
      red "Unexpected extra argument: $1"
      usage
      exit 1
    fi
    host="$1"
    ;;
  esac
  shift
done

if [[ -z $host ]]; then
  red "Missing host."
  usage
  exit 1
fi

if [[ -z $target ]]; then
  red "Missing --target."
  usage
  exit 1
fi

mode_count=0
for mode in "$check_only" "$switch_profile" "$install_nix_portable"; do
  if [[ $mode == true ]]; then
    mode_count=$((mode_count + 1))
  fi
done

if [[ $mode_count -eq 0 ]]; then
  red "Choose one of --check, --switch, or --install-nix-portable."
  usage
  exit 1
fi

if [[ $mode_count -gt 1 ]]; then
  red "Choose only one of --check, --switch, or --install-nix-portable."
  usage
  exit 1
fi

if [[ ! -f flake.nix ]]; then
  red "Run this from the flake repository root."
  exit 1
fi

ssh_cmd=(ssh)
system_manager_ssh_args=()

if [[ -n $port ]]; then
  ssh_cmd+=(-p "$port")
  system_manager_ssh_args+=(--ssh-option "-p" --ssh-option "$port")
fi

if [[ -n $ssh_identity ]]; then
  ssh_cmd+=(-i "$ssh_identity")
  system_manager_ssh_args+=(--ssh-option "-i" --ssh-option "$ssh_identity")
fi

for option in "${ssh_options[@]}"; do
  ssh_cmd+=(-o "$option")
  system_manager_ssh_args+=(--ssh-option "-o" --ssh-option "$option")
done

ssh_cmd+=("$target")

require_command() {
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    red "Missing required command: $command_name"
    exit 1
  fi
}

remote() {
  "${ssh_cmd[@]}" "$@"
}

remote_install_nix_portable() {
  green "====== INSTALLING NIX-PORTABLE ======"

  green "Checking remote kernel"
  remote_os="$(remote uname -s)"
  if [[ $remote_os != "Linux" ]]; then
    red "Remote target is $remote_os, expected Linux."
    exit 1
  fi

  remote_arch="$(remote uname -m)"
  case "$remote_arch" in
  x86_64 | aarch64) ;;
  *)
    red "nix-portable has no published release for remote arch: $remote_arch"
    exit 1
    ;;
  esac

  local release_url="https://github.com/DavHau/nix-portable/releases/latest/download/nix-portable-${remote_arch}"
  yellow "Fetching $release_url on $target."

  # release_url has no whitespace, so passing it as a single ssh argv element
  # round-trips safely (ssh joins remote argv with plain spaces, unescaped).
  remote env NP_RELEASE_URL="$release_url" bash -s <<'REMOTE_SCRIPT'
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "install-nix-portable must run as root on the target (current user: $(whoami))." >&2
  exit 1
fi

# Executables that should behave as their real nix-native counterparts once
# symlinked to the nix-portable binary; see the "Multi-call binary" section of
# https://github.com/DavHau/nix-portable.
symlinks=(
  nix
  nix-build
  nix-channel
  nix-collect-garbage
  nix-copy-closure
  nix-env
  nix-hash
  nix-instantiate
  nix-shell
  nix-store
)

bin_dir="/usr/local/bin"
install -d -m 0755 "$bin_dir"

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
curl -fsSL "$NP_RELEASE_URL" -o "$tmp"
install -m 0755 "$tmp" "$bin_dir/nix-portable"

for name in "${symlinks[@]}"; do
  ln -sf "$bin_dir/nix-portable" "$bin_dir/$name"
done

"$bin_dir/nix" --extra-experimental-features "nix-command flakes" --version
REMOTE_SCRIPT

  green "nix-portable installed as /usr/local/bin/nix (and nix-build, nix-store, etc.) on $target."
  yellow "It stores its Nix store under root's \$HOME/.nix-portable and picks bubblewrap or"
  yellow "proot automatically (override with NP_RUNTIME=bwrap|proot|nix on the target)."
  yellow "Re-run with --check to verify system-manager can now reach it."
}

if [[ $install_nix_portable == true ]]; then
  require_command ssh
  remote_install_nix_portable
  exit 0
fi

green "====== SYSTEM-MANAGER PREFLIGHT ======"
require_command nix
require_command ssh

green "Building .#systemConfigs.$host"
nix build --show-trace --accept-flake-config ".#systemConfigs.$host"

green "Checking SSH connectivity to $target"
remote true

green "Checking remote kernel"
remote_os="$(remote uname -s)"
if [[ $remote_os != "Linux" ]]; then
  red "Remote target is $remote_os, expected Linux."
  exit 1
fi

green "Checking remote Nix"
remote nix --version

green "Checking remote Nix command support"
remote nix --extra-experimental-features "nix-command flakes" eval --expr 'builtins.currentSystem' >/dev/null

if remote test -r /etc/os-release; then
  os_release="$(remote sh -c '. /etc/os-release; printf "%s %s" "${ID:-unknown}" "${ID_LIKE:-}"')"
  case " $os_release " in
  *" debian "* | *" ubuntu "* | *" nixos "*)
    green "Remote distro looks supported by system-manager: $os_release"
    ;;
  *)
    yellow "Remote distro may need system-manager.allowAnyDistro = true: $os_release"
    ;;
  esac
else
  yellow "Could not read /etc/os-release on the remote target."
fi

if [[ $check_only == true ]]; then
  green "Preflight checks passed for $host on $target."
  exit 0
fi

require_command system-manager

green "====== SYSTEM-MANAGER SWITCH ======"
yellow "Activating .#$host on $target with system-manager --sudo."
system-manager \
  --target-host "$target" \
  "${system_manager_ssh_args[@]}" \
  switch \
  --flake ".#$host" \
  --sudo

green "System-manager switch completed for $host on $target."
