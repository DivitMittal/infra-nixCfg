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
├── iso/                        # ISO builds (NixOS install media)
│   ├── enum.nix
│   ├── iso/                    # x86_64-linux vanilla
│   ├── t2-iso/                 # x86_64-linux T2
│   └── as-iso/                 # aarch64-linux Apple Silicon
├── openwrt/                    # OpenWrt router configurations
│   ├── enum.nix
│   └── R1/                      # primary router
│       ├── R1.nix              # primary configuration
│       └── modules/            # auto-imported UCI modules
└── switch/                     # Terraform-managed (terranix) switches
    ├── enum.nix
    └── S1/                      # TP-Link TL-SG105E, mgmt 192.168.2.2
        └── default.nix         # terranix module (VLANs, PVIDs, ...)
```

## Switch Configurations (terranix)

`hosts/switch/` holds plain-attrset terranix modules for switches that don't
run OpenWrt/NixOS but expose a Terraform-manageable API — currently S1, a
TP-Link Easy Smart switch managed via
[terraform-provider-tplink-easysmart](https://github.com/lucavb/terraform-provider-tplink-easysmart).
Each host is registered in `hosts/switch/enum.nix` under
`flake.switchConfigurations.<name>` and compiled to `config.tf.json` by
`flake/terranix.nix`.

Unlike the NixOS-style hosts above, these aren't `mkCfg`-generated systems —
there's nothing to activate on the switch itself, so `terraform`/`tofu` runs
from the workstation against the switch's web UI.

```bash
nix run .#switch-S1              # plan (default, read-only)
nix run .#switch-S1 -- apply
```

The admin password is decrypted at run time from
`OS-nixCfg-secrets/secrets/lan/S1.age` (declared in that repo's
`secrets/manifest.nix`, same convention as every other secret consumed via
`common/home/age.nix`) using the `~/.ssh/agenix/id_ed25519` identity, and
exported as `TF_VAR_switch_s1_password` — it is never stored in this repo.
State lives outside the repo, in
`$XDG_STATE_HOME/os-nixcfg/terraform/switch-S1`.

`secrets/lan/R1.age` is a symlink to `secrets/lan/S1.age` — R1's OpenWrt
root password (set over SSH during `nix run .#openwrt-ont <target>`, see
`flake/openwrt.nix`) intentionally shares S1's admin password, one
ciphertext for both.

To create the secret itself (from inside `OS-nixCfg-secrets`, after entering
its devshell so `ragenix`/`RULES` are set up):

```bash
ragenix -e secrets/lan/S1.age
```

## Host Directory Layout

Files are auto-imported via `lib.custom.scanPaths`. The host's primary
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
