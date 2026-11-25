{pkgs, ...}: {
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
