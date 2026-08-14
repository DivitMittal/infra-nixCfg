{pkgs, ...}: {
  # home.packages = lib.attrsets.attrValues {
  #   inherit
  #     (pkgs)
  #     powershell
  #     ;
  # };

  programs.nushell = {
    enable = true;
    package = pkgs.nushell;

    settings = {
      show_banner = false;

      edit_mode = "vi";
      cursor_shape = {
        vi_insert = "line";
        vi_normal = "block";
      };
    };
  };
}
