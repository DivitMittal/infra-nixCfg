{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.infra-nixCfg-secrets.homeManagerConfigurations.himalayaAccounts
  ];

  programs.himalaya = {
    enable = true;
    package = pkgs.himalaya.override {buildFeatures = ["oauth2"];};
  };
}
