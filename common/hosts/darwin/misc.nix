{
  self,
  config,
  lib,
  pkgs,
  ...
}: {
  system.stateVersion = lib.mkDefault 6;

  networking = {
    knownNetworkServices = ["Wi-Fi"];
    dns = [
      ## Cloudflare DNS
      # IPv4
      "1.1.1.1"
      "1.0.0.1"
      # IPv6
      "2606:4700:4700::1111"
      "2606:4700:4700::1001"
    ];
    computerName = "${config.networking.hostName}";
  };

  # Block Spotify's auto-updater to preserve spicetify patches.
  # nix-darwin has no `networking.hosts` (that's NixOS-only) and taking over
  # /etc/hosts via `environment.etc.hosts` aborts activation unless its current
  # hash is whitelisted, so apply the block with an idempotent activation script.
  system.activationScripts.spicetifyHosts.text = ''
    # Remove any previously applied block, then (re)append the current one.
    if [ -f /etc/hosts ]; then
      tmp="$(mktemp)"
      grep -v \
        -e "upgrade.scdn.co" \
        -e "upgrade-clientmanifest.scdn.co" \
        -e "# nix-darwin:spicetify-auto-update" \
        /etc/hosts > "$tmp" || true
      cat "$tmp" > /etc/hosts
      rm -f "$tmp"
    fi
    printf "\n# nix-darwin:spicetify-auto-update block\n0.0.0.0 upgrade.scdn.co\n0.0.0.0 upgrade-clientmanifest.scdn.co\n" >> /etc/hosts
  '';

  #environment.darwinConfig = self + "/hosts/darwin/${config.networking.hostName}/default.nix"; # non-flake feature(adds darwin to $NIX_PATH)
  system.primaryUser = "${config.hostSpec.username}";
  system.tools = {
    darwin-option.enable = true;
    darwin-rebuild.enable = true;
    darwin-uninstaller.enable = true;
    darwin-version.enable = true;
  };
  system.checks = {
    verifyBuildUsers = true;
    verifyNixPath = false;
  };
  system.configurationRevision = self.rev or self.dirtyRev or null;

  environment.systemPackages = lib.attrsets.attrValues {
    inherit
      (pkgs)
      blueutil # bluetooth cli
      ;
    inherit
      (pkgs.customDarwin)
      tccutil # macOS TCC/privacy permissions cli
      zerobrew-bin
      ;

    brew-ultimate = pkgs.writeShellScriptBin "brew-ultimate" ''
      echo "Running brew update..."
      brew update

      echo "Running brew upgrade..."
      brew upgrade

      echo "Running brew autoremove..."
      brew autoremove

      echo "Running brew cleanup..."
      brew cleanup -s --prune=0

      echo "Removing brew cache..."
      rm -rf "$(brew --cache)"

      echo "Brew maintenance complete!"
    '';
  };

  environment.variables = {
    ## Fix SSL certificate verification (including for Homebrew)
    SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
    GIT_SSL_CAINFO = "/etc/ssl/certs/ca-certificates.crt";
  };

  ## Create system-level gitconfig to fix SSL for all git instances (including Homebrew's)
  environment.etc."gitconfig".text = ''
    [http]
      sslCAInfo = /etc/ssl/certs/ca-certificates.crt
  '';
}
