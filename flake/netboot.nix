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

    ## Serving from macOS (no Linux box on the LAN yet)
    # A Mac can't build these x86_64-linux artifacts, so CI builds them into
    # one directory (`netboot-bundle`, uploaded by .github/workflows/
    # netboot-build.yml) and `pxe-serve-darwin` serves that directory.
    httpPort = 8080;

    # iPXE runs this right after the firmware's PXE ROM chainloads it. It asks
    # for DHCP again and fetches the real boot script over HTTP from whichever
    # machine answered as proxy-DHCP (the Mac), so the ~hundreds-of-MB initrd
    # never goes over TFTP. TFTP is only the fallback.
    ipxeEmbed = pkgs.writeText "t1-netboot-embed.ipxe" ''
      #!ipxe
      :retry
      dhcp || goto wait
      set srv ''${proxydhcp/next-server}
      isset ''${srv} || set srv ''${next-server}
      echo t1-netboot: fetching boot script from ''${srv}
      chain http://''${srv}:${toString httpPort}/netboot.ipxe || chain tftp://''${srv}/netboot.ipxe || goto wait
      :wait
      echo t1-netboot: no boot script yet, retrying in 5s (Ctrl-B for a shell)
      sleep 5
      goto retry
    '';

    # Relative names resolve against the script's own URL, so the kernel and
    # initrd come from the same HTTP server.
    bootScript = pkgs.writeText "netboot.ipxe" ''
      #!ipxe
      kernel bzImage ${cmdline} initrd=initrd
      initrd initrd
      boot
    '';

    netbootBundle = pkgs.runCommand "t1-netboot-bundle" {} ''
      mkdir -p $out
      cp ${build.kernel}/${config.system.boot.loader.kernelFile} $out/bzImage
      cp ${build.netbootRamdisk}/initrd $out/initrd
      cp ${bootScript} $out/netboot.ipxe
      cp ${pkgs.ipxe.override {embedScript = ipxeEmbed;}}/{ipxe.efi,undionly.kpxe} $out/
    '';

    # Two modes. UEFI clients get ipxe.efi, legacy ones undionly.kpxe.
    #   default:  proxy-DHCP on a shared LAN; the existing router keeps handing
    #             out leases and dnsmasq only adds the PXE answer.
    #   --direct: a cable straight from the Mac to the target. dnsmasq is the
    #             only DHCP server there and hands out an address with no
    #             gateway or DNS, so the target's default route and internet
    #             stay on its other NIC (e.g. a USB adapter on the GN XPON).
    directAddr = "10.42.0.1";
    darwinCommand = pkgs.writeShellScript "pxe-serve-darwin" ''
      set -eu
      usage() {
        echo "usage: sudo nix run .#pxe-serve-darwin -- <bundle dir> [<interface>]" >&2
        echo "       sudo nix run .#pxe-serve-darwin -- <bundle dir> --direct <interface>" >&2
        echo "get the bundle: gh run download -n t1-netboot-bundle -D <dir> (see hosts/README.md)" >&2
        exit 2
      }
      [ "$#" -ge 1 ] && [ -f "$1/netboot.ipxe" ] || usage
      if [ "$(id -u)" -ne 0 ]; then
        echo "pxe-serve-darwin: DHCP/TFTP ports need root; re-run with sudo" >&2
        exit 1
      fi
      bundle="$(cd "$1" && pwd)"
      shift

      direct=0
      if [ "''${1:-}" = "--direct" ]; then
        [ "$#" -ge 2 ] || usage
        direct=1
        iface="$2"
      else
        iface="''${1:-$(/sbin/route -n get default | awk '/interface:/ {print $2}')}"
      fi

      work="$(mktemp -d "''${TMPDIR:-/tmp}/pxe-serve.XXXXXX")"
      cleanup() {
        [ -n "''${http_pid:-}" ] && kill "$http_pid" 2>/dev/null || true
        [ "$direct" -eq 1 ] && /sbin/ifconfig "$iface" inet ${directAddr} -alias 2>/dev/null || true
        rm -rf "$work"
      }
      trap cleanup EXIT INT TERM

      if [ "$direct" -eq 1 ]; then
        /sbin/ifconfig "$iface" inet ${directAddr} netmask 255.255.255.0 alias
        addr=${directAddr}
        dhcp="dhcp-range=10.42.0.100,10.42.0.150,255.255.255.0,1h
      dhcp-option=option:router
      dhcp-option=option:dns-server
      dhcp-leasefile=$work/leases"
      else
        addr="$(/usr/sbin/ipconfig getifaddr "$iface")"
        dhcp="dhcp-range=$addr,proxy"
      fi
      echo "pxe-serve-darwin: serving $bundle on $iface ($addr); Ctrl-C to stop"
      [ "$direct" -eq 1 ] && echo "the target's address shows up below as DHCPACK($iface) 10.42.0.1xx"

      cat > "$work/dnsmasq.conf" <<EOF
      port=0
      user=root
      interface=$iface
      bind-interfaces
      log-dhcp
      $dhcp
      dhcp-match=set:ipxe,175
      # iPXE's own DHCP request: point next-server at this Mac explicitly, which
      # is where the embedded script fetches netboot.ipxe from.
      dhcp-boot=tag:ipxe,netboot.ipxe,,$addr
      pxe-service=tag:!ipxe,X86-64_EFI,"t1-netboot",ipxe.efi
      pxe-service=tag:!ipxe,BC_EFI,"t1-netboot",ipxe.efi
      pxe-service=tag:!ipxe,x86PC,"t1-netboot",undionly.kpxe
      enable-tftp
      tftp-root=$bundle
      EOF

      ${lib.getExe pkgs.darkhttpd} "$bundle" --port ${toString httpPort} --addr "$addr" &
      http_pid=$!
      ${pkgs.dnsmasq}/bin/dnsmasq --no-daemon --conf-file="$work/dnsmasq.conf"
    '';
  in {
    packages = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      netboot-bundle = netbootBundle;
    };

    apps =
      lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        pxe-serve = {
          type = "app";
          program = toString command;
        };
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        pxe-serve-darwin = {
          type = "app";
          program = toString darwinCommand;
        };
      };
  };
}
