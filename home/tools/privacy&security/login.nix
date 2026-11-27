{
  config,
  hostPlatform,
  pkgs,
  ...
}: {
  home.packages = [pkgs.bitwarden-cli pkgs.cotp];

  programs.rbw = {
    enable = false;
    package = pkgs.rbw;

    settings = {
      email = config.hostSpec.email.personal;
      pinentry =
        if hostPlatform.isDarwin
        then pkgs.pinentry_mac
        else pkgs.pinentry;
    };
  };
}
