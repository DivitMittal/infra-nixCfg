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
│   ├── T1/                     # x86_64-linux HP t640 thin client (PXE/facter, see below)
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
└── netboot/                    # PXE/TFTP netboot images (RAM-resident, minimal)
    ├── enum.nix
    └── t1-netboot/              # x86_64-linux — facter report + install source for T1
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

### T1 (HP t640 thin client) — PXE/facter bootstrap

`T1` is a diskless-by-default thin client bootstrapped over PXE. Unlike the VPS
hosts, it has no known-good `hardware-configuration.nix`: hardware detection
comes from [nixos-facter](https://github.com/nix-community/nixos-facter)
(`hardware.facter.reportPath` in `hosts/nixos/T1/hardware.nix`, module
upstreamed into nixpkgs). `hosts/nixos/T1/facter.json` starts as a `{}`
placeholder — `hardware.facter.enable` stays off until it's replaced with a
real report, so evaluation is safe before you've touched the hardware.

`t1-netboot` (`.#nixosConfigurations.t1-netboot`) is a minimal PXE ramdisk
image — no desktop stack, just enough to run `nixos-facter` and act as the
`nixos-anywhere` install source. It is not a deploy-rs target; it is only ever
booted over the network.

1. Build the netboot artifacts and serve them from your TFTP/PXE server:

   ```bash
   nix build .#nixosConfigurations.t1-netboot.config.system.build.netbootRamdisk
   nix build .#nixosConfigurations.t1-netboot.config.system.build.kernel
   nix eval --raw .#nixosConfigurations.t1-netboot.config.system.build.netbootIpxeScript
   ```

2. PXE-boot the T640 into that image, then generate the real hardware report
   from within it:

   ```bash
   nixos-facter -o facter.json
   ```

   Copy the resulting `facter.json` back over
   `hosts/nixos/T1/facter.json` (e.g. `scp` it out, or serve it with a
   temporary `python3 -m http.server` and `curl` it from your workstation),
   replacing the `{}` placeholder, and commit it.

3. Confirm the target disk (`lsblk` from the PXE shell — `hosts/nixos/T1/disko.nix`
   assumes `/dev/sda`, adjust if the report says otherwise), then install for
   real from the still-PXE-booted host:

   ```bash
   bootstrap-remote T1 --target root@<pxe-booted-ip> --disk /dev/sda --check
   bootstrap-remote T1 --target root@<pxe-booted-ip> --disk /dev/sda --yes-destroy-disk
   ```

4. Once installed to local disk, T1 behaves like any other NixOS host —
   rebuild via `hts` locally, or wire it into `hosts/deploy.nix` for deploy-rs
   if you want remote deploys later.

### T1 as an edge router: multi-PPPoE OpenWrt/ImmortalWrt VM

Besides being a plain NixOS host, T1 also hosts a multi-PPPoE OpenWrt/
ImmortalWrt router as a VM, using T1's two (or more) physical NICs via
macvtap passthrough — one toward the ISP, one toward the home LAN. The
router VM itself terminates two PPPoE lines on the WAN side (each behind its
own `kmod-macvlan` MAC-VLAN device) and load-balances them with `mwan3`.

Why a hand-rolled `qemu-kvm` service instead of `microvm.nix` or Proxmox:
`microvm.nix` only boots **NixOS** guests (it turns `nixosConfigurations`
into disk images — no path for a foreign OS image), and Proxmox doesn't
offer a categorically different hypervisor tier (same KVM stack under Debian
plus a UI). Running `qemu-system-x86_64 -enable-kvm` directly gets the same
KVM acceleration with no framework mismatch. See
`hosts/nixos/T1/router-vm.nix` for the full systemd-networkd (macvtap
netdevs) + systemd service definition, and `flake/openwrt-images.nix` for
the image build (multi-PPPoE `uci-defaults` script, `mwan3` config,
packages).

**This is unverified on real hardware** — T1 isn't physically bootstrapped in
this branch, and the two physical NIC names in `router-vm.nix`
(`wanPhysIface` / `lanPhysIface`) are placeholders. Confirm the real names
via `ip link` and adjust before relying on this.

#### Building both images

```bash
nix build .#openwrt-t640-router
nix build .#immortalwrt-t640-router
```

Both are `x86_64-linux`-only outputs (the upstream ImageBuilders only support
an `x86_64-linux` builder host — build these from a Linux machine or a
Linux remote builder, not from macOS directly). `router-vm.nix` defaults to
booting `immortalwrt-t640-router`; switch to `openwrt-t640-router` by
changing the one `routerImagePackage` line.

#### VM service lifecycle

```bash
systemctl status openwrt-router-vm
systemctl restart openwrt-router-vm   # e.g. after switching the image package
journalctl -u openwrt-router-vm -f    # serial console output (qemu -serial mon:stdio)
```

`ExecStartPre` idempotently decompresses the current image package's
`.img.gz` into `/var/lib/openwrt-router/disk.img`, re-extracting only when
the source store path changes (tracked via a stamp file) — so restarting the
service doesn't re-run a fresh install every time. `Restart=always` keeps the
router VM up across crashes/kernel panics inside the guest.

#### First-boot: entering real PPPoE credentials

The image intentionally does **not** bake real PPPoE credentials into the
Nix store or this repo, matching this project's existing no-secrets-in-store
convention. `95-multi-pppoe`'s `uci-defaults` script wires up both PPPoE
lines with clearly-commented `CHANGEME` placeholder credentials, wan
firewall zone membership, and `mwan3` load-balancing — but you must enter the
real username/password for each line once, after the VM's first boot, via
LuCI (`Network > Interfaces > wan1`/`wan2` > Edit) or:

```sh
uci set network.wan1.username='...'
uci set network.wan1.password='...'
uci set network.wan2.username='...'
uci set network.wan2.password='...'
uci commit network && /etc/init.d/network reload
```

#### Switching mwan3 from balanced to failover

The default `mwan3` policy (`balanced`) weights both PPPoE lines equally
(`metric='1'`, `weight='3'` on both members). To switch to primary/backup
failover instead, give the backup line a higher metric than the primary
(mwan3 prefers lower metrics) — e.g. from the LuCI mwan3 app, or:

```sh
uci set mwan3.wan2_m1_w3.metric='2'   # wan1 stays primary at metric 1
uci commit mwan3
mwan3 restart
```

### Firmware/UEFI/BIOS updates (fwupd)

`services.fwupd` is enabled for T1 and T2 (real x86_64 UEFI hardware; see
`common/hosts/nixos/fwupd.nix` for why L2 and ASL1N are excluded). fwupd/LVFS
is the standard cross-vendor tool for this on Linux — Nix can declare the
daemon and its policy, but not a specific firmware version: firmware is
flashed into hardware, not a Nix-store artifact, so applying an update is
still an operator-run step after rebuilding:

```bash
fwupdmgr refresh       # pull latest LVFS metadata
fwupdmgr get-updates   # list what's available for this machine
fwupdmgr update        # apply
```

HP's LVFS coverage for the t640 thin-client line is effectively nonexistent
today (HP's LVFS presence concentrates on EliteBook/EliteDesk/Z-workstation
hardware), so `get-updates` reporting nothing on T1 is expected, not broken.

#### Applying firmware updates over PXE

`t1-netboot` also has `services.fwupd.enable = true;`, so you can check/apply
firmware from the PXE shell — useful before T1 has an installed system, or as
a rescue path afterwards. Important caveats:

- **"Over PXE" only gets you the environment.** The actual flash happens
  locally: fwupd stages a capsule, then on the _next_ reboot the T640's own
  firmware reads and applies it before the OS loads — nothing is written to
  the flash chip mid-session over the network.
- **Requires genuine UEFI-mode PXE boot end-to-end** (UEFI PXE ROM →
  `ipxe.efi` → kernel), not legacy BIOS PXE — otherwise there's no
  `efivarfs`/capsule runtime for fwupd to use. Whether your PXE/TFTP/DHCP
  server boots clients in UEFI mode is configured outside this flake (e.g. in
  `OS-nixCfg-openwrt-router`), not here.
- **No persistent mounts in netboot**, so fwupd can't auto-detect the ESP.
  Mount the target disk's real ESP at `/boot` manually first (matches T1's
  installed-system convention, so no `EspLocation` override is needed once
  it's mounted there):

  ```bash
  lsblk -f                        # find the ESP partition, e.g. /dev/sda1
  mount /dev/sda1 /boot
  fwupdmgr refresh
  fwupdmgr get-updates
  fwupdmgr update                 # stages the capsule; reboot to apply
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
