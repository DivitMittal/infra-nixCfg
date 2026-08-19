# T1's second role: host the multi-PPPoE OpenWrt/ImmortalWrt router as a
# hand-rolled qemu-kvm VM (see hosts/README.md for the full write-up and
# `flake/openwrt-images.nix` for the image build). This is genuinely new
# territory for this repo — no existing systemd-networkd/qemu precedent to
# reuse — so it's flagged here for extra review scrutiny, same as
# `disko.nix`'s "confirm before relying on it" note below.
#
# `microvm.nix` only runs NixOS guests (it builds `nixosConfigurations` into
# disk images), so it has no path for booting a foreign OS image like
# OpenWrt/ImmortalWrt. Proxmox doesn't offer a categorically different
# hypervisor tier either (same KVM stack under Debian + a UI). Hence: run the
# built image directly via `qemu-system-x86_64 -enable-kvm`, same KVM
# acceleration as any other option, no framework mismatch.
{
  self,
  pkgs,
  lib,
  ...
}: let
  # --- Placeholder physical NIC names -------------------------------------
  # T1 has two+ NICs (onboard + add-in) but isn't physically bootstrapped yet
  # in this branch, so the real interface names are unknown. CONFIRM the
  # actual names via `ip link` (or `lsblk`-equivalent `ip -br link show`) once
  # the hardware is in hand, same spirit as `disko.nix`'s "confirm the exact
  # device via `lsblk`" note — adjust before relying on this module.
  wanPhysIface = "enp1s0"; # WAN-facing (ISP) physical NIC — CONFIRM via `ip link`
  lanPhysIface = "enp2s0"; # LAN-facing (home network) physical NIC — CONFIRM via `ip link`

  wanMacvtap = "wan-mvtap";
  lanMacvtap = "lan-mvtap";

  # VM defaults to ImmortalWrt (more actively maintained fork). Both
  # `openwrt-t640-router` and `immortalwrt-t640-router` are always built by
  # flake/openwrt-images.nix — switching images is this one line.
  routerImagePackage = self.packages.${pkgs.stdenv.hostPlatform.system}.immortalwrt-t640-router;

  stateDir = "/var/lib/openwrt-router";
  diskImage = "${stateDir}/disk.img";
  # Stamp file records which store path the current disk.img was extracted
  # from, so ExecStartPre only re-extracts when the built image actually
  # changes (e.g. after switching openwrt-t640-router <-> immortalwrt-t640-router,
  # or a rebuild with different packages/uci-defaults).
  sourceStamp = "${stateDir}/disk.img.source";

  prepareDiskScript = pkgs.writeShellScript "openwrt-router-vm-prepare-disk" ''
    set -euo pipefail
    mkdir -p ${lib.escapeShellArg stateDir}

    shopt -s nullglob
    imgGz=(${routerImagePackage}/*.img.gz)
    shopt -u nullglob
    if [ "''${#imgGz[@]}" -eq 0 ]; then
      echo "openwrt-router-vm: no *.img.gz found in ${routerImagePackage}" >&2
      exit 1
    fi
    src="''${imgGz[0]}"

    if [ ! -f ${lib.escapeShellArg sourceStamp} ] || [ "$(cat ${lib.escapeShellArg sourceStamp})" != "$src" ]; then
      ${pkgs.gzip}/bin/gzip -dc "$src" > ${lib.escapeShellArg diskImage}.tmp
      mv ${lib.escapeShellArg diskImage}.tmp ${lib.escapeShellArg diskImage}
      echo "$src" > ${lib.escapeShellArg sourceStamp}
    fi
  '';

  # macvtap character device nodes are /dev/tap<ifindex> — the ifindex is
  # assigned dynamically by the kernel, so it must be resolved at service
  # start (not hardcoded), then opened as an fd and handed to qemu's
  # `-netdev tap,fd=...` (this is the same technique libvirt uses for macvtap
  # passthrough networking).
  startScript = pkgs.writeShellScript "openwrt-router-vm-start" ''
    set -euo pipefail

    wanIfindex=$(cat /sys/class/net/${wanMacvtap}/ifindex)
    lanIfindex=$(cat /sys/class/net/${lanMacvtap}/ifindex)

    exec {wanFd}<>"/dev/tap$wanIfindex"
    exec {lanFd}<>"/dev/tap$lanIfindex"

    exec ${pkgs.qemu_kvm}/bin/qemu-system-x86_64 \
      -enable-kvm \
      -M microvm \
      -m 1024 \
      -smp 2 \
      -netdev tap,id=wan,fd=$wanFd \
      -device virtio-net-pci,netdev=wan \
      -netdev tap,id=lan,fd=$lanFd \
      -device virtio-net-pci,netdev=lan \
      -drive file=${lib.escapeShellArg diskImage},if=virtio,format=raw \
      -nographic \
      -serial mon:stdio
  '';
in {
  boot.kernelModules = ["tap"];

  # macvtap netdevs: one per physical NIC, bridged so the guest sees the
  # physical link directly (matching MAC-level visibility the ISP's PPPoE
  # session tracking and any home-LAN DHCP/ARP expects).
  systemd.network = {
    enable = true;
    netdevs = {
      "25-${wanMacvtap}" = {
        netdevConfig = {
          Name = wanMacvtap;
          Kind = "macvtap";
        };
        macvtapConfig.Mode = "bridge";
      };
      "25-${lanMacvtap}" = {
        netdevConfig = {
          Name = lanMacvtap;
          Kind = "macvtap";
        };
        macvtapConfig.Mode = "bridge";
      };
    };
    networks = {
      "25-${wanPhysIface}" = {
        matchConfig.Name = wanPhysIface;
        networkConfig.MACVTAP = [wanMacvtap];
      };
      "25-${lanPhysIface}" = {
        matchConfig.Name = lanPhysIface;
        networkConfig.MACVTAP = [lanMacvtap];
      };
    };
  };

  networking = {
    # NetworkManager is enabled by default (common/hosts/nixos/networking.nix)
    # and must not fight systemd-networkd over the physical uplinks or the
    # macvtap devices created from them.
    networkmanager.unmanaged = [
      "interface-name:${wanPhysIface}"
      "interface-name:${lanPhysIface}"
      "interface-name:${wanMacvtap}"
      "interface-name:${lanMacvtap}"
    ];

    # T1's hardware.nix defaults networking.useDHCP to true (legacy scripted
    # dhcpcd, applies to any interface without explicit config). Exclude
    # these four so only systemd-networkd manages them — the physical
    # uplinks are passed through to the guest and shouldn't get a host-side
    # DHCP lease, and the macvtap devices are unaddressed passthrough taps.
    interfaces = lib.genAttrs [wanPhysIface lanPhysIface wanMacvtap lanMacvtap] (_: {useDHCP = false;});

    # Silence the nixpkgs networking module's own recommendation: with
    # `systemd.network.enable = true` (needed for the macvtap netdevs above)
    # and the global `networking.useDHCP = true` default (T1's hardware.nix),
    # networkd becomes the authoritative backend for any interface
    # NetworkManager doesn't manage, instead of leaving that ambiguous
    # between networkd and legacy dhcpcd.
    useNetworkd = true;
  };

  systemd.services.openwrt-router-vm = {
    description = "OpenWrt/ImmortalWrt multi-PPPoE router VM (macvtap passthrough, hand-rolled qemu-kvm)";
    after = ["network.target" "systemd-networkd.service"];
    wants = ["systemd-networkd.service"];
    wantedBy = ["multi-user.target"];

    # Don't crash-loop forever on hardware without KVM (e.g. a nested-eval
    # sanity check off T1's real hardware).
    unitConfig.ConditionPathExists = "/dev/kvm";

    serviceConfig = {
      Type = "simple";
      ExecStartPre = prepareDiskScript;
      ExecStart = startScript;
      Restart = "always";
      RestartSec = "5s";
    };
  };
}
