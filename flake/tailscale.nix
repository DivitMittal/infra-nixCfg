{inputs, ...}: {
  perSystem = {
    pkgs,
    system,
    ...
  }: let
    configuration = inputs.terranix.lib.terranixConfiguration {
      inherit system;
      modules = [../network/tailscale/personal.nix];
    };
    command = pkgs.writeShellApplication {
      name = "tailscale-personal";
      runtimeInputs = [pkgs.opentofu pkgs.python3 pkgs.rage];
      text = ''
        export TAILSCALE_TF_CONFIG=${configuration}
        export TAILSCALE_TF_LOCK=${../network/tailscale/.terraform.lock.hcl}
        exec python3 ${../network/tailscale/manage.py} "$@"
      '';
    };
  in {
    packages.tailscale-personal-tf = configuration;
    checks.tailscale-operations =
      pkgs.runCommand "tailscale-operations" {
        nativeBuildInputs = [pkgs.python3];
      } ''
        cp -r ${../network/tailscale} tailnet
        chmod -R u+w tailnet
        python3 -m unittest discover -s tailnet -p 'test_*.py'
        touch "$out"
      '';
    apps.tailscale-personal = {
      type = "app";
      program = "${command}/bin/tailscale-personal";
    };
  };
}
