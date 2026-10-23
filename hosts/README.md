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
│   └── WSL/                    # x86_64-linux WSL2
├── droid/                      # Android (nix-on-droid)
│   ├── enum.nix
│   └── M1/                     # aarch64-linux Android
├── iso/                        # ISO builds (NixOS install media)
│   ├── enum.nix
│   ├── iso/                    # x86_64-linux vanilla
│   ├── t2-iso/                 # x86_64-linux T2
│   └── as-iso/                 # aarch64-linux Apple Silicon
└── cloud/                      # Terraform-managed (terranix) cloud infra
    ├── enum.nix
    ├── VPS1/                    # OVH VPS (Mumbai/YNM)
    │   └── default.nix         # terranix module (ovh_vps order)
    └── VPS0/                    # Oracle Cloud VPS
        └── default.nix         # terranix module (oci_core_instance)
```

## Cloud Configurations (terranix)

`hosts/cloud/` holds plain-attrset terranix modules that _commission_ cloud
infrastructure via provider APIs, rather than configuring an already-running
host — currently C1, an OVH VPS ordered via
[terraform-provider-ovh](https://github.com/ovh/terraform-provider-ovh) in
OVH's Mumbai (`YNM`) datacenter, replacing the decommissioned datalix VPS
(formerly `hosts/nixos/VPS2`). Each host is registered in
`hosts/cloud/enum.nix` under `flake.cloudConfigurations.<name>` and compiled
to `config.tf.json` by `flake/terranix.nix`. `ovh/ovh` is a normal published
registry provider — `flake/terranix.nix` pins nixpkgs'
`terraform-providers.ovh_ovh` mirror via `dev_overrides` purely for
reproducibility, not because the registry copy is broken.

Unlike the NixOS-style hosts above, there's nothing to activate on a
not-yet-ordered VPS — `terraform`/`tofu` runs from the workstation against
the provider API.

The Oracle target's tenancy/user/region/AD/compartment/subnet/image are all
single-valued for this account, so they default in
`hosts/cloud/VPS0/default.nix` — no `-var=` flags needed for a normal
plan/apply. The API signing key is decrypted from agenix at runtime by the
`cloud-VPS0` app (see `flake/terranix.nix`), so nothing to pass there either:

```bash
nix run .#cloud-VPS0 -- plan
nix run .#cloud-VPS0 -- apply
```

Override a default when needed, e.g. to target a different subnet or image:

```bash
nix run .#cloud-VPS0 -- plan -var='oci_image_ocid=<other-image-ocid>'
```

`cloud-VPS0` creates an OCI `VM.Standard.A1.Flex` instance and assigns a public
IP through the default subnet. It does not create or modify networking.

```bash
nix run .#cloud-C1 -- plan -var='ovh_subsidiary=IE'     # read-only
nix run .#cloud-C1 -- apply -var='ovh_subsidiary=IE'     # orders real, billed hardware
```

`ovh_subsidiary` has no default — OVH has no separate India API
endpoint/subsidiary (the Mumbai datacenter is billed through one of
CZ/DE/ES/EU/FI/FR/GB/IE/IT/LT/MA/NL/PL/PT/SN/TN); set it to whatever your OVH
account is actually registered under. `application_key`/`application_secret`/
`consumer_key` are decrypted at run time the same way every other secret in
this repo is (via `common/home/age.nix`'s convention), from three secrets
that don't exist yet and must be created by hand:

```bash
ragenix -e secrets/cloud/ovh-application-key.age
ragenix -e secrets/cloud/ovh-application-secret.age
ragenix -e secrets/cloud/ovh-consumer-key.age
```

Generate the application key/secret at https://eu.api.ovh.com/createApp/,
then mint a consumer key scoped to that pair via OVH's token wizard —
Terraform cannot do this step itself. State lives outside the repo, in
`$XDG_STATE_HOME/os-nixcfg/terraform/cloud-C1`.

This only commissions the VPS. OS install goes through the same path as
VPS0/VPS1 below (`bootstrap-remote` + nixos-anywhere against the rescue
image, using the root password OVH emails on creation) — there is
intentionally no NixOS host wired up for C1 yet.

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

`VPS0` and `VPS1` are first-class NixOS hosts in this flake:

- `VPS0` is the Oracle Cloud VM.Standard.A1.Flex VPS in Mumbai. It is
  `aarch64-linux`, boots via UEFI GRUB installed as removable media, uses OCI
  DHCPv4 matched by MAC `02:00:17:05:eb:38`, and its disko layout targets the
  stable OCI by-id path
  `/dev/disk/by-id/scsi-36075f9bc9c73417586c6fd09a98be681`.
- `VPS1` is the Mumbai KVM VPS. It uses static private IPv4
  `10.10.10.51/24` and is reached for deploys through public NAT at
  `148.113.8.216:20041`.

`VPS1`'s disko layout targets `/dev/sda`; `VPS0` targets its OCI by-id
disk. For an Oracle Ubuntu image, bootstrap through the `ubuntu` user only after
confirming passwordless sudo works.

```bash
bootstrap-remote VPS0 --target ubuntu@80.225.249.202 --disk /dev/disk/by-id/scsi-36075f9bc9c73417586c6fd09a98be681 --check
bootstrap-remote VPS0 --target ubuntu@80.225.249.202 --disk /dev/disk/by-id/scsi-36075f9bc9c73417586c6fd09a98be681 --yes-destroy-disk

bootstrap-remote VPS1 --target root@148.113.8.216 --port 20041 --check
bootstrap-remote VPS1 --target root@148.113.8.216 --port 20041 --yes-destroy-disk
```

### Steady-state deploys

After bootstrap, use deploy-rs rather than `nixos-anywhere`. VPS system deploys
are intentionally system-only; deploy Home Manager separately through the
matching `*-home` node.

```bash
nix eval --raw .#nixosConfigurations.VPS0.config.system.build.toplevel.drvPath
nix eval --raw .#nixosConfigurations.VPS1.config.system.build.toplevel.drvPath
deploy .#VPS0 --dry-activate
deploy .#VPS1 --dry-activate
deploy .#VPS0
deploy .#VPS1
```

The VPS deploy nodes intentionally use `magicRollback = false`, so the recovery
plan for broken network/SSH changes is provider console or rescue mode. They
also use `remoteBuild = true` so Linux closures build on the VPSes instead of
the macOS workstation. Prefer local evaluation, dry activation, SSH smoke tests,
and one host at a time for risky VPS changes.

### Home Manager on VPSes

`VPS0` and `VPS1` expose standalone Home Manager configurations and
remote deploy-rs nodes. Deploy the NixOS system first so the normal user, SSH
keys, and agenix-backed passwords exist, then deploy the Home Manager profile as
that user.

```bash
nix eval --raw .#homeConfigurations.VPS0.activationPackage.drvPath
nix eval --raw .#homeConfigurations.VPS1.activationPackage.drvPath

deploy .#VPS0-home --dry-activate
deploy .#VPS1-home --dry-activate
deploy .#VPS0-home
deploy .#VPS1-home
```

Inside the devshell, `deploy-home VPS1 --dry-activate` is a shorthand for
`deploy .#VPS1-home --dry-activate`. The local `hms` and `hts` commands still
operate on the current machine's hostname and are not remote deploy wrappers.
