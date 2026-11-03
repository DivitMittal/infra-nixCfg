{lib, ...}: {
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

  # Creates a $out/bin/<name> that ephemerally runs a JS package via `bun x`.
  # Equivalent to `bunx <pkg>`. Uses pkgs.bun from nixpkgs. Not `pnpm dlx`:
  # pnpm (10 and 11) aborts node on darwin while installing
  # (`Assertion failed: (errno == EINTR), function uv__io_poll, file kqueue.c`).
  mkBunxBin = pkgs: name: pkg:
    pkgs.writeShellScriptBin name ''
      exec ${pkgs.bun}/bin/bun x ${pkg} "$@"
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
