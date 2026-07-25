{
  pkgs,
  lib,
  config,
  ...
}: {
  home.packages = lib.attrsets.attrValues {
    inherit (pkgs) pnpm;
  };

  home.sessionVariables.PNPM_HOME = "${config.home.homeDirectory}/.local/share/pnpm";
  home.sessionPath = ["${config.home.sessionVariables.PNPM_HOME}"];

  # Silence Node's noisy "File descriptor N opened/closed in unmanaged mode"
  # warnings that surface when running one-off tools via `pnpm dlx`.
  home.sessionVariables.NODE_OPTIONS = "--no-warnings";

  # npm configuration
  programs.npm = {
    enable = true;
    package = pkgs.nodejs;
    settings = {
      fund = false; # Disable funding messages
      audit = false; # Disable audit warnings
    };
  };

  programs.bun = {
    enable = true;
    package = pkgs.bun;

    enableGitIntegration = true;

    settings = {
      telemetry = false;
    };
  };
}
