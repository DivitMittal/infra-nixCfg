{lib, ...}: {
  # The installable must be a string, not a derivation: only the launcher is
  # retained by the profile. nix run fetches/builds the target on first use.
  mkNixRunBin = pkgs: name: installable:
    pkgs.writeShellScriptBin name ''
      exec nix run ${lib.escapeShellArg installable} -- "$@"
    '';

  # Creates a $out/bin/<formula> that runs a Homebrew formula ephemerally via zerobrew.
  # Darwin-only: pkgs.customDarwin must be present.
  mkZbxBin = pkgs: formula:
    pkgs.writeShellScriptBin formula ''
      exec ${pkgs.customDarwin.zerobrew-bin}/bin/zbx ${formula} "$@"
    '';

  # Creates a $out/bin/<name> that ephemerally runs a Python tool via `uv tool run`.
  # Equivalent to `uvx <args>`. Uses pkgs.uv from nixpkgs.
  mkUvxBin = pkgs: name: args:
    pkgs.writeShellScriptBin name ''
      exec ${pkgs.uv}/bin/uv tool run ${args} "$@"
    '';

  # Runs an npm CLI on demand. Keep Node available for executables that use
  # a Node shebang rather than forcing them to run under Bun.
  mkBunxBin = pkgs: name: pkg:
    pkgs.writeShellScriptBin name ''
      export PATH=${lib.makeBinPath [pkgs.nodejs]}:"$PATH"
      exec ${pkgs.bun}/bin/bunx --package ${lib.escapeShellArg pkg} ${lib.escapeShellArg name} "$@"
    '';

  ## Intro: Scans a directory and returns a list of paths to all Nix modules (directories or .nix files)
  ## excluding the default.nix file in the scanned directory itself.
  ## Performance note: This function calls builtins.readDir which is evaluated at parse time.
  ## The results are effectively memoized per unique path by Nix's evaluation caching,
  ## so multiple calls with the same path don't re-read the directory.
  ## Returns: List of absolute paths like [ /path/to/dir/module1.nix /path/to/dir/subdir ]
  ## Replaced by inputs.import-tree — see github:vic/import-tree
  scanPaths = _path: let
    entries = builtins.readDir _path;
    filteredEntries =
      lib.attrsets.filterAttrs (
        name: type:
          (type == "directory") || ((name != "default.nix") && (lib.strings.hasSuffix ".nix" name))
      )
      entries;
  in
    lib.lists.map (name: _path + "/${name}") (lib.attrsets.attrNames filteredEntries);
}
