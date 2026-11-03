{
  pkgs,
  hostPlatform,
  lib,
  ...
}: {
  home.packages = lib.attrsets.attrValues {
    ## Parametric CAD
    freecad =
      if hostPlatform.isDarwin
      then pkgs.brewCasks.freecad
      else pkgs.freecad;

    ## Mesh modelling, sculpting & rendering
    blender =
      if hostPlatform.isDarwin
      then pkgs.brewCasks.blender
      else pkgs.blender;

    ## Python CAD (build123d), not packaged in nixpkgs. Runs Python in an
    ## ephemeral uv env with build123d + ocp_vscode, so `show()` works with the
    ## OCP CAD Viewer (`python -m ocp_vscode` for the standalone viewer)
    build123d = pkgs.writeShellScriptBin "build123d" ''
      exec ${pkgs.uv}/bin/uv run --no-project --with build123d --with ocp_vscode python "$@"
    '';
  };
}
