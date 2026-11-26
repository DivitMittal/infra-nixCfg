{
  pkgs,
  lib,
  inputs,
  ...
}: {
  imports = [
    inputs.infra-nixCfg-secrets.homeManagerConfigurations.himalayaAccounts
  ];

  # home-manager's module emits himalaya v2 config. OAuth2 is plain SASL
  # xoauth2 with a token command (mutt-oauth2), so no oauth2 build feature.
  programs.himalaya = {
    enable = true;
    package =
      if pkgs.stdenv.hostPlatform.isDarwin && !(lib.versionAtLeast pkgs.himalaya.version "2")
      then pkgs.customDarwin.himalaya-bin
      else pkgs.himalaya;
  };
}
