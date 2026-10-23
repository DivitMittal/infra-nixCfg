{
  lib,
  pkgs,
  config,
  ...
}: {
  programs.awscli = {
    enable = false;
    package = pkgs.awscli2;

    settings = {
      "default" = {
        region = "ap-south-1";
        output = "json";
      };
    };
  };

  # Point oci-cli at XDG_CONFIG_HOME instead of the default ~/.oci/config. The
  # env var takes precedence over the hard-coded default per Oracle's
  # read_values_from_env callback in cli_util.py.
  home.sessionVariables.OCI_CLI_CONFIG_FILE = "${config.xdg.configHome}/oci/config";

  home.packages = lib.attrsets.attrValues {
    ## cloud-platforms-cli
    inherit
      (pkgs)
      oci-cli # Oracle Cloud Infrastructure CLI
      ovhcloud-cli # OVHcloud CLI
      ;
    #gcp = pkgs.google-cloud-sdk;

    wrangler = lib.custom.mkBunxBin "wrangler" "wrangler@latest";
  };
}
