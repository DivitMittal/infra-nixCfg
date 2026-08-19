{
  inputs,
  self,
  ...
}: {
  perSystem = {
    pkgs,
    system,
    ...
  }: let
    # Forked TP-Link Easy Smart provider. The pinned branch includes upstream
    # PR #9's session-cookie fix plus a switch-wide 802.1Q mode resource used by
    # S1. Keep Terraform's source address as lucavb/tplink-easysmart to preserve
    # provider-state compatibility; only the Nix build source comes from the
    # fork. Replace this override with an upstream release once both fixes ship.
    # Fork: https://github.com/DivitMittal/terraform-provider-tplink-easysmart/tree/feat/vlan-8021q-mode
    tplinkProvider = pkgs.buildGoModule {
      pname = "terraform-provider-tplink-easysmart";
      version = "0.3.0-unstable-2026-08-09";
      src = pkgs.fetchFromGitHub {
        owner = "DivitMittal";
        repo = "terraform-provider-tplink-easysmart";
        rev = "148f15509c5d1545039deb48a9079e99270da4b9";
        hash = "sha256-IIaM+T8Kl4PJOzNSbTVL8iXoqQXwd8aYo6/Uj2rUAD8=";
      };
      vendorHash = "sha256-n1Mibw4hNQ58GanBCNPo4NgKlTOqEnAef9bKhYKCYC0=";
    };

    # Terraform CLI config pointing at the patched provider binary. dev_overrides
    # loads it directly, so no `terraform init` (and no registry/lock) is needed
    # for this provider.
    tplinkCliConfig = pkgs.writeText "tplink-dev.tfrc" ''
      provider_installation {
        dev_overrides {
          "registry.terraform.io/lucavb/tplink-easysmart" = "${tplinkProvider}/bin"
        }
        direct {}
      }
    '';

    switchS1Tf = inputs.terranix.lib.terranixConfiguration {
      inherit system;
      modules = [self.switchConfigurations.S1];
    };

    # Same age-encrypted store used for every other secret in this flake
    # (see common/home/age.nix); matches the "lan/S1.age" entry declared in
    # OS-nixCfg-secrets/secrets/manifest.nix (shared with R1, see openwrt.nix).
    switchS1Secret = inputs.OS-nixCfg-secrets + "/secrets/lan/S1.age";

    # Runs `terraform <mode> [extra args]` (mode defaults to "plan") against
    # S1's generated config, in a persistent state dir outside the repo.
    # Credentials are decrypted straight from OS-nixCfg-secrets with the
    # same agenix identity home-manager's ragenix module uses, rather than
    # being wired through Nix.
    switchS1Command = pkgs.writeShellScript "switch-S1-terraform" ''
      set -eu

      mode="''${1:-plan}"
      [ "$#" -gt 0 ] && shift

      identity="''${HOME}/.ssh/agenix/id_ed25519"
      [ -f "$identity" ] || {
        echo "missing agenix identity at $identity" >&2
        exit 1
      }

      work_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/os-nixcfg/terraform/switch-S1"
      mkdir -p "$work_dir"
      cp -f ${switchS1Tf} "$work_dir/config.tf.json"

      export TF_VAR_switch_s1_password="$(${pkgs.rage}/bin/rage --decrypt -i "$identity" ${switchS1Secret})"
      # Use the patched provider (see tplinkProvider). dev_overrides loads the
      # binary directly, so `terraform init` is neither needed nor wanted here.
      export TF_CLI_CONFIG_FILE=${tplinkCliConfig}

      cd "$work_dir"
      exec ${pkgs.terraform}/bin/terraform "$mode" "$@"
    '';
  in {
    packages = {
      switch-S1-tf = switchS1Tf;
      tplink-easysmart-provider = tplinkProvider;
    };

    apps.switch-S1 = {
      type = "app";
      program = toString switchS1Command;
    };
  };
}
