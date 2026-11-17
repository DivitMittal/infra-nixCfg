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
  # --- Physical NICs, pinned by MAC (from T1's facter report) -------------
  # The kernel's names for USB NICs encode the USB port path
  # (enp3s0f3u4u2), so moving the adapter would rename it. These .link
  # files give both NICs fixed names by MAC instead.
  wanPhysIface = "wan0"; # USB RTL8153 adapter, cabled to the GN XPON
  wanMac = "00:e0:4c:4d:2e:78";
  lanPhysIface = "lan0"; # onboard Realtek (r8169), cabled to S1
  lanMac = "84:3a:5b:17:32:0a";

  wanMacvtap = "wan-mvtap";
  lanMacvtap = "lan-mvtap";

  # The host's own foothold on the home LAN. Both physical NICs are handed to
  # the guest, so without this T1 would be unreachable (no SSH, no RSSHub).
  # A macvlan and a macvtap in bridge mode on the same parent can reach each
  # other, so the host talks to the router guest through the LAN NIC.
  # Static rather than DHCP so T1 stays reachable while the guest is down.
  lanHostIface = "lan-host";
  lanHostAddress = "192.168.2.3/24";
  routerLanAddress = "192.168.2.1"; # T640 guest, hosts/openwrt/T640/modules/network.nix

  # VM defaults to ImmortalWrt (more actively maintained fork). Both
  # `openwrt-t640-router` and `immortalwrt-t640-router` are always built by
  # flake/openwrt-images.nix — switching images is this one line.
  routerImagePackage = self.packages.${pkgs.stdenv.hostPlatform.system}.immortalwrt-t640-router;

  stateDir = "/var/lib/openwrt-router";
  diskImage = "${stateDir}/disk.img";
  # Stamp file records which store path the current disk.img was extracted
  # from, so ExecStartPre only re-extracts when the built image actually
  # changes (e.g. after switching openwrt-t640-router <-> immortalwrt-t640-router,
  # or a rebuild with a different baked-in package set — see
  # flake/openwrt-images.nix; ongoing UCI config is deployed separately via
  # `nix run .#t640-router`, not baked into the image).
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

    # q35, not microvm: microvm has no PCI bus by default and its qboot
    # firmware can't be relied on to boot a raw OpenWrt disk image.
    #
    # LAN is attached first so the guest enumerates it as eth0 and WAN as
    # eth1, the stock generic-x86 layout (br-lan on eth0, wan on eth1), so a
    # fresh image is reachable on the LAN before nuci has touched it. Each
    # NIC reuses its macvtap's MAC: macvtap drops frames for any other MAC.
    exec ${pkgs.qemu_kvm}/bin/qemu-system-x86_64 \
      -enable-kvm \
      -M q35 \
      -cpu host \
      -m 1024 \
      -smp 2 \
      -netdev tap,id=lan,fd=$lanFd \
      -device virtio-net-pci,netdev=lan,mac=$(cat /sys/class/net/${lanMacvtap}/address) \
      -netdev tap,id=wan,fd=$wanFd \
      -device virtio-net-pci,netdev=wan,mac=$(cat /sys/class/net/${wanMacvtap}/address) \
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
    links = {
      "10-${wanPhysIface}" = {
        matchConfig.PermanentMACAddress = wanMac;
        linkConfig.Name = wanPhysIface;
      };
      "10-${lanPhysIface}" = {
        matchConfig.PermanentMACAddress = lanMac;
        linkConfig.Name = lanPhysIface;
      };
    };
    netdevs = {
      "25-${wanMacvtap}" = {
        netdevConfig = {
          Name = wanMacvtap;
          Kind = "macvtap";
        };
        # passthru, not bridge: a bridge-mode macvtap only accepts frames for
        # its own MAC, so the guest's per-line PPPoE macvlans (distinct MACs,
        # hosts/openwrt/T640/modules/network.nix) would never see replies.
        # passthru hands the guest the whole NIC; the host has no WAN presence.
        macvtapConfig.Mode = "passthru";
      };
      "25-${lanMacvtap}" = {
        netdevConfig = {
          Name = lanMacvtap;
          Kind = "macvtap";
        };
        macvtapConfig.Mode = "bridge";
      };
      "25-${lanHostIface}" = {
        netdevConfig = {
          Name = lanHostIface;
          Kind = "macvlan";
        };
        macvlanConfig.Mode = "bridge";
      };
    };
    networks = {
      "25-${wanPhysIface}" = {
        matchConfig.Name = wanPhysIface;
        networkConfig.MACVTAP = [wanMacvtap];
      };
      "25-${lanPhysIface}" = {
        matchConfig.Name = lanPhysIface;
        networkConfig = {
          MACVTAP = [lanMacvtap];
          MACVLAN = [lanHostIface];
        };
      };
      "25-${lanHostIface}" = {
        matchConfig.Name = lanHostIface;
        address = [lanHostAddress];
        gateway = [routerLanAddress];
        dns = [routerLanAddress];
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
      "interface-name:${lanHostIface}"
    ];

    # T1's hardware.nix defaults networking.useDHCP to true (legacy scripted
    # dhcpcd, applies to any interface without explicit config). Exclude
    # these four so only systemd-networkd manages them — the physical
    # uplinks are passed through to the guest and shouldn't get a host-side
    # DHCP lease, and the macvtap devices are unaddressed passthrough taps.
    interfaces = lib.genAttrs [wanPhysIface lanPhysIface wanMacvtap lanMacvtap lanHostIface] (_: {useDHCP = false;});

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
