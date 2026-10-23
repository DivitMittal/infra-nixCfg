{
  lib,
  self,
  ...
}: {
  # PXE server for the netboot class (hosts/netboot/*): wraps pixiecore in
  # proxy-DHCP mode, so the existing LAN router keeps handing out leases and
  # pixiecore only answers the PXE part (TFTP ipxe.efi/undionly.kpxe chain ->
  # HTTP kernel+initrd). Works for both UEFI and legacy PXE clients.
  #
  # Linux-only (pixiecore needs raw DHCP/TFTP sockets); run it as root on any
  # Linux box on the same L2 segment as the target:
  #
  #   sudo nix run .#pxe-serve            # serves t1-netboot
  #   sudo nix run .#pxe-serve -- --debug # extra pixiecore flags pass through
  #
  # Ports to allow on that box: UDP 67, 69, 4011 and TCP 64172.
  #
  # pixiecore boot mode answers *any* PXE client on the segment. The image is
  # RAM-only and never touches disk on its own, but only power on / F12 the
  # one machine you mean to boot while this is running.
  perSystem = {pkgs, ...}: let
    inherit (self.nixosConfigurations.t1-netboot) config;
    inherit (config.system) build;
    cmdline = "init=${build.toplevel}/init ${toString config.boot.kernelParams}";

    command = pkgs.writeShellScript "pxe-serve" ''
      set -eu
      if [ "$(id -u)" -ne 0 ]; then
        echo "pxe-serve: pixiecore needs root (DHCP/TFTP ports); re-run with sudo" >&2
        exit 1
      fi
      exec ${lib.getExe pkgs.pixiecore} boot \
        ${build.kernel}/${config.system.boot.loader.kernelFile} ${build.netbootRamdisk}/initrd \
        --cmdline ${lib.escapeShellArg cmdline} \
        --dhcp-no-bind \
        --port 64172 --status-port 64172 \
        "$@"
    '';
  in {
    apps = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      pxe-serve = {
        type = "app";
        program = toString command;
      };
    };
  };
}
