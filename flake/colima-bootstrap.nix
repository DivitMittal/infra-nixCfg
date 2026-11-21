# Declarative NixOS-on-Lima bootstrap for the colima nixos-dev VM.
#
# Outputs exposed (darwin only):
#   packages.x86_64-darwin.colima-nixos-lima  — Lima YAML template (nix store path)
#   apps.x86_64-darwin.colima-nixos-start     — `nix run .#colima-nixos-start` to launch VM
#
# The disk image is accessed directly from the nixosConfiguration:
#   nix build .#nixosConfigurations.colima.config.system.build.diskoImages
# This requires a Linux builder — the default colima docker VM works:
#   nix build ... --builders 'ssh://user@192.168.5.2 x86_64-linux'
#
# Full bootstrap flow:
#   1. nix build .#nixosConfigurations.colima.config.system.build.diskoImages \
#        --builders 'ssh://user@<colima-vm-ip> x86_64-linux'
#   2. nix run .#colima-nixos-start
#   3. limactl shell colima-nixos -- home-manager switch --flake path:.#colima
{
  self,
  lib,
  ...
}: {
  perSystem = {
    system,
    pkgs,
    ...
  }:
    lib.optionalAttrs (system == "x86_64-darwin") (let
      # Reference the Linux derivation directly — its store path is computable
      # on darwin without building it. Do NOT route through perSystem.packages
      # to avoid triggering the x86_64-linux perSystem evaluation cycle.
      image = self.nixosConfigurations.colima.config.system.build.diskoImages;

      # Lima template — plain:true boots the raw NixOS disk directly,
      # skipping cloud-init so NixOS manages everything from first boot.
      limaTemplate = pkgs.writeText "colima-nixos.yaml" ''
        plain: true
        images:
          - location: "${image}/main.raw"
            arch: x86_64
        cpus: 4
        memory: "4GiB"
        mounts: []
        ssh:
          localPort: 0
          loadDotSSHPubKeys: true
        firmware:
          legacyBIOS: false
        networks:
          - lima: user-v2
        containerd:
          system: false
          user: false
      '';

      startScript = pkgs.writeShellApplication {
        name = "colima-nixos-start";
        runtimeInputs = [pkgs.lima pkgs.jq];
        text = ''
          NAME="colima-nixos"
          if limactl list --format json \
             | jq -e --arg n "$NAME" '.[] | select(.name == $n)' > /dev/null 2>&1; then
            echo "VM '$NAME' already exists — starting."
            limactl start "$NAME"
          else
            echo "Creating VM '$NAME' from NixOS disk image…"
            limactl start --name "$NAME" ${limaTemplate}
          fi
          echo ""
          echo "Connect:         limactl shell $NAME"
          echo "Apply home-mgr:  limactl shell $NAME -- home-manager switch --flake path:.#colima"
        '';
      };
    in {
      packages.colima-nixos-lima = limaTemplate;
      apps.colima-nixos-start = {
        type = "app";
        program = lib.getExe startScript;
      };
    });
}
