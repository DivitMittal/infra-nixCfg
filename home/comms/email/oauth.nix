{
  pkgs,
  config,
  lib,
  ...
}: {
  # Expose Google OAuth credentials as env vars by reading decrypted age files at shell startup.
  # pkgs/custom/mutt-oauth2 reads these at runtime for the Google registration,
  # so `oauth2` (and aerc/himalaya calling it) must inherit them from a shell.
  programs = let
    clientId = config.age.secrets."google/client_id.age".path;
    clientSecret = config.age.secrets."google/client_secret.age".path;
    posixInit = ''
      [ -r "${clientId}" ] && export GOOGLE_CLIENT_ID=$(< "${clientId}")
      [ -r "${clientSecret}" ] && export GOOGLE_CLIENT_SECRET=$(< "${clientSecret}")
    '';
  in {
    fish.shellInit = lib.mkIf config.programs.fish.enable ''
      if test -r "${clientId}"
        set -gx GOOGLE_CLIENT_ID (cat "${clientId}")
      end
      if test -r "${clientSecret}"
        set -gx GOOGLE_CLIENT_SECRET (cat "${clientSecret}")
      end
    '';
    bash.initExtra = lib.mkIf config.programs.bash.enable posixInit;
    zsh.initContent = lib.mkIf config.programs.zsh.enable posixInit;
  };

  home.packages = [
    # Usage (one-time per account):
    #   oauth2 ~/.local/share/oauth2/<email> --authorize
    #   Microsoft: registration → microsoft | flow → localhostauthcode or devicecode
    #   Google:    registration → google    | flow → localhostauthcode
    pkgs.custom.mutt-oauth2
  ];
}
