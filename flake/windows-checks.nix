{self, ...}: {
  perSystem = {pkgs, ...}: {
    # Parse the actual Windows prompt files, including their TOML escaping.
    checks = pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
      windows-starship =
        pkgs.runCommand "windows-starship" {
          nativeBuildInputs = [pkgs.python3];
          l1 = pkgs.writeText "l1-starship.toml" self.winConfigurations.l1.config.win.files.".config/starship.toml".text;
          l2 = pkgs.writeText "l2-starship.toml" self.winConfigurations.l2.config.win.files.".config/starship.toml".text;
        } ''
          python - "$l1" "$l2" <<'PY'
          import sys
          import tomllib

          for path in sys.argv[1:]:
              with open(path, "rb") as config_file:
                  config = tomllib.load(config_file)
              assert "$line_break" in config["format"], path
              assert r"\($virtualenv\)" in config["python"]["format"], path
          PY
          touch "$out"
        '';
    };
  };
}
