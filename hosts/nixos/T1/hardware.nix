{lib, ...}: {
  # nixos-facter hardware report (nix-community/nixos-facter, module upstreamed
  # into nixpkgs at nixos/modules/hardware/facter). Derives kernel
  # modules/boot/peripheral config from the report instead of a hand-written
  # hardware-configuration.nix.
  #
  # facter.json here is a placeholder ({}), which leaves hardware.facter.enable
  # off (it defaults to `report != {}`) until replaced with a real report. To
  # generate one: PXE-boot this host into `t1-netboot`, run
  # `nixos-facter -o facter.json` there, and copy the result over this file.
  # See hosts/README.md for the full bootstrap sequence.
  hardware.facter.reportPath = ./facter.json;

  # AMD Ryzen Embedded (t640 SoC) — safe default until facter.json supersedes it.
  boot.kernelModules = ["kvm-amd"];

  networking.useDHCP = lib.mkDefault true;
}
