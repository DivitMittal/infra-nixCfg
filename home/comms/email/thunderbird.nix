{
  pkgs,
  inputs,
  ...
}: let
  tb = pkgs.nur.repos.rycee.thunderbird-addons;
  buildXpi = pkgs.nur.repos.rycee.lib.mozilla.mkBuildMozillaXpiAddon {inherit (pkgs) stdenv fetchurl;};
  markdown-here-revival = buildXpi {
    pname = "markdown-here-revival";
    version = "4.0.9.1";
    addonId = "markdown-here-revival@xul.calypsoblue.org";
    url = "https://addons.thunderbird.net/thunderbird/downloads/file/1044024/markdown_here_revival-4.0.9.1-tb.xpi?src=";
    sha256 = "17iy2c81pccbzcz572f84w7rz54zqh8ikn8gj662h9n370kakyv6";
    meta = {};
  };
in {
  imports = [
    inputs.infra-nixCfg-secrets.homeManagerConfigurations.tbAccounts
  ];

  programs.thunderbird = {
    enable = true;
    package = pkgs.thunderbird;

    profiles."main" = {
      isDefault = true;

      settings = {
        "extensions.autoDisableScopes" = 0;
      };

      extensions = [
        tb.send-later
        tb.provider-for-google-calendar
        markdown-here-revival
      ];
    };
  };
}
