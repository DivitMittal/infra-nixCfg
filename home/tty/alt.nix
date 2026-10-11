{
  pkgs,
  lib,
  config,
  ...
}: {
  home.packages = lib.attrsets.attrValues {
    inherit
      (pkgs)
      duf # df alt
      dust # du alt
      cyme # lsusb alt
      caligula # dd alt
      choose # cut alt
      tree # ls tree alt
      ;
  };

  ## fc alt
  programs.pay-respects = {
    enable = true;
    package = pkgs.pay-respects;

    enableFishIntegration = config.programs.fish.enable;
    enableZshIntegration = config.programs.zsh.enable;
    enableBashIntegration = false;
    enableNushellIntegration = config.programs.nushell.enable;
  };

  programs.eza = {
    enable = true;
    package = pkgs.eza;

    enableFishIntegration = config.programs.fish.enable;
    enableZshIntegration = config.programs.zsh.enable;
    enableBashIntegration = false;
    enableNushellIntegration = config.programs.nushell.enable;
    git = true;

    # creates shell alias for ls
    extraOptions = [
      "--all"
      "--classify"
      "--icons=always"
      "--group-directories-first"
      "--hyperlink"
      "--color=always"
      "--color-scale"
      "--color-scale-mode=gradient"
    ];
  };

  home.shellAliases = let
    ov = "${pkgs.ov}/bin/ov -H1";
    eza = "${pkgs.eza}/bin/eza";
  in {
    ll = "${eza} -albhHigUuS -m@ --color=always | ${ov}";
    lt = "${eza} --tree --level=2 --color=always | ${ov}";
  };
}
