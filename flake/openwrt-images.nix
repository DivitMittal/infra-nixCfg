{inputs, ...}: {
  # Split of responsibilities for T640 (the OpenWrt/ImmortalWrt guest VM T1
  # boots — see hosts/nixos/T1/router-vm.nix):
  #   - imagebuilder (this file): produces a minimal bootable base image
  #     with the multi-PPPoE-related packages baked in, so a from-scratch
  #     image is immediately capable offline even before its first nuci
  #     deploy. It does not configure any UCI beyond the upstream
  #     ImageBuilder's own defaults.
  #   - nuci (flake/openwrt-t640.nix, hosts/openwrt/T640/): all ongoing
  #     declarative UCI config — the multi-PPPoE WAN, mwan3 policy, and the
  #     eth0→eth1 `lan` device fix — deployed post-boot the same way R1's
  #     config is (`nix run .#t640-router <target>`). This replaces what
  #     used to be a one-shot `uci-defaults` script baked into the image at
  #     build time. See hosts/README.md's "T1 as an edge router" section.
  #
  # Both astro/nix-openwrt-imagebuilder and its codgician/nix-immortalwrt-imagebuilder
  # fork only support x86_64-linux as the *builder's* host system — the
  # produced images are still for the x86/64 target regardless of what
  # system builds them.
  perSystem = {
    pkgs,
    lib,
    system,
    ...
  }:
    lib.attrsets.optionalAttrs (system == "x86_64-linux") (let
      commonArgs = {
        inherit pkgs;
        target = "x86";
        variant = "64";
        profile = "generic";
        # Baked into the image so a fresh boot is immediately capable
        # offline, ahead of the first `nix run .#t640-router` deploy. nuci's
        # `reconcile-apk-world` (hosts/openwrt/T640/modules/reconcile.nix)
        # only reconciles what's declared on top of whatever's already
        # installed — it doesn't need to be the thing that first gets these
        # onto a from-scratch image.
        packages = [
          "kmod-macvlan"
          "kmod-8021q" # not wired up by the declarative config yet, kept available for future VLAN-tagged WAN lines
          "mwan3"
          "luci-app-mwan3"
          "kmod-pppoe"
          "ppp-mod-pppoe"
        ];
      };
    in {
      packages = {
        openwrt-t640-router = inputs.openwrt-imagebuilder.lib.build commonArgs;
        immortalwrt-t640-router = inputs.immortalwrt-imagebuilder.lib.build commonArgs;
      };
    });
}
