# Hosts Directory

Platform-specific host configurations. Each platform directory contains an
`enum.nix` that enumerates the platform's hosts via `mkCfg`, plus one
subdirectory per host.

## Structure

```
hosts/
├── darwin/                     # macOS (nix-darwin)
│   ├── enum.nix
│   ├── L1/                     # x86_64-darwin workstation
│   └── ASL1/                   # aarch64-darwin workstation
├── nixos/                      # NixOS systems
│   ├── enum.nix
│   ├── L2/                     # x86_64-linux desktop
│   ├── T2/                     # x86_64-linux T2 MacBook
│   ├── ASL1N/                  # aarch64-linux on ASL1
│   ├── colima/                 # x86_64-linux VM
│   ├── VPS0/                   # aarch64-linux Oracle A1 Flex VPS (Mumbai)
│   ├── VPS1/                   # x86_64-linux VPS (Mumbai)
│   ├── VPS2/                   # x86_64-linux VPS (Germany)
│   └── WSL/                    # x86_64-linux WSL2
├── droid/                      # Android (nix-on-droid)
│   ├── enum.nix
│   └── M1/                     # aarch64-linux Android
├── system-manager/             # non-NixOS Linux (numtide/system-manager)
│   ├── enum.nix
│   ├── Linux1/                 # generic Linux host with Nix installed
│   └── VPS3/                   # LXC VPS, not a KVM/NixOS install target
└── iso/                        # ISO builds (NixOS install media)
    ├── enum.nix
    ├── iso/                    # x86_64-linux vanilla
    ├── t2-iso/                 # x86_64-linux T2
    └── as-iso/                 # aarch64-linux Apple Silicon
```

## Host Directory Layout

Files are imported by `mkCfg` using `inputs.import-tree`. The host's primary
module is `<hostName>.nix`; supplementary files vary by platform.

Typical NixOS host:

```
hostname/
├── hostname.nix                # primary config
├── hardware.nix                # nixos-generate-config output
├── topology.nix                # network topology position
├── disko.nix                   # disk layout
├── home/                       # host-specific home-manager
├── programs/
└── services/
```

Darwin host:

```
hostname/
├── hostname.nix                # primary config
├── fstab.nix                   # mountpoints
├── defaults/                   # macOS `defaults` overrides
├── programs/
└── services/
```

## Adding Host

1. Create `hosts/{platform}/{hostname}/`
2. Add `<hostName>.nix` (and any platform-specific files)
3. Register in `hosts/{platform}/enum.nix` using `mkCfg`

## Rebuild

```bash
hts  # System rebuild
```

## Non-NixOS Linux with system-manager

Use `numtide/system-manager` for existing Linux machines that should be managed
from this flake but are not full NixOS installations. These hosts are declared in
`.#systemConfigs` and live under `hosts/system-manager/`.

Current examples:

- `Linux1` is a generic non-NixOS Linux host with Nix already installed.
- `VPS3` is an LXC VPS. It intentionally avoids NixOS/KVM-only concepts such as
  `nixos-anywhere`, `disko`, GRUB, kernel/initrd modules, and bootloader
  management.

Build the profiles explicitly because `nix flake check` does not necessarily
force-build custom `systemConfigs` outputs:

```bash
nix build --show-trace --accept-flake-config .#systemConfigs.Linux1
nix build --show-trace --accept-flake-config .#systemConfigs.VPS3
```

Enter the devshell to use the pinned `system-manager` CLI and wrappers. The
`sms` passthrough is available only on systems where upstream packages
`system-manager` for the current platform; from unsupported platforms, use the
build/eval checks locally and run activation from a supported Linux/aarch64-darwin
environment.

```bash
nix develop
sms build --flake .#Linux1
sms build --flake .#VPS3
```

Run remote preflight checks against an existing Linux SSH target:

```bash
bootstrap-system-manager VPS3 --target root@203.0.113.10 --check
```

Then switch only after the checks pass:

```bash
bootstrap-system-manager VPS3 --target root@203.0.113.10 --switch
# or directly:
sms --target-host root@203.0.113.10 switch --flake .#VPS3 --sudo
```

`--check` and `--switch` need `nix` reachable on the target's non-interactive
SSH `PATH`. On a fresh VPS with no Nix installed and no interest in a
system-wide Nix install, provision
[`davhau/nix-portable`](https://github.com/DavHau/nix-portable) first — it is a
single static, rootless binary with flakes enabled out of the box, so no
`curl | sh` installer or daemon setup is required on the target:

```bash
bootstrap-system-manager VPS3 --target root@203.0.113.10 --install-nix-portable
bootstrap-system-manager VPS3 --target root@203.0.113.10 --check
bootstrap-system-manager VPS3 --target root@203.0.113.10 --switch
```

`--install-nix-portable` downloads the release matching the target's `uname -m`
and installs it as `/usr/local/bin/nix` (plus the other `nix-*` multi-call
names) so it resolves the same way a real Nix install would for both
non-interactive SSH commands and `system-manager --target-host`. It requires
root on the target and only touches that one binary and its symlinks — nothing
else on the host changes, and there is no long-running daemon to manage.

For distributions outside system-manager's supported set (currently NixOS,
Ubuntu, and Debian), set this in the host module after confirming the risk:

```nix
system-manager.allowAnyDistro = true;
```

For LXC providers, also confirm the container supports the systemd features your
host module uses. Keep initial LXC profiles package-focused until systemd service
activation has been tested on that provider.

## Remote NixOS Bootstrap

Use `nixos-anywhere` for first install/reinstall of any NixOS host declared in
`.#nixosConfigurations`. The devshell provides a thin safety wrapper named
`bootstrap-remote` that keeps host details explicit instead of baking provider
endpoints into the script.

Enter the devshell first:

```bash
nix develop
```

Run non-destructive checks against a rescue/current Linux SSH target:

```bash
bootstrap-remote <host> --target root@203.0.113.10 --check
```

Targets may be root or a regular user. Regular-user targets, such as Ubuntu's
`ubuntu` cloud user, must have passwordless sudo because disk inspection and the
final install need root privileges:

```bash
bootstrap-remote <host> --target ubuntu@203.0.113.10 --check
```

Then run the destructive install only after confirming the SSH target and checked
disk are correct:

```bash
bootstrap-remote <host> --target root@203.0.113.10 --yes-destroy-disk
```

By default the wrapper checks `/dev/sda` before install. Override that when a
host's disko layout targets a different device:

```bash
bootstrap-remote <host> --target root@203.0.113.10 --disk /dev/vda --check
```

The wrapper evaluates `.#nixosConfigurations.<host>` locally, checks SSH access,
checks the target disk, then calls `nixos-anywhere --flake .#<host> --build-on
remote`. Remote building is the default because this workstation may be macOS
while the target is Linux.

If an agenix identity is needed on the installed system, the wrapper copies a
local private key into the new root as `/var/lib/agenix/id_ed25519` via
`nixos-anywhere --extra-files`. By default it uses
`${HOME}/.ssh/agenix/id_ed25519` or `AGENIX_IDENTITY_PATH`; pass
`--agenix-identity <path>` to be explicit, or `--no-agenix` for hosts that do not
need system-level agenix at bootstrap. Never commit this private key.

Useful options:

```bash
bootstrap-remote <host> --target root@203.0.113.10 --port 2222 --check
bootstrap-remote <host> --target root@203.0.113.10 --ssh-identity ~/.ssh/rescue --check
bootstrap-remote <host> --target root@203.0.113.10 --build-on auto --check
```

### VPS Examples

`VPS0`, `VPS1`, and `VPS2` are first-class NixOS hosts in this flake:

- `VPS0` is the Oracle Cloud VM.Standard.A1.Flex VPS in Mumbai. It is
  `aarch64-linux`, boots via UEFI GRUB installed as removable media, uses OCI
  DHCPv4 matched by MAC `02:00:17:05:eb:38`, and its disko layout targets the
  stable OCI by-id path
  `/dev/disk/by-id/scsi-36075f9bc9c73417586c6fd09a98be681`.
- `VPS1` is the Mumbai KVM VPS. It uses static private IPv4
  `10.10.10.51/24` and is reached for deploys through public NAT at
  `148.113.8.216:20041`.
- `VPS2` is the Germany KVM VPS. It is IPv6-only at
  `2a0e:97c0:3e3:34d::1/64` with gateway `fe80::1` on `eth0`.

`VPS1` and `VPS2` disko layouts target `/dev/sda`; `VPS0` targets its OCI by-id
disk. For an Oracle Ubuntu image, bootstrap through the `ubuntu` user only after
confirming passwordless sudo works.

```bash
bootstrap-remote VPS0 --target ubuntu@80.225.249.202 --disk /dev/disk/by-id/scsi-36075f9bc9c73417586c6fd09a98be681 --check
bootstrap-remote VPS0 --target ubuntu@80.225.249.202 --disk /dev/disk/by-id/scsi-36075f9bc9c73417586c6fd09a98be681 --yes-destroy-disk

bootstrap-remote VPS1 --target root@148.113.8.216 --port 20041 --check
bootstrap-remote VPS1 --target root@148.113.8.216 --port 20041 --yes-destroy-disk

bootstrap-remote VPS2 --target root@2a0e:97c0:3e3:34d::1 --check
bootstrap-remote VPS2 --target root@2a0e:97c0:3e3:34d::1 --yes-destroy-disk
```

### Steady-state deploys

After bootstrap, use deploy-rs rather than `nixos-anywhere`. VPS system deploys
are intentionally system-only; deploy Home Manager separately through the
matching `*-home` node.

```bash
nix eval --raw .#nixosConfigurations.VPS0.config.system.build.toplevel.drvPath
nix eval --raw .#nixosConfigurations.VPS1.config.system.build.toplevel.drvPath
nix eval --raw .#nixosConfigurations.VPS2.config.system.build.toplevel.drvPath
deploy .#VPS0 --dry-activate
deploy .#VPS1 --dry-activate
deploy .#VPS2 --dry-activate
deploy .#VPS0
deploy .#VPS1
deploy .#VPS2
```

The VPS deploy nodes intentionally use `magicRollback = false`, so the recovery
plan for broken network/SSH changes is provider console or rescue mode. They
also use `remoteBuild = true` so Linux closures build on the VPSes instead of
the macOS workstation. Prefer local evaluation, dry activation, SSH smoke tests,
and one host at a time for risky VPS changes.

### Home Manager on VPSes

`VPS0`, `VPS1`, and `VPS2` expose standalone Home Manager configurations and
remote deploy-rs nodes. Deploy the NixOS system first so the normal user, SSH
keys, and agenix-backed passwords exist, then deploy the Home Manager profile as
that user.

```bash
nix eval --raw .#homeConfigurations.VPS0.activationPackage.drvPath
nix eval --raw .#homeConfigurations.VPS1.activationPackage.drvPath
nix eval --raw .#homeConfigurations.VPS2.activationPackage.drvPath

deploy .#VPS0-home --dry-activate
deploy .#VPS1-home --dry-activate
deploy .#VPS2-home --dry-activate
deploy .#VPS0-home
deploy .#VPS1-home
deploy .#VPS2-home
```

Inside the devshell, `deploy-home VPS1 --dry-activate` is a shorthand for
`deploy .#VPS1-home --dry-activate`. The local `hms` and `hts` commands still
operate on the current machine's hostname and are not remote deploy wrappers.
