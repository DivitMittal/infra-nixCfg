# Hosts Directory

Per-host configuration inventory for the fleet. Each platform directory
contains an `enum.nix` that enumerates the platform's hosts via `mkCfg`, plus
one subdirectory per host.

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
│   ├── _homelab/               # shared by T1/T2/T3/MON1 (base.nix, t640.nix)
│   ├── T1/                     # x86_64-linux HP t640 — edge router (ImmortalWrt VM)
│   ├── L1N/                    # x86_64-linux NixOS on L1 (T2-chip MacBook)
│   ├── T2/                     # x86_64-linux HP t640 — GUI + AI agent runner
│   ├── T3/                     # x86_64-linux HP t640 — home-lab services
│   ├── MON1/                   # x86_64-linux Lenovo S100 — monitoring
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
│   ├── l1n-iso/                # x86_64-linux installer for L1N (apple-t2)
│   └── as-iso/                 # aarch64-linux Apple Silicon
├── netboot/                    # PXE/TFTP netboot images (RAM-resident, minimal)
│   ├── enum.nix
│   └── t1-netboot/              # x86_64-linux — facter report + install source for T1
├── openwrt/                    # OpenWrt router configurations
│   ├── enum.nix
│   ├── R1/                      # historical/rollback router config (superseded by T640, no longer deployed)
│   │   ├── default.nix         # primary configuration
│   │   └── modules/            # auto-imported UCI modules
│   └── T640/                    # multi-PPPoE router VM guest running on T1 (hosts/nixos/T1/router-vm.nix)
│       ├── default.nix         # primary configuration
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
`infra-nixCfg-secrets/secrets/network/S1.age` (declared in that repo's
`secrets/manifest.nix`, same convention as every other secret consumed via
`common/home/age.nix`) using the `~/.ssh/agenix/id_ed25519` identity, and
exported as `TF_VAR_switch_s1_password` — it is never stored in this repo.
State lives outside the repo, in
`$XDG_STATE_HOME/os-nixcfg/terraform/switch-S1`.

`secrets/network/R1.age` is a symlink to `secrets/network/S1.age` — R1's OpenWrt
root password (set over SSH during `nix run .#openwrt-ont <target>`, see
`flake/openwrt.nix`) intentionally shares S1's admin password, one
ciphertext for both.

To create the secret itself (from inside `infra-nixCfg-secrets`, after entering
its devshell so `ragenix`/`RULES` are set up):

```bash
ragenix -e secrets/network/S1.age
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

`hts`, `hms` and `bootstrap` pick the flake attribute from `hostname`.

### L1N: one-time switch from the old `T2` name

The NixOS install on L1 (the T2-chip MacBook) was created as host `T2`.
That configuration is now `L1N` (`nixosConfigurations.L1N`,
`homeConfigurations.L1N`, installer `l1n-iso`). `T2` now belongs to an HP t640
k3s worker. Until L1's NixOS is switched once, its hostname is still `T2`, so a
plain `hts` would select the t640's config, with its disks, bootloader and k3s
role. `utils/common.sh` (`refuse_stale_l1n_hostname`) stops `hts`, `hms` and
`bootstrap` when the hostname is `T2` on Apple hardware.

Boot L1 into NixOS and run this from the repo root (this branch or master):

```bash
git pull
sudo nixos-rebuild build --flake .#L1N     # optional dry run; nothing is activated
sudo nixos-rebuild switch --flake .#L1N    # sets networking.hostName = "L1N"
hostname                                   # must print L1N
hms                                        # now selects homeConfigurations.L1N
```

If `hostname` still shows `T2` after the switch, reboot. After that, `hts` and
`hms` work as usual.

Secrets and keys:

- The hostname comes from `hostSpec.hostName` (`common/hosts/all/misc.nix`).
  `infra-nixCfg-secrets` has no entries keyed by `T2` or `L1N`. Its
  `homelab.disks` and `homelab.facter` cover only T1, T3 and MON1, so the
  rename changes no secret lookups for this machine.
- Home Manager agenix decrypts with the user key
  `~/.ssh/agenix/id_ed25519`, not a host key. That key must already be on L1's
  NixOS. Only VPS and k3s hosts use the system identity
  `/var/lib/agenix/id_ed25519`, and L1N is neither.
- `hosts/nixos/L1N/{disko,hardware}.nix` were moved unchanged from the old
  `T2`, so filesystems and the systemd-boot setup stay the same.
- `T2.lan` and SSH `known_hosts` entries for `T2` now mean the t640. Remove any
  stale MacBook entry on other machines (`ssh-keygen -R T2.lan`).

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
  DHCPv4 matched by its NIC's MAC, and its disko layout targets the stable OCI
  by-id path of its boot volume. Both values live in the private
  `infra-nixCfg-secrets` (`homelab.macs.VPS0`, `homelab.disks.VPS0`).
- `VPS1` is the Mumbai KVM VPS. It uses static private IPv4
  `10.10.10.51/24` and is reached for deploys through public NAT at
  `148.113.8.216:20041`.
- `VPS2` is the Germany KVM VPS. It is IPv6-only at
  `2a0e:97c0:3e3:34d::1/64` with gateway `fe80::1` on `eth0`.

`VPS1` and `VPS2` disko layouts target `/dev/sda`; `VPS0` targets its OCI by-id
disk. For an Oracle Ubuntu image, bootstrap through the `ubuntu` user only after
confirming passwordless sudo works.

```bash
# VPS0's by-id disk path: homelab.disks.VPS0 in infra-nixCfg-secrets
bootstrap-remote VPS0 --target ubuntu@80.225.249.202 --disk /dev/disk/by-id/scsi-<VPS0-volume-id> --check
bootstrap-remote VPS0 --target ubuntu@80.225.249.202 --disk /dev/disk/by-id/scsi-<VPS0-volume-id> --yes-destroy-disk

bootstrap-remote VPS1 --target root@148.113.8.216 --port 20041 --check
bootstrap-remote VPS1 --target root@148.113.8.216 --port 20041 --yes-destroy-disk

bootstrap-remote VPS2 --target root@2a0e:97c0:3e3:34d::1 --check
bootstrap-remote VPS2 --target root@2a0e:97c0:3e3:34d::1 --yes-destroy-disk
```

### Home lab: roles and bring-up order

| Host | Hardware                         | Role                                                 | LAN address                     |
| ---- | -------------------------------- | ---------------------------------------------------- | ------------------------------- |
| T1   | HP t640, lowest spec + USB 3 NIC | Edge router: ImmortalWrt VM (DMZ; PPPoE optional)    | host `192.168.2.3`, router `.1` |
| T2   | HP t640, highest spec            | Sway GUI + API-backed AI agents + k3s worker         | DHCP, `T2.lan`                  |
| T3   | HP t640, medium spec             | k3s server + RSSHub `:31200`, SSH portfolio `:30022` | DHCP, `T3.lan`                  |
| MON1 | Lenovo S100 (Atom, 2 GiB)        | Prometheus `:9090`, Grafana `:3000`, blackbox probes | DHCP, `MON1.lan`                |

All four share `hosts/nixos/_homelab/base.nix` (key-only SSH, node-exporter
for MON1 to scrape); the t640s also share `_homelab/t640.nix` (systemd-boot,
disko layout), and T2/T3 add `_homelab/agents.nix` (user lingering,
inotify/nofile limits, zram, systemd-oomd) so many API-backed agents can run
there instead of on L1; SSH in and start them in tmux/herdr. Every box installs the same way, using T1's steps below: PXE
into `t1-netboot` (it's a generic image, so any of them can boot it), run
`utils/collect_hw.sh`, then `bootstrap-remote <host>`. After that,
`deploy .#<host>`.

Host identifiers that shouldn't be public (the facter report with its
component serials, NIC MACs, disk by-id paths) go in the **private**
`infra-nixCfg-secrets` under `homelab` (`flake/homelab.nix` there, with
reports at `homelab/facter/<host>.json`), and this repo reads them from
`inputs.infra-nixCfg-secrets.homelab`. Hosts without a report fall back to
`_homelab/facter-placeholder.json` (`{}`, facter off).

Bring them up in this order, because each step needs the one before it:

1. **T1** — until the router is up, nothing else gets a `.lan` name or
   internet. On R0, set the DMZ host to `192.168.1.254`, then run
   `nix run .#t640-router root@192.168.2.1` from a machine wired to S1. That
   needs `secrets/network/T640.age` (the generated root password) in
   `infra-nixCfg-secrets`; see "WAN modes" for later switching to PPPoE.
2. **MON1** — so you can watch the rest come up. The Grafana admin password is
   generated on first start: `ssh root@MON1.lan cat /var/lib/grafana-secrets/admin-password`.
3. **T3**, then **T2** — the k3s server must be available before its worker
   joins. See [the k3s runbook](../docs/homelab-k3s.md) for token provisioning,
   workload placement, storage, and backup requirements. T1 stays outside
   Kubernetes so cluster workloads cannot disrupt routing.

S1 ports 1–4 carry T3, T1 (router), MON1 and T2; port 5 uplinks the
unmanaged switch S2, which carries the workstations (L1, M1). The port map was
measured from S1's per-port counters on 2026-11-19, so re-measure after
recabling. Neither switch is fully monitorable: S1 (Easy Smart) has no SNMP,
so MON1 only pings it and probes its web UI, and S2 can't be monitored at all.

### T1 (HP t640 thin client) — PXE/facter bootstrap

`T1` is a diskless-by-default thin client bootstrapped over PXE. Unlike the VPS
hosts, it has no known-good `hardware-configuration.nix`: hardware detection
comes from [nixos-facter](https://github.com/nix-community/nixos-facter)
(`hardware.facter.reportPath` in `hosts/nixos/_homelab/base.nix`, module
upstreamed into nixpkgs). Until a host's report is in
`infra-nixCfg-secrets` (`homelab.facter.<host>`), it gets a `{}` placeholder
and `hardware.facter.enable` stays off, so evaluation is safe before you've
touched the hardware.

`t1-netboot` (`.#nixosConfigurations.t1-netboot`) is a minimal PXE ramdisk
image — no desktop stack, just enough to run `nixos-facter` and act as the
`nixos-anywhere` install source. It is not a deploy-rs target; it is only ever
booted over the network.

1. Serve `t1-netboot` over PXE. It's the same image for every home-lab box,
   with sshd and your key already in it, so the target needs no console.

   **From a Mac** (no Linux box on the LAN yet). CI builds the bundle, since
   a Mac can't build x86_64-linux. Get the newest one:

   ```bash
   gh run download -R DivitMittal/infra-nixCfg -n t1-netboot-bundle -D ~/t1-netboot \
     "$(gh run list -R DivitMittal/infra-nixCfg -w netboot-build.yml -s success -L 1 --json databaseId -q '.[0].databaseId')"
   ```

   _Direct cable (recommended):_ the Mac's USB-C Ethernet adapter goes
   straight to the target's **onboard** port, and the target's USB adapter
   goes to a GN XPON LAN port for internet (the installer downloads packages).
   Find the adapter's interface name with `networksetup -listallhardwareports`.

   ```bash
   sudo nix run .#pxe-serve-darwin -- ~/t1-netboot --direct en7   # your adapter's name
   ```

   The Mac takes `10.42.0.1` on that cable and hands the target a
   `10.42.0.1xx` lease with **no gateway or DNS**, so the target's internet
   stays on its USB adapter. The dnsmasq log shows the lease
   (`DHCPACK(en7) 10.42.0.1xx ...`); SSH to that address.

   _Shared LAN:_ with the Mac and target on the same network (for example the
   Mac on the GN XPON's Wi-Fi and the target on a GN XPON LAN port), run it
   without `--direct`. dnsmasq is then **proxy-DHCP**: the GN XPON keeps
   handing out addresses and dnsmasq only answers PXE. This fails if the GN
   XPON doesn't pass broadcasts between Wi-Fi and LAN.

   Either way, TFTP carries only the small iPXE binary, and darkhttpd on
   `:8080` serves the kernel and initrd. If macOS asks whether to accept
   incoming connections, allow them. Ctrl-C once the target has booted.

   **From a Linux box** on the target's network: `sudo nix run .#pxe-serve`
   (pixiecore, builds everything locally).

2. PXE-boot the T640 into that image, then collect its hardware report,
   disks and NICs from the workstation (read-only):

   ```bash
   ssh root@<target-ip> 'bash -s' < utils/collect_hw.sh > <host>-hw.txt
   ssh root@<target-ip> cat /tmp/facter.json > <host>-facter.json
   ```

   Add the report to **`infra-nixCfg-secrets`** as
   `homelab/facter/<host>.json`, register it under `homelab.facter` in that
   repo's `flake/homelab.nix` (with the host's NIC MACs and disk by-id
   path), then `nix flake update infra-nixCfg-secrets` here. Don't commit it
   to this public repo.

3. Confirm the target disk (`lsblk` from the PXE shell — `hosts/nixos/_homelab/t640.nix`
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
netdevs) + systemd service definition.

The router VM's config is split the same way as everything else in this
repo:

- **Imagebuilder** (`flake/openwrt-images.nix`) builds a minimal bootable
  base image — `openwrt-t640-router` / `immortalwrt-t640-router` — with the
  multi-PPPoE-related packages (`kmod-macvlan`, `mwan3`, `luci-app-mwan3`,
  `kmod-pppoe`, `ppp-mod-pppoe`, ...) baked in, so a fresh boot is
  immediately capable offline. It does not configure any UCI itself.
- **nuci** (`hosts/openwrt/T640/`, deployed via `flake/openwrt-t640.nix`)
  owns all ongoing declarative config — the multi-PPPoE WAN interfaces,
  `mwan3` balanced policy, and moving the LAN to `192.168.2.1` —
  pushed post-boot the same way R1's config is (`nix run .#t640-router
<target>`, see `hosts/openwrt/R1`/`flake/openwrt.nix` for the pattern this
  mirrors). This replaced an earlier one-shot `uci-defaults` script that
  used to be baked into the image at build time.

The VM attaches the LAN NIC first, so the guest sees `eth0` = LAN and `eth1` =
WAN, which matches a stock x86 image. The image bakes in one setting, the LAN
address `192.168.2.1` (a `uci-defaults` file in `flake/openwrt-images.nix`).
A stock `192.168.1.1` LAN would overlap R0's `192.168.1.0/24` on the WAN side
in DMZ mode, so even a fresh guest answers at `192.168.2.1`. The T1 host keeps its own LAN address,
`192.168.2.3`, on a `lan-host` macvlan, so you can still SSH in while the
router guest is down.

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

#### Entering real PPPoE credentials

The declarative UCI config (`hosts/openwrt/T640/modules/network.nix`)
intentionally does **not** bake real PPPoE credentials into the Nix store or
this repo, matching this project's existing no-secrets-in-store convention
— it only ever contains clearly-commented `CHANGEME` placeholders.

Real per-line credentials are injected the same way R1's root password and
Wi-Fi-backup PSK are: two agenix-encrypted secrets in `infra-nixCfg-secrets`
(`secrets/network/T640-wan1.age`, `secrets/network/T640-wan2.age`, each
containing `username\npassword`), decrypted at deploy time and written over
SSH to `/etc/nuci/wan{1,2}-credentials` by `flake/openwrt-t640.nix`'s
`set_wan_credentials` step. A `nuci` reconcile.d hook
(`hosts/openwrt/T640/modules/wan-credentials.nix`) then applies them to live
UCI on every `nix run .#t640-router <target>` deploy — no manual LuCI/`uci
set` step needed once those two secrets exist. Create them first (from
inside `infra-nixCfg-secrets`, in its devshell):

```bash
ragenix -e secrets/network/T640-wan1.age
ragenix -e secrets/network/T640-wan2.age
```

If you'd rather enter credentials manually instead (e.g. before the secrets
exist), the same fields are reachable via LuCI (`Network > Interfaces >
wan1`/`wan2` > Edit) or:

```sh
uci set network.wan1.username='...'
uci set network.wan1.password='...'
uci set network.wan2.username='...'
uci set network.wan2.password='...'
uci commit network && /etc/init.d/network reload
```

— but the reconcile.d hook will overwrite these on the next deploy once the
secrets exist, since nuci reconciles the whole declared config on every run.

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

#### WAN modes: DMZ (default) and PPPoE

`hosts/openwrt/T640` takes a `wanMode`, the same pattern R1 used:

| Mode    | R0 setup                              | WAN on the T640 guest                            | Deploy                                 |
| ------- | ------------------------------------- | ------------------------------------------------ | -------------------------------------- |
| `dmz`   | Router mode, DMZ host `192.168.1.254` | static `192.168.1.254/24`, gateway `192.168.1.1` | `nix run .#t640-router <target>`       |
| `pppoe` | Bridge mode                           | two PPPoE lines balanced by mwan3                | `nix run .#t640-router-pppoe <target>` |

DMZ mode needs only `secrets/network/T640.age`. In this mode, R0 still
NATs, so the home LAN sits behind double NAT (fine for normal use; port
forwards must be opened on the T640 only, since R0's DMZ forwards everything).
PPPoE mode also needs the two `T640-wan{1,2}.age` credentials above. Deploying
one mode over the other converts the router declaratively.

### T1 Tailscale (subnet router)

T1 runs tailscaled on the NixOS host and advertises `192.168.2.0/24`, with
subnet SNAT enabled, local DNS preserved and no exit node. The daemon stays
outside the router VM, and both networkd and NetworkManager leave its
interface unmanaged. Its optional enrollment key is
`secrets/homelab/T1-tailscale.age` in the private secrets input.

The personal tailnet policy, router tag, route auto-approval and CI identity
are declared through Terranix/OpenTofu. Follow [the tailnet setup guide](../docs/tailscale.md)
for existing-policy adoption, encrypted state, enrollment and verification.
Linux remote clients must enable subnet-route acceptance. CI is granted only
TCP access to the T3 cache, not LAN management access.

### Firmware/UEFI/BIOS updates (fwupd)

`services.fwupd` is enabled for T1-T3 and L1N (real x86_64 UEFI hardware; see
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

### SSH into L1 from the rest of the fleet

`hosts/darwin/L1/services/ssh.nix` enables macOS Remote Login on L1 and
authorizes the same shared pubkey every home-lab box already trusts
(`hosts/nixos/_homelab/base.nix`). Any box that holds the matching private
key — `~/.ssh/agenix/id_ed25519`, present on every `homeConfigurations.*`
host per `common/home/age.nix` — can reach it:

```bash
ssh div@192.168.2.4   # from T2, T3, L2 (NixOS boot), L1N, M1, WSL, colima
```

L2's **Windows** boot slot (`vanee`) needs that same private key copied into
its profile first, since nix-win can't deploy it without committing it to
the store. Run once, from a box that already holds the key:

```bash
utils/provision_l2_ssh_key.sh
```

`hosts/win/L2/main.nix` then declares a `ssh L1` alias via `win.files`, so
`vanee@L2` only needs `ssh L1` once the key exists.

### Desk input sharing (Lan Mouse)

L1 (`192.168.2.4`, wired USB adapter) is the centre of the desk. L2 Windows
(`192.168.2.6`) is above it; T2 (`192.168.2.171`) is to its left. Move back
through L2's bottom edge or T2's right edge to return to L1. The emergency
release shortcut on all three machines is **Ctrl+Shift+Esc**.

`lib/lan-mouse.nix` declares the peers, layout, certificate fingerprint
allowlists and Windows task settings for all three machines.
`home/tools/hid/lan-mouse.nix` consumes those settings and manages desktop
startup. Linux builds enable layer-shell capture and
wlroots emulation even though the GTK frontend is disabled. T2 requires a
logged-in Sway session; Lan Mouse starts with `sway-session.target`, not at the
login greeter. L1 starts its LaunchAgent at login. Home Manager installs and
registers `~/Applications/Lan Mouse Desktop.app` and associates the agent with
that app so macOS can identify it for Local Network privacy. Grant the app
Accessibility and Local Network access in System Settings; those user grants
are not managed by Nix. Other hosts do not join this desk automatically.

T2 enables `programs.ydotool` to provide a virtual keyboard when no physical
keyboard is attached. Lan Mouse's wlroots backend needs that keyboard's
keymap to initialize. The ydotool socket remains restricted to its service
group; no desktop user membership is required for this purpose.

The text greeter runs before Lan Mouse, so the Mac's shared keyboard cannot
type into it. With no physical keyboard attached to T2, run
`./utils/t2_console_login.sh` in a terminal on L1. Enter the existing `div`
password at its hidden SSH prompt; the helper types it through T2's virtual
keyboard, then Sway starts the normal Lan Mouse service. The password is not
stored or passed as a process argument. This requires L1's agenix SSH key and
does not enable automatic login or change the password.

L2's Windows boot gets its part through nix-win (`win-deploy L2`), from
`hosts/win/L2/lan-mouse.nix`. That module installs the v0.11.0 Windows release
to `%LOCALAPPDATA%\lan-mouse\bin` and writes
`%LOCALAPPDATA%\lan-mouse\config.toml` from `lib/lan-mouse.nix`. Inspect the
settings with `nix eval --json .#lanMouse.windows.L2`.

`hosts/win/L2/desk.nix` turns each `desk.daemons` entry (Lan Mouse and
UniClipboard) into DSC resources: a ComputerManagementDsc `ScheduledTask`
that starts the daemon in vanee's interactive session at login, a
NetworkingDsc `Firewall` rule allowing inbound traffic from the local subnet,
and a `Script` resource that deletes the Block rules Windows records when its
network prompt is dismissed. L2's LAN is classed Public, so without those rules
each daemon would raise that prompt. The task launches the daemon through
`conhost.exe --headless`, so no console window opens; Windows Terminal ignores
`powershell -WindowStyle Hidden`. Each deploy restarts both tasks. The login
task only runs at logon, so a daemon that exhausts its restarts stays down
until the next login or `Start-ScheduledTask 'Lan Mouse'`. Its daemon log is
`%LOCALAPPDATA%\lan-mouse\daemon.log`; L1 logs to `~/.cache/lan-mouse.err.log`.
T2 logs are available through `journalctl --user -u lan-mouse`.

Use `lan-mouse cli list` on each machine to check active peer directions.
Connection logs and a pointer/keyboard handoff establish actual connectivity;
an active peer entry alone does not. On L1, if `lan-mouse.err.log` says
`accessibility permission is required`, the agent can be running with its
peers marked active but cannot capture the pointer. In System Settings →
Privacy & Security → Accessibility, enable the installed
`~/Applications/Lan Mouse Desktop.app` (use **+** to add it if missing). If
the entry is already enabled but capture is still denied, remove it and add
the installed bundle again. Then restart just the Lan Mouse agent:

```bash
launchctl kickstart -k "gui/$(id -u)/org.nix-community.home.lan-mouse"
```

Check the new log entries for `using capture backend: macos`, then push the
pointer through L1's top edge to test L2. If capture starts but L2 does not
respond, check the app's Local Network permission and L2's daemon log for a
connection attempt at the time of the test.

Certificate replacement requires updating
the public fingerprint in `lib/lan-mouse.nix` and reapplying the affected
configurations. Private PEM keys stay on their respective machines.

### Desk clipboard sharing (UniClipboard)

L1, T2 and L2's Windows boot share one encrypted UniClipboard space.
`home/tools/hid/uniclipboard.nix` runs `uniclip run` as a LaunchAgent on L1
and as a user service bound to `sway-session.target` on T2, so T2 only syncs
while its Sway session runs. On L1 it also retires the LaunchAgent that
`uniclip service start` writes, which pins a single store path.
`hosts/win/L2/uniclipboard.nix` ships the Windows CLI through nix-win to
`%LOCALAPPDATA%\uniclipboard\bin` and declares its `desk.daemons` entry, so
it gets the same task and firewall handling as Lan Mouse. Its log is
`%LOCALAPPDATA%\uniclipboard\daemon.log`. Keep other `win.files` for L2 off
the `appdata-local` root (use `home` with an `AppData/Local/...` path):
nix-win silently drops `win.packages` on a root that `win.files` also uses.

Membership lives in each device's profile, not in Nix. L1 sponsors the space;
its passphrase is in L1's login Keychain under `uniclipboard-space`. To add a
device, run `uniclip space invite` on L1, then on the new device:

```sh
uniclip space join --code <code> --passphrase '<passphrase>' --device-name <name>
```

Read the passphrase on L1 with `security find-generic-password -s
uniclipboard-space -w`. Check the result with `uniclip member list` on
both sides, and a round trip with `uniclip send --text test` and `uniclip get`.
