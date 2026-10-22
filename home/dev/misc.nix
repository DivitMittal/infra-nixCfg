{
  pkgs,
  lib,
  hostPlatform,
  inputs,
  ...
}: {
  home.packages =
    lib.attrsets.attrValues ({
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
      }
      # leetcode-tui builds from its own nixpkgs, which throws on x86_64-darwin
      # (Nixpkgs 26.11+), and Nixpkgs doesn't package it.
      // lib.attrsets.optionalAttrs (!(hostPlatform.isDarwin && hostPlatform.isx86_64)) {
        leetcode-tui = inputs.leetcode-tui.packages.${hostPlatform.system}.default;
      })
    ++ lib.optionals hostPlatform.isDarwin [
      pkgs.xcodes
      (lib.custom.mkZbxBin "unxip")
    ];
}
