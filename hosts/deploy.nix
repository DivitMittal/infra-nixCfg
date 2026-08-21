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
  username = inputs.OS-nixCfg-secrets.user.username;

  activateNixOnDroid = configuration:
    inputs.deploy-rs.lib.aarch64-linux.activate.custom
    configuration.activationPackage
    "${configuration.activationPackage}/activate";

  activateHome = system: configuration:
    inputs.deploy-rs.lib.${system}.activate.home-manager configuration;

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
    # nix-on-droid device on the local network
    M1 = {
      hostname = "M1";
      profiles.system = {
        sshUser = "nix-on-droid";
        user = "nix-on-droid";
        magicRollback = true;
        sshOpts = ["-p" "8022"];
        path = activateNixOnDroid self.nixOnDroidConfigurations.M1;
      };
    };

    # nix-on-droid device over ADB-forwarded SSH
    M1-adb = {
      hostname = "127.0.0.1";
      profiles.system = {
        sshUser = "nix-on-droid";
        user = "nix-on-droid";
        magicRollback = true;
        sshOpts = [
          "-p"
          "18022"
          "-i"
          "~/.ssh/nix-on-droid/ssh_host_rsa_key"
          "-o"
          "HostKeyAlias=M1-adb"
          "-o"
          "CheckHostIP=no"
        ];
        path = activateNixOnDroid self.nixOnDroidConfigurations.M1;
      };
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
  };
}
