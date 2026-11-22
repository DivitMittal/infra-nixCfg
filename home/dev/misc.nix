{
  pkgs,
  lib,
  hostPlatform,
  inputs,
  ...
}: {
  home.packages =
    lib.attrsets.attrValues {
      inherit
        (pkgs)
        ## General
        tokei
        ## Programming Languages
        #tree-sitter
        ## java
        #jdk gradle
        ## lua
        lua
        ;
      leetcode-tui = let
        upstream = inputs.leetcode-tui.packages.${hostPlatform.system}.default;
      in
        if hostPlatform.isLinux
        then
          upstream.override (old: {
            pkgs = old.pkgs.extend (_final: prev: {
              defaultCrateOverrides =
                prev.defaultCrateOverrides
                // {
                  onig_sys = attrs: let
                    previous = (prev.defaultCrateOverrides.onig_sys or (_: {})) attrs;
                  in
                    previous
                    // {
                      # Bundled Oniguruma uses pre-C23 ANYARGS callbacks; GCC 15
                      # defaults to C23, where empty parameter lists mean void.
                      CFLAGS = lib.concatStringsSep " " (lib.filter (flag: flag != "") [
                        (previous.CFLAGS or (attrs.CFLAGS or ""))
                        "-std=gnu17"
                      ]);
                    };
                };
            });
          })
        else upstream;
    }
    ++ lib.optionals hostPlatform.isDarwin [
      pkgs.xcodes
      (lib.custom.mkZbxBin "unxip")
    ];
}
