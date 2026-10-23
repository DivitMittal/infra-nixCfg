{
  inputs,
  self,
  ...
}: {
  perSystem = {pkgs, ...}: let
    # nixpkgs mirrors the real registry provider binary (ovh/ovh, a normal
    # published Terraform provider), so dev_overrides here just pins it for
    # reproducibility and skips a network `terraform init`.
    ovhProvider = pkgs.terraform-providers.ovh_ovh;
    ociProvider = pkgs.terraform-providers.oci;
    ovhCliConfig = pkgs.writeText "ovh-dev.tfrc" ''
      provider_installation {
        dev_overrides {
          "registry.terraform.io/ovh/ovh" = "${ovhProvider}/libexec/terraform-providers/registry.terraform.io/ovh/ovh/${ovhProvider.version}/${pkgs.go.GOOS}_${pkgs.go.GOARCH}"
        }
        direct {}
      }
    '';
    ociCliConfig = pkgs.writeText "oci-dev.tfrc" ''
      provider_installation {
        dev_overrides {
          "registry.terraform.io/oracle/oci" = "${ociProvider}/libexec/terraform-providers/registry.terraform.io/oracle/oci/${ociProvider.version}/${pkgs.go.GOOS}_${pkgs.go.GOARCH}"
        }
        direct {}
      }
    '';

    cloudVPS1Tf = inputs.terranix.lib.terranixConfiguration {
      inherit pkgs;
      modules = [self.cloudConfigurations.VPS1];
    };
    cloudVPS0Tf = inputs.terranix.lib.terranixConfiguration {
      inherit pkgs;
      modules = [self.cloudConfigurations.VPS0];
    };

    # OVH API credentials for commissioning VPS1 (see hosts/cloud/VPS1/default.nix).
    # These must be created by hand in infra-nixCfg-secrets first.
    cloudC1ApplicationKeySecret = inputs.infra-nixCfg-secrets + "/secrets/cloud/ovh-application-key.age";
    cloudC1ApplicationSecretSecret = inputs.infra-nixCfg-secrets + "/secrets/cloud/ovh-application-secret.age";
    cloudC1ConsumerKeySecret = inputs.infra-nixCfg-secrets + "/secrets/cloud/ovh-consumer-key.age";

    # Permanent OCI API signing key for commissioning VPS0 (see
    # hosts/cloud/VPS0/default.nix) — the public half is uploaded to the
    # OCI user via `oci iam user api-key upload`.
    cloudO1PrivateKeySecret = inputs.infra-nixCfg-secrets + "/secrets/cloud/oci-api-key.age";

    # Runs `terraform <mode> [extra args]` (mode defaults to "plan") against
    # C1's generated config. ovh_subsidiary has no default (see
    # hosts/cloud/VPS1/default.nix) so it must be passed on every invocation,
    # e.g.: nix run .#cloud-C1 -- plan -var='ovh_subsidiary=IE'
    cloudVPS1Command = pkgs.writeShellScript "cloud-VPS1-terraform" ''
      set -eu

      mode="''${1:-plan}"
      [ "$#" -gt 0 ] && shift

      identity="''${HOME}/.ssh/agenix/id_ed25519"
      [ -f "$identity" ] || {
        echo "missing agenix identity at $identity" >&2
        exit 1
      }

      work_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/os-nixcfg/terraform/cloud-VPS1"
      mkdir -p "$work_dir"
      cp -f ${cloudVPS1Tf} "$work_dir/config.tf.json"

      export TF_VAR_ovh_application_key="$(${pkgs.rage}/bin/rage --decrypt -i "$identity" ${cloudC1ApplicationKeySecret})"
      export TF_VAR_ovh_application_secret="$(${pkgs.rage}/bin/rage --decrypt -i "$identity" ${cloudC1ApplicationSecretSecret})"
      export TF_VAR_ovh_consumer_key="$(${pkgs.rage}/bin/rage --decrypt -i "$identity" ${cloudC1ConsumerKeySecret})"
      export TF_CLI_CONFIG_FILE=${ovhCliConfig}

      cd "$work_dir"
      exec ${pkgs.terraform}/bin/terraform "$mode" "$@"
    '';
    cloudVPS0Command = pkgs.writeShellScript "cloud-VPS0-terraform" ''
      set -eu
      mode="''${1:-plan}"
      [ "$#" -gt 0 ] && shift

      identity="''${HOME}/.ssh/agenix/id_ed25519"
      [ -f "$identity" ] || {
        echo "missing agenix identity at $identity" >&2
        exit 1
      }

      work_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/os-nixcfg/terraform/cloud-VPS0"
      mkdir -p "$work_dir"
      cp -f ${cloudVPS0Tf} "$work_dir/config.tf.json"

      key_file="$(mktemp)"
      trap 'rm -f "$key_file"' EXIT
      ${pkgs.rage}/bin/rage --decrypt -i "$identity" ${cloudO1PrivateKeySecret} > "$key_file"
      chmod 600 "$key_file"
      export TF_VAR_oci_private_key_path="$key_file"
      export TF_CLI_CONFIG_FILE=${ociCliConfig}

      cd "$work_dir"
      exec ${pkgs.terraform}/bin/terraform "$mode" "$@"
    '';
  in {
    packages = {
      cloud-VPS1-tf = cloudVPS1Tf;
      cloud-VPS0-tf = cloudVPS0Tf;
    };

    apps.cloud-VPS1 = {
      type = "app";
      program = toString cloudVPS1Command;
    };
    apps.cloud-VPS0 = {
      type = "app";
      program = toString cloudVPS0Command;
    };
  };
}
