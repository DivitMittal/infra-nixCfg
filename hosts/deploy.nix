# Central deploy-rs registry for infra-nixCfg.
#
# Lives under ./hosts (not ./flake) because flake-parts modules imported via
# ./hosts reliably expose `flake.deploy.nodes` to the top-level `deploy`
# output, while `./flake` modules do not (empirically verified — the previous
# `flake/deploy.nix` registry was silently shadowed). flake-parts resolves
# `flake.deploy.nodes` with last-wins precedence across modules, so this file
# is the LAST entry in `hosts/default.nix`'s imports list to be the
# authoritative single source of truth for all deploy-rs nodes.
{
  inputs,
  self,
  ...
}: let
  username = inputs.infra-nixCfg-secrets.user.username;

  activateNixOnDroid = configuration:
    inputs.deploy-rs.lib.aarch64-linux.activate.custom
    configuration.activationPackage
    "${configuration.activationPackage}/activate";

  ## Windows hosts (winConfigurations.*, see flake/mkWinCfg.nix) don't fit
  ## deploy-rs's normal `activate.nixos`/`activate.home-manager` shapes —
  ## `system.build.toplevel` is PowerShell + data for nix-win's own CLI to
  ## apply, not something deploy-rs can exec directly on the remote host.
  ##
  ## Rather than have deploy-rs copy that closure at all (nix-win's CLI does
  ## its own `nix build` inside WSL anyway — copying it first would be
  ## redundant), this wraps a tiny script whose only job is to invoke
  ## nix-win's CLI, which does the real build+apply itself once it's
  ## running on the target. deploy-rs is used purely as the SSH trigger +
  ## rollback bookkeeping layer, not as the payload transport.
  ##
  ## CAVEATS (not yet validated against real hardware — L2 has no
  ## NixOS-WSL/nix-win set up yet as of this migration):
  ##   - Assumes the ssh target lands inside the host's WSL distro (not
  ##     Windows OpenSSH), with WSL/Windows interop enabled so `pwsh.exe`
  ##     resolves on PATH.
  ##   - `pwsh.exe` launched via interop runs as the Windows user that owns
  ##     that WSL instance. Machine-scope registry/env writes (see
  ##     common/hosts/win/settings.nix) need that session elevated —
  ##     plain SSH exec is NOT elevated, so an unattended `deploy` run will
  ##     fail on anything requiring Administrator until that's addressed
  ##     (e.g. a scheduled task registered with highest RunLevel, invoked
  ##     instead of calling pwsh.exe directly).
  ##   - magicRollback is off: deploy-rs's rollback mechanism assumes a
  ##     NixOS-style system profile on the ssh target itself, which doesn't
  ##     apply here — nix-win has its own generation/rollback under
  ##     %LOCALAPPDATA%\nix-win\ on the Windows side instead. Use
  ##     `nix-win rollback` directly on the host for that.
  mkWinActivate = {
    hostAttr,
    flakeUri,
  }: let
    nixWinCli = inputs.nix-win.packages.x86_64-linux.nix-win;
    activate = inputs.nixpkgs.legacyPackages.x86_64-linux.writeShellScript "activate-${hostAttr}" ''
      set -eu
      if command -v pwsh.exe >/dev/null 2>&1; then
        exec pwsh.exe -File "${nixWinCli}/nix-win.ps1" switch -FlakeUri "${flakeUri}" -FlakeAttr "winConfigurations.${hostAttr}"
      else
        echo "activate-${hostAttr}: no pwsh.exe on PATH — is this landing inside the host's WSL distro?" >&2
        exit 127
      fi
    '';
  in
    inputs.deploy-rs.lib.x86_64-linux.activate.custom activate "${activate}";

  activateHome = system: configuration:
    inputs.deploy-rs.lib.${system}.activate.home-manager configuration;

  # All home-lab boxes are x86_64-linux and built on the target, since the
  # workstation may be macOS.
  mkHomelabNode = hostname: configuration: {
    inherit hostname;
    profiles.system = {
      sshUser = "root";
      user = "root";
      remoteBuild = true;
      path = inputs.deploy-rs.lib.x86_64-linux.activate.nixos configuration;
      sshOpts = ["-i" "/Users/div/.ssh/agenix/id_ed25519" "-o" "StrictHostKeyChecking=accept-new"];
    };
  };

  mkDroidNode = {
    hostname,
    configuration,
    sshOpts,
  }: {
    inherit hostname;
    profiles.system = {
      sshUser = "nix-on-droid";
      user = "nix-on-droid";
      magicRollback = true;
      inherit sshOpts;
      path = activateNixOnDroid configuration;
    };
  };

  # Reached through `adb forward` (the devshell's <host>-adb-forward). Every
  # forwarded device is 127.0.0.1, so known_hosts needs a per-node alias.
  mkAdbDroidNode = {
    name,
    configuration,
    port,
    key,
  }:
    mkDroidNode {
      hostname = "127.0.0.1";
      inherit configuration;
      sshOpts = ["-p" (toString port) "-i" key "-o" "HostKeyAlias=${name}" "-o" "CheckHostIP=no"];
    };

  mkVpsHomeProfile = {
    system,
    configuration,
    sshOpts ? [],
  }: {
    profiles.home = {
      sshUser = username;
      user = username;
      inherit sshOpts;
      magicRollback = false;
      remoteBuild = true;
      path = activateHome system configuration;
    };
  };
in {
  flake.deploy.nodes = {
    # The phone, on Termux Launcher's Nix edition. Its fixed LAN address is a
    # router reservation (hosts/openwrt/T640); uid/gid are pinned in
    # hosts/droid/M1/M1.nix because the build happens off-device.
    M1 = mkDroidNode {
      hostname = "192.168.2.7";
      configuration = self.nixOnDroidConfigurations.M1;
      sshOpts = ["-p" "8022" "-i" "~/.ssh/agenix/id_ed25519" "-o" "HostKeyAlias=M1"];
    };

    M1-adb = mkAdbDroidNode {
      name = "M1-adb";
      configuration = self.nixOnDroidConfigurations.M1;
      port = 18022;
      key = "~/.ssh/agenix/id_ed25519";
    };

    # Home lab, reached over the LAN. T1's host address is static
    # (router-vm.nix); the rest resolve through the router's dnsmasq. Unlike
    # the VPSes, magicRollback stays on: a change that cuts SSH reverts by
    # itself instead of needing a trip to the box with a keyboard.
    T1 = mkHomelabNode "192.168.2.3" self.nixosConfigurations.T1;
    T2 = mkHomelabNode "T2.lan" self.nixosConfigurations.T2;
    T3 = mkHomelabNode "T3.lan" self.nixosConfigurations.T3;
    MON1 = mkHomelabNode "MON1.lan" self.nixosConfigurations.MON1;

    # Echo Show 5 running Termux Launcher (Nix edition). Same uid caveat as M1.
    E1 = mkDroidNode {
      hostname = "E1";
      configuration = self.nixOnDroidConfigurations.E1;
      sshOpts = ["-p" "8022" "-i" "~/.ssh/nix-on-droid-E1/ssh_host_rsa_key" "-o" "HostKeyAlias=E1"];
    };

    E1-adb = mkAdbDroidNode {
      name = "E1-adb";
      configuration = self.nixOnDroidConfigurations.E1;
      port = 18024;
      key = "~/.ssh/nix-on-droid-E1/ssh_host_rsa_key";
    };

    # Oracle Cloud A1 Flex VPS in Mumbai.
    VPS0 = {
      hostname = "80.225.249.202";
      profiles.system = {
        sshUser = "root";
        user = "root";
        magicRollback = false;
        remoteBuild = true;
        path =
          inputs.deploy-rs.lib.aarch64-linux.activate.nixos
          self.nixosConfigurations.VPS0;
        sshOpts = ["-i" "/Users/div/.ssh/agenix/id_ed25519" "-o" "StrictHostKeyChecking=accept-new"];
      };
    };

    "VPS0-home" =
      {
        hostname = "80.225.249.202";
      }
      // mkVpsHomeProfile {
        system = "aarch64-linux";
        configuration = self.homeConfigurations.VPS0;
        sshOpts = ["-i" "/Users/div/.ssh/agenix/id_ed25519" "-o" "StrictHostKeyChecking=accept-new"];
      };

    # Mumbai KVM VPS — deployed over the public NAT port
    # (public :20041 → internal :22). deploy-rs connects as root (key-only,
    # PermitRootLogin prohibit-password) and activates directly;
    # magicRollback disabled to avoid false rollbacks over the NAT path.
    VPS1 = {
      hostname = "148.113.8.216";
      profiles.system = {
        sshUser = "root";
        user = "root";
        sshOpts = ["-p" "20041"];
        magicRollback = false;
        remoteBuild = true;
        path =
          inputs.deploy-rs.lib.x86_64-linux.activate.nixos
          self.nixosConfigurations.VPS1;
      };
    };

    "VPS1-home" =
      {
        hostname = "148.113.8.216";
      }
      // mkVpsHomeProfile {
        system = "x86_64-linux";
        configuration = self.homeConfigurations.VPS1;
        sshOpts = ["-p" "20041"];
      };

    # Germany IPv6-only KVM VPS for server/background workloads.
    VPS2 = {
      hostname = "2a0e:97c0:3e3:34d::1";
      profiles.system = {
        sshUser = "root";
        user = "root";
        magicRollback = false;
        remoteBuild = true;
        path =
          inputs.deploy-rs.lib.x86_64-linux.activate.nixos
          self.nixosConfigurations.VPS2;
        sshOpts = ["-i" "/Users/div/.ssh/agenix/id_ed25519" "-o" "StrictHostKeyChecking=accept-new"];
      };
    };

    "VPS2-home" =
      {
        hostname = "2a0e:97c0:3e3:34d::1";
      }
      // mkVpsHomeProfile {
        system = "x86_64-linux";
        configuration = self.homeConfigurations.VPS2;
        sshOpts = ["-i" "/Users/div/.ssh/agenix/id_ed25519" "-o" "StrictHostKeyChecking=accept-new"];
      };

    # L2's Windows boot slot (user: vanee), via nix-win — see mkWinActivate
    # above for what this actually does and its untested caveats. ssh must
    # land inside L2's WSL distro, once one exists there (it doesn't yet —
    # see playbooks-4-windows' feat/nix-win-migration branch for the
    # remaining Ansible-driven bootstrap that has to happen first).
    l2-windows = {
      hostname = "192.168.2.6"; # T640 router reservation (L2-eth)
      profiles.system = {
        sshUser = "vanee";
        user = "vanee";
        magicRollback = false;
        path = mkWinActivate {
          hostAttr = "l2";
          flakeUri = "github:DivitMittal/OS-nixCfg";
        };
      };
    };
  };
}
